module uart_test_top (
    input  wire CLOCK_50,
    output wire UART_TX
);

    // ----------------------------------------------------
    // Dados enviados
    // ----------------------------------------------------

    reg [7:0] tx_data = 8'h00;

    reg tx_start = 1'b0;

    wire tx_busy;


    // ----------------------------------------------------
    // Contador para controlar intervalo entre transmissões
    //
    // 50 MHz:
    // 5.000.000 clocks = aproximadamente 100 ms
    //
    // Portanto envia aproximadamente 10 bytes por segundo.
    // ----------------------------------------------------

    reg [22:0] delay_counter = 0;

    localparam integer DELAY_COUNT = 5_000_000;


    // ----------------------------------------------------
    // Transmissor UART
    // ----------------------------------------------------

    uart_tx #(
        .CLOCK_FREQ(50_000_000),
        .BAUD_RATE(115_200)
    )
    uart_tx_inst (
        .clk   (CLOCK_50),
        .start (tx_start),
        .data  (tx_data),
        .tx    (UART_TX),
        .busy  (tx_busy)
    );


    // ----------------------------------------------------
    // Gerador dos bytes:
    //
    // 00
    // 01
    // 02
    // 03
    // ...
    // FF
    // 00
    // ...
    // ----------------------------------------------------

    always @(posedge CLOCK_50) begin

        // start normalmente fica em zero.
        // Ele é colocado em 1 durante apenas um clock.
        tx_start <= 1'b0;

        if (!tx_busy) begin

            if (delay_counter == DELAY_COUNT - 1) begin

                delay_counter <= 0;

                // solicita envio do byte atual
                tx_start <= 1'b1;

                // próximo byte
                tx_data <= tx_data + 1'b1;

            end
            else begin

                delay_counter <= delay_counter + 1'b1;

            end

        end
        else begin

            delay_counter <= 0;

        end

    end

endmodule