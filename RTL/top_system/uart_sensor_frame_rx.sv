`timescale 1ns / 1ps

// ============================================================================
// uart_sensor_frame_rx
// ============================================================================
// Substitui o spi_sensor_frame_rx quando a ingestao de sensores passa de SPI
// para UART.
//
// POR QUE ESTE MODULO PRECISOU EXISTIR
// ------------------------------------
// O SPI entregava o delimitador de quadro de graca: uma asserção de
// slave_select_n = uma epoca de aquisicao. O spi_sensor_frame_rx so precisava
// contar bytes enquanto "spi_selected" estivesse ativo.
//
// UART nao tem esse sinal. E um fluxo de bytes sem inicio nem fim, entao o
// enquadramento precisa ser construido no protocolo. Este modulo usa tres
// mecanismos, todos necessarios:
//
//   1) PALAVRA DE SINCRONISMO (SYNC0, SYNC1) marca o inicio do quadro.
//   2) CHECKSUM (XOR de todos os bytes de payload) detecta corrupcao. Numa
//      linha serial assincrona nao ha clock compartilhado; um unico glitch
//      desloca todos os bytes seguintes. Sem checksum, lixo entraria no
//      pipeline de inferencia como se fosse dado bom.
//   3) TIMEOUT DE OCIOSIDADE ressincroniza se o transmissor parar no meio de
//      um quadro. Sem isso, uma unica interrupcao deixaria o receptor
//      travado esperando bytes que nunca chegam.
//
// FORMATO DO QUADRO (padrao: 30 bytes)
// ------------------------------------
//   [0]      SYNC0                     (0xA5)
//   [1]      SYNC1                     (0x5A)
//   [2..28]  payload: N_SENSORS palavras de BYTES_PER_WORD bytes,
//            MSB primeiro (big-endian), na ordem
//              0..3 = vibracao, 4..6 = corrente, 7..8 = temperatura
//   [29]     checksum = XOR de todos os bytes de payload
//
// GARANTIA DE INTEGRIDADE
// -----------------------
// sensor_data so e atualizado quando um quadro passa no checksum. Um quadro
// corrompido nunca aparece na saida -- importante porque aux_features (a
// parte de corrente/temperatura) e lida combinacionalmente do sensor_data
// pelo coletor do MLP, ou seja, NAO e protegida por frame_valid. Se
// escrevessemos direto em sensor_data, lixo de um quadro rejeitado poderia
// ser amostrado pelo MLP.
// ============================================================================
module uart_sensor_frame_rx #(
    parameter int DATA_WIDTH     = 24,
    parameter int N_SENSORS      = 9,
    parameter int BYTES_PER_WORD = DATA_WIDTH/8,

    parameter logic [7:0] SYNC0 = 8'hA5,
    parameter logic [7:0] SYNC1 = 8'h5A,

    // Timeout de ressincronizacao, expresso em tempos de byte da linha
    parameter int CLK_FREQ_HZ        = 50_000_000,
    parameter int BAUD_RATE          = 115_200,
    parameter int IDLE_TIMEOUT_BYTES = 4
)(
    input  logic clk,
    input  logic reset,

    // Interface com o receptor UART (receiver.sv)
    input  logic [7:0] rx_data,
    input  logic       rx_ready,
    output logic       rx_ready_clr,

    // Mesma interface de saida do antigo spi_sensor_frame_rx
    output logic signed [DATA_WIDTH-1:0] sensor_data [0:N_SENSORS-1],
    output logic                         frame_valid,   // pulso de 1 ciclo
    output logic                         frame_error    // pulso de 1 ciclo
);

    localparam int BIT_CYCLES    = CLK_FREQ_HZ / BAUD_RATE;          // 434
    localparam int TIMEOUT_CYC   = BIT_CYCLES * 10 * IDLE_TIMEOUT_BYTES;
    localparam int IDLE_W        = $clog2(TIMEOUT_CYC + 1);

    // ------------------------------------------------------------------
    // Consumo de bytes do receptor UART
    // ------------------------------------------------------------------
    // O receiver mantem "ready" alto ate receber "ready_clr", e nao tem FIFO:
    // um byte novo sobrescreve o anterior. Consumimos em ~3 ciclos de clock,
    // contra ~4340 ciclos por byte na linha, entao nunca ha overrun.
    typedef enum logic {B_IDLE, B_CLR} byte_state_e;
    byte_state_e byte_state;

    logic [7:0] byte_data;
    logic       byte_valid;   // pulso de 1 ciclo por byte recebido

    always_ff @(posedge clk) begin
        if (reset) begin
            byte_state   <= B_IDLE;
            byte_data    <= 8'd0;
            byte_valid   <= 1'b0;
            rx_ready_clr <= 1'b0;
        end else begin
            byte_valid   <= 1'b0;
            rx_ready_clr <= 1'b0;

            unique case (byte_state)
                B_IDLE: begin
                    if (rx_ready) begin
                        byte_data    <= rx_data;
                        byte_valid   <= 1'b1;
                        rx_ready_clr <= 1'b1;
                        byte_state   <= B_CLR;
                    end
                end
                B_CLR: begin
                    if (!rx_ready) byte_state <= B_IDLE;
                end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // FSM de enquadramento
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_SYNC0,    // procurando o primeiro byte de sincronismo
        S_SYNC1,    // procurando o segundo
        S_PAYLOAD,  // recebendo as N_SENSORS palavras
        S_CKSUM,    // recebendo e conferindo o checksum
        S_COMMIT    // publicando o quadro (1 ciclo)
    } state_e;

    state_e state;

    logic signed [DATA_WIDTH-1:0] frame_buf [0:N_SENSORS-1];
    logic        [DATA_WIDTH-1:0] word_sr;
    logic [$clog2(N_SENSORS)-1:0]      word_idx;
    logic [$clog2(BYTES_PER_WORD+1)-1:0] byte_idx;
    logic [7:0]        cksum;
    logic [IDLE_W-1:0] idle_cnt;

    // Palavra sendo montada, MSB primeiro
    logic [DATA_WIDTH-1:0] next_word;
    assign next_word = {word_sr[DATA_WIDTH-9:0], byte_data};

    always_ff @(posedge clk) begin
        automatic logic timeout_resync;
        if (reset) begin
            state       <= S_SYNC0;
            word_sr     <= '0;
            word_idx    <= '0;
            byte_idx    <= '0;
            cksum       <= 8'd0;
            idle_cnt    <= '0;
            frame_valid <= 1'b0;
            frame_error <= 1'b0;
            for (int i = 0; i < N_SENSORS; i++) begin
                frame_buf[i]   <= '0;
                sensor_data[i] <= '0;
            end
        end else begin
            frame_valid <= 1'b0;
            frame_error <= 1'b0;

            // ---- Timeout de ociosidade: so conta dentro de um quadro ----
            // Um unico "timeout_resync" evita que este bloco e o case abaixo
            // disputem a atribuicao de "state" no mesmo ciclo.
            timeout_resync = 1'b0;
            if (byte_valid) begin
                idle_cnt <= '0;
            end else if (state != S_SYNC0 && state != S_COMMIT) begin
                if (idle_cnt == IDLE_W'(TIMEOUT_CYC)) timeout_resync = 1'b1;
                else                                  idle_cnt <= idle_cnt + 1'b1;
            end

            if (timeout_resync) begin
                // Transmissor parou no meio do quadro: volta a cacar sync
                state       <= S_SYNC0;
                idle_cnt    <= '0;
                frame_error <= 1'b1;
            end
            else begin
              unique case (state)
                S_SYNC0: begin
                    if (byte_valid && byte_data == SYNC0)
                        state <= S_SYNC1;
                end

                S_SYNC1: begin
                    if (byte_valid) begin
                        if (byte_data == SYNC1) begin
                            state    <= S_PAYLOAD;
                            word_idx <= '0;
                            byte_idx <= '0;
                            cksum    <= 8'd0;
                        end else if (byte_data == SYNC0) begin
                            state <= S_SYNC1;   // 0xA5 0xA5 0x5A ainda sincroniza
                        end else begin
                            state <= S_SYNC0;
                        end
                    end
                end

                S_PAYLOAD: begin
                    if (byte_valid) begin
                        word_sr <= next_word;
                        cksum   <= cksum ^ byte_data;

                        if (byte_idx == BYTES_PER_WORD-1) begin
                            frame_buf[word_idx] <= $signed(next_word);
                            byte_idx <= '0;
                            if (int'(word_idx) == N_SENSORS-1) begin
                                word_idx <= '0;
                                state    <= S_CKSUM;
                            end else begin
                                word_idx <= word_idx + 1'b1;
                            end
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end
                end

                S_CKSUM: begin
                    if (byte_valid) begin
                        if (byte_data == cksum) begin
                            state <= S_COMMIT;
                        end else begin
                            // Quadro rejeitado: sensor_data permanece com o
                            // ultimo quadro BOM, nunca com lixo.
                            frame_error <= 1'b1;
                            state       <= S_SYNC0;
                        end
                    end
                end

                S_COMMIT: begin
                    for (int i = 0; i < N_SENSORS; i++)
                        sensor_data[i] <= frame_buf[i];
                    frame_valid <= 1'b1;
                    state       <= S_SYNC0;
                end

                default: state <= S_SYNC0;
              endcase
            end
        end
    end

endmodule
