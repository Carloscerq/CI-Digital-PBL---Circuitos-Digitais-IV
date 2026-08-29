// =============================================================================
// Module : receiver
// Descricao:
//   Receptor UART baseado em maquina de estados (FSM), com sobreamostragem
//   (oversampling) de 16x para sincronizar com o bit de start e reduzir o
//   efeito de jitter/metaestabilidade no sinal serial Rx.
//
// Notas de conversao (Verilog-2001 -> SystemVerilog):
//   - "reg"/"wire" trocados por "logic" (tipagem SystemVerilog).
//   - Estados definidos com "typedef enum" em vez de "parameter" solto,
//     o que da checagem de tipo em tempo de compilacao e facilita leitura
//     em simulador/waveform.
//   - "always @(posedge clk)" trocado por "always_ff @(posedge clk)",
//     que e a forma recomendada em SV para logica sequencial sintetizavel
//     (o compilador aponta erro se alguma atribuicao acidental virar latch).
//   - O "initial begin ... end" original so garante o valor inicial em
//     SIMULACAO (e, por sorte, em alguns fabricantes de FPGA tambem no
//     power-up). Foi adicionado um reset sincrono ATIVO EM NIVEL
//     ALTO (rst) para garantir um estado conhecido em qualquer FPGA/ASIC e
//     apos qualquer reset de sistema, sem depender de "initial".
//   - Atencao: rx_en e testado como ATIVO EM BAIXO (~rx_en) -- mesma
//     convencao usada no "Tx_en" do transmissor original (~Tx_en). Isso foi
//     mantido para preservar o comportamento original. Se na sua placa
//     rx_en for logicamente "1 = habilitado", inverta o sinal antes de
//     conectar aqui (ou troque "~rx_en" por "rx_en" abaixo).
// =============================================================================

module receiver #(
    parameter int OVERSAMPLE = 16   // Amostras de clk_en por periodo de bit
)(
    input  logic        clk,        // Clock do sistema
    input  logic        rst,        // Reset sincrono, ATIVO EM ALTO
    input  logic        clk_en,     // Pulso de habilitacao vindo do gerador de baud (16x)
    input  logic        rx,         // Entrada serial
    input  logic        rx_en,      // Habilita receptor (ativo em baixo, ver nota acima)
    input  logic        ready_clr,  // Limpa a flag "ready" apos leitura do dado
    output logic        ready,      // Fica em 1 quando um byte valido foi recebido
    output logic [7:0]  data        // Byte recebido
);

    typedef enum logic [1:0] {
        RX_STATE_START = 2'b00,   // Aguardando bit de start
        RX_STATE_DATA  = 2'b01,   // Recebendo os 8 bits de dado
        RX_STATE_STOP  = 2'b10    // Verificando o bit de stop
    } rx_state_e;

    rx_state_e  state;
    logic [3:0] sample;    // Contador de amostras dentro do bit atual (0..15)
    logic [3:0] bit_pos;   // Posicao do bit de dado sendo montado (0..8)
    logic [7:0] scratch;   // Registrador temporario com o byte em montagem

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= RX_STATE_START;
            sample  <= 4'd0;
            bit_pos <= 4'd0;
            scratch <= 8'd0;
            data    <= 8'd0;
            ready   <= 1'b0;
        end else begin
            // ready_clr tem prioridade mas nao impede a FSM de rodar no mesmo ciclo
            if (ready_clr)
                ready <= 1'b0;

            if (clk_en && ~rx_en) begin
                case (state)
                    RX_STATE_START: begin
                        // So comeca a contar depois que Rx cair (deteccao do start bit)
                        if (!rx || sample != 4'd0)
                            sample <= sample + 4'd1;

                        if (sample == 4'd15) begin
                            state   <= RX_STATE_DATA;
                            bit_pos <= 4'd0;
                            sample  <= 4'd0;
                            scratch <= 8'd0;
                        end
                    end

                    RX_STATE_DATA: begin
                        sample <= sample + 4'd1;

                        // Amostra no meio do bit (sample == 8) para maior margem de ruido
                        if (sample == 4'd8) begin
                            scratch[bit_pos[2:0]] <= rx;
                            bit_pos <= bit_pos + 4'd1;
                        end

                        if (bit_pos == 4'd8 && sample == 4'd15)
                            state <= RX_STATE_STOP;
                    end

                    RX_STATE_STOP: begin
                        // Aceita o stop bit no fim da janela (sample==15) ou
                        // antecipa deteccao de erro/novo start se Rx cair cedo
                        if (sample == 4'd15 || (sample >= 4'd8 && !rx)) begin
                            state  <= RX_STATE_START;
                            data   <= scratch;
                            ready  <= 1'b1;
                            sample <= 4'd0;
                        end else begin
                            sample <= sample + 4'd1;
                        end
                    end

                    default: state <= RX_STATE_START;
                endcase
            end
        end
    end

endmodule
