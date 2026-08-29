// =============================================================================
// Module : transmitter
// Descricao:
//   Transmissor UART. Envia um byte serialmente (start bit, 8 bits de dado,
//   stop bit), avancando um bit por pulso de "clk_en" (que deve chegar na
//   taxa de baud, 1x -- diferente do receptor, que usa 16x).
//
// Notas de conversao:
//   - "reg"/"wire" -> "logic"; estados definidos com "typedef enum".
//   - "always @(posedge clk)" -> "always_ff @(posedge clk)".
//   - Adicionado reset sincrono ATIVO EM ALTO (rst) no lugar do
//     "initial begin Tx = 1'b1; end", que so e garantido em simulacao.
//   - Tx_en mantido ATIVO EM BAIXO, exatamente como no codigo original
//     ("if (~Tx_en) ..." no estado IDLE): nivel baixo em Tx_en inicia a
//     transmissao. Ajuste a polaridade no sinal de entrada se preferir
//     um Tx_en ativo em alto.
// =============================================================================

module transmitter (
    input  logic        clk,   // Clock do sistema
    input  logic        rst,     // Reset sincrono, ATIVO EM ALTO
    input  logic        clk_en,     // Pulso de habilitacao na taxa de baud (1x)
    input  logic [7:0]  data_in,   // Byte a ser transmitido
    input  logic        tx_en,     // Dispara transmissao (ativo em baixo, ver nota acima)
    output logic        tx,        // Saida serial
    output logic        tx_busy    // Alto enquanto uma transmissao esta em andamento
);

    typedef enum logic [1:0] {
        TX_STATE_IDLE  = 2'b00,
        TX_STATE_START = 2'b01,
        TX_STATE_DATA  = 2'b10,
        TX_STATE_STOP  = 2'b11
    } tx_state_e;

    tx_state_e  state;
    logic [7:0] data;      // Copia local do byte sendo transmitido
    logic [2:0] bit_pos;   // Indice do bit de dado atual (0..7)

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= TX_STATE_IDLE;
            tx      <= 1'b1;      // Linha em repouso = nivel alto
            data    <= 8'h00;
            bit_pos <= 3'h0;
        end else begin
            case (state)
                TX_STATE_IDLE: begin
                    // Nao depende de "clk_en": comeca assim que Tx_en for ativado
                    if (~tx_en) begin
                        state   <= TX_STATE_START;
                        data    <= data_in;
                        bit_pos <= 3'h0;
                    end
                end

                TX_STATE_START: begin
                    if (clk_en) begin
                        tx    <= 1'b0;          // Start bit
                        state <= TX_STATE_DATA;
                    end
                end

                TX_STATE_DATA: begin
                    if (clk_en) begin
                        tx      <= data[bit_pos];
                        bit_pos <= bit_pos + 3'h1;
                        if (bit_pos == 3'h7)
                            state <= TX_STATE_STOP;
                    end
                end

                TX_STATE_STOP: begin
                    if (clk_en) begin
                        tx    <= 1'b1;          // Stop bit
                        state <= TX_STATE_IDLE;
                    end
                end

                default: begin
                    tx    <= 1'b1;
                    state <= TX_STATE_IDLE;
                end
            endcase
        end
    end

    assign tx_busy = (state != TX_STATE_IDLE);

endmodule
