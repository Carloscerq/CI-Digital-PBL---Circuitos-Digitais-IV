// =============================================================================
// Module : baudrate
// Descricao:
//   Gerador de taxa de baud a partir do clock do sistema (clk_50m). Usa dois
//   acumuladores independentes que contam de 0 ate (DIV-1) e voltam a 0;
//   o pulso de enable fica ativo (combinacional) exatamente no ciclo em que
//   o acumulador esta em 0.
//     - rx_clk_en : pulsa a BAUD_RATE * OVERSAMPLE (usado pelo receptor)
//     - tx_clk_en : pulsa a BAUD_RATE                (usado pelo transmissor)
//
// Nota de conversao:
//   Este arquivo substitui a versao anterior (baseada em contador registrado)
//   por uma conversao FIEL ao "baudrate.v" original fornecido, que usa
//   acumuladores com enable combinacional (assign rx_clk_en = (rx_acc==0)).
//   A unica adicao em relacao ao original e a porta "rst": o codigo
//   original so zerava os acumuladores via inicializacao de "reg ... = 0"
//   (garantida apenas em simulacao). Foi adicionado reset sincrono ATIVO EM
//   ALTO, a MESMA polaridade usada em receiver.sv e transmitter.sv
//   (uart.sv propaga o mesmo "rst" para os tres modulos).
//
//   >>> CORRECAO: a versao anterior deste arquivo usava "if (!rst)", ou seja,
//   polaridade INVERTIDA em relacao ao receiver/transmitter. Com rst=0
//   (operacao normal) os acumuladores ficavam presos em 0, os enables
//   ficavam permanentemente em 1 e o UART operava a 1 bit por ciclo de clk
//   em vez de 1 bit por periodo de baud -- o receptor lia praticamente so
//   linha em repouso e devolvia 0xFF em todos os bytes.
// =============================================================================

module baudrate #(
    parameter int CLK_FREQ_HZ = 50_000_000,   // Frequencia de clk_50m, em Hz
    parameter int BAUD_RATE   = 115_200,      // Taxa de baud desejada
    parameter int OVERSAMPLE  = 16            // Fator de sobreamostragem do Rx
)(
    input  logic clk,
    input  logic rst,          // Reset sincrono, ativo em alto
    output logic rx_clk_en,    // Pulso de 1 ciclo a BAUD_RATE * OVERSAMPLE
    output logic tx_clk_en     // Pulso de 1 ciclo a BAUD_RATE
);

    localparam int RX_ACC_MAX   = CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);
    localparam int TX_ACC_MAX   = CLK_FREQ_HZ / BAUD_RATE;
    localparam int RX_ACC_WIDTH = $clog2(RX_ACC_MAX);
    localparam int TX_ACC_WIDTH = $clog2(TX_ACC_MAX);

    logic [RX_ACC_WIDTH-1:0] rx_acc;
    logic [TX_ACC_WIDTH-1:0] tx_acc;

    // Enable ativo (por 1 ciclo de clk) sempre que o acumulador esta em 0
    assign rx_clk_en = (rx_acc == '0);
    assign tx_clk_en = (tx_acc == '0);

    // Acumulador do Rx (sobreamostrado 16x)
    always_ff @(posedge clk) begin
        if (rst)
            rx_acc <= '0;
        else if (rx_acc == RX_ACC_WIDTH'(RX_ACC_MAX - 1))
            rx_acc <= '0;
        else
            rx_acc <= rx_acc + 1'b1;
    end

    // Acumulador do Tx (na taxa de baud)
    always_ff @(posedge clk) begin
        if (rst)
            tx_acc <= '0;
        else if (tx_acc == TX_ACC_WIDTH'(TX_ACC_MAX - 1))
            tx_acc <= '0;
        else
            tx_acc <= tx_acc + 1'b1;
    end

endmodule