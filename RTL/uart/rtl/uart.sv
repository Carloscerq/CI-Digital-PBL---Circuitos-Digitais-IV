// =============================================================================
// Module : uart
// Descricao:
//   Integra o gerador de baud, o transmissor e o receptor em um unico
//   modulo de topo, pronto para ser usado como entrada de sintese no FPGA.
//
// Notas de conversao / mudancas em relacao ao original:
//   - "wire"/"reg" -> "logic".
//   - A porta "clear" existia no modulo original mas nunca era usada em
//     lugar nenhum (nem conectada aos submodulos). Ela foi substituida por
//     "rst": um reset sincrono ativo em alto que agora É de fato usado
//     por todos os submodulos (baudrate, transmitter, receiver). Se preferir
//     manter o nome/polaridade antigos, e so trocar "rst" por "~clear"
//     na instanciacao abaixo.
//   - CLK_FREQ_HZ, BAUD_RATE e OVERSAMPLE viraram parametros do modulo de
//     topo, repassados ao gerador de baud, para facilitar reuso em outra
//     placa/clock/velocidade sem editar o RTL.
// =============================================================================

module uart #(
    parameter int CLK_FREQ_HZ = 50_000_000,   // Frequencia de clk, em Hz
    parameter int BAUD_RATE   = 115_200,      // Taxa de baud da linha serial
    parameter int OVERSAMPLE  = 16            // Fator de sobreamostragem do Rx
)(
    input  logic         clk,     // Clock do sistema
    input  logic         rst,     // Reset sincrono, ATIVO EM ALTO (mesma polaridade nos 3 submodulos)

    // Transmissor
    input  logic [7:0]   data_in, // Byte a transmitir
    input  logic         tx_en,   // Dispara tx (ativo em baixo, ver transmitter.sv)
    output logic         tx,      // Saida serial
    output logic         tx_busy, // Alto durante uma transmissao

    // Receptor
    input  logic         rx,          // Entrada serial
    input  logic         rx_en,       // Habilita rx (ativo em baixo, ver receiver.sv)
    output logic         ready,       // Alto quando ha um byte novo em data_out
    input  logic         ready_clr,   // Limpa "ready" apos a leitura
    output logic [7:0]   data_out     // Byte recebido
);

    logic tx_clk_en, rx_clk_en;

    baudrate #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .OVERSAMPLE  (OVERSAMPLE)
    ) uart_baud (
        .clk  (clk),
        .rst    (rst),
        .rx_clk_en (rx_clk_en),
        .tx_clk_en (tx_clk_en)
    );

    transmitter uart_tx (
        .clk     (clk),
        .rst     (rst),
        .clk_en  (tx_clk_en),
        .data_in (data_in),
        .tx_en   (tx_en),
        .tx      (tx),
        .tx_busy (tx_busy)
    );

    receiver #(
        .OVERSAMPLE (OVERSAMPLE)
    ) uart_rx (
        .clk       (clk),
        .rst       (rst),
        .clk_en    (rx_clk_en),
        .rx        (rx),
        .rx_en     (rx_en),
        .ready_clr (ready_clr),
        .ready     (ready),
        .data      (data_out)
    );

endmodule
