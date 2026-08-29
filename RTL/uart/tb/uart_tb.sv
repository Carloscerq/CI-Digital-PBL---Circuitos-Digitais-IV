// =============================================================================
// Module : tb_uart
// Descricao:
//   Testbench autochecavel (self-checking) para o modulo "uart" (que integra
//   baudrate + transmitter + receiver). A estrategia de verificacao e um
//   LOOPBACK DIGITAL: a saida serial tx e ligada diretamente na entrada rx
//   do mesmo DUT ("assign rx = tx;"). Cada byte enviado pelo transmissor
//   deve, pouco depois, ser recebido de volta pelo receptor -- se
//   data_out == byte enviado, o teste passa.
//
// Tasks de teste automatizado incluidas:
//   apply_reset            - gera o pulso de reset inicial
//   tx_byte                - dispara a transmissao de 1 byte (nao verifica)
//   check_rx_byte          - espera "ready" e compara data_out (com timeout)
//   send_and_verify        - combina tx_byte + check_rx_byte (caso comum)
//   run_basic_tests        - vetores de borda (0x00, 0xFF, 0x55, 0xAA, ...)
//   run_random_tests       - N bytes aleatorios (com seed fixa p/ repetir)
//   run_back_to_back_test  - documenta o comportamento de buffer unico
//                             (sem FIFO) quando dois bytes sao enviados sem
//                             ler o primeiro
//   run_reset_midframe_test- reset no meio de uma transmissao e checa
//                             recuperacao do sistema
//   print_summary          - imprime PASS/FAIL final e encerra a simulacao
// =============================================================================

`timescale 1ns/1ps

module tb_uart;

    // -------------------------------------------------------------------
    // Parametros de simulacao
    // -------------------------------------------------------------------
    localparam int CLK_FREQ_HZ = 50_000_000;
    localparam int BAUD_RATE   = 115_200;
    localparam int OVERSAMPLE  = 16;

    localparam time     CLK_PERIOD        = 20ns;   // 50 MHz
    localparam int      RX_TIMEOUT_CYCLES = 20_000; // ~ 2 frames a 115200 bps
    localparam realtime GLOBAL_TIMEOUT    = 50ms;   // watchdog geral

    // Duracao de 1 bit em ciclos de clk (434 @ 50MHz/115200), usada nos
    // testes que precisam esperar um quadro terminar
    localparam int BIT_PERIOD_CYCLES = CLK_FREQ_HZ / BAUD_RATE;

    // -------------------------------------------------------------------
    // Sinais de conexao com o DUT
    // -------------------------------------------------------------------
    logic       clk;
    logic       rst;

    logic [7:0] data_in;
    logic       tx_en;
    logic       tx;
    logic       tx2;
    logic       tx_busy;

    logic       rx;
    logic       rx_en;
    logic       ready;
    logic       ready_clr;
    logic [7:0] data_out;

    logic [7:0] LEDR;

    // Loopback digital: a saida serial volta direto para a entrada serial
    assign rx = tx;

    // -------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------
    uart #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .OVERSAMPLE  (OVERSAMPLE)
    ) dut (
        .clk   (clk),
        .rst       (rst),
        .data_in   (data_in),
        .tx_en     (tx_en),
        .tx        (tx),
        .tx2       (tx2),
        .tx_busy   (tx_busy),
        .rx        (rx),
        .rx_en     (rx_en),
        .ready     (ready),
        .ready_clr (ready_clr),
        .data_out  (data_out),
        .LEDR      (LEDR)
    );

    // -------------------------------------------------------------------
    // Geracao de clock
    // -------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------
    // Contadores globais de resultado
    // -------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // -------------------------------------------------------------------
    // Waveform (opcional) -- comente estas duas linhas se nao precisar
    // -------------------------------------------------------------------
    initial begin
        $dumpfile("tb_uart.vcd");
        $dumpvars(0, tb_uart);
    end

    // -------------------------------------------------------------------
    // Watchdog global: aborta a simulacao se algo travar (ex.: FSM presa)
    // -------------------------------------------------------------------
    initial begin
        #(GLOBAL_TIMEOUT);
        $fatal(1, "[WATCHDOG] Timeout global da simulacao atingido -- possivel travamento na FSM.");
    end

    // =====================================================================
    // TASKS DE TESTE AUTOMATIZADO
    // =====================================================================

    // Aplica reset sincrono por alguns ciclos de clock
    task automatic apply_reset();
        begin
            rst       = 1'b1;
            data_in   = 8'h00;
            tx_en     = 1'b1;   // ativo em baixo -> 1 = nao dispara tx
            rx_en     = 1'b1;   // ativo em baixo -> 1 = receptor desabilitado
            ready_clr = 1'b0;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
            rx_en = 1'b0;       // habilita o receptor para o resto do teste
            @(posedge clk);
        end
    endtask

    // Dispara a transmissao de um byte (pulso de 1 ciclo em tx_en, ativo em baixo)
    task automatic tx_byte(input logic [7:0] b);
        begin
            wait (tx_busy == 1'b0);
            @(posedge clk);
            data_in <= b;
            tx_en   <= 1'b0;
            @(posedge clk);
            tx_en   <= 1'b1;
        end
    endtask

    // Espera "ready" (com timeout) e compara data_out com o valor esperado
    task automatic check_rx_byte(input logic [7:0] expected,
                                  input int        timeout_cycles = RX_TIMEOUT_CYCLES);
        int cyc;
        begin
            cyc = 0;
            while (!ready && cyc < timeout_cycles) begin
                @(posedge clk);
                cyc++;
            end

            if (!ready) begin
                $error("[FAIL][TIMEOUT] Byte 0x%02h nunca chegou (ready nao foi para 1)", expected);
                fail_count++;
            end else if (data_out === expected) begin
                $display("[PASS] Enviado 0x%02h -> Recebido 0x%02h", expected, data_out);
                pass_count++;
            end else begin
                $error("[FAIL] Enviado 0x%02h -> Recebido 0x%02h (esperado 0x%02h)",
                       expected, data_out, expected);
                fail_count++;
            end

            // Limpa "ready" (pulso de 1 ciclo)
            @(posedge clk);
            ready_clr <= 1'b1;
            @(posedge clk);
            ready_clr <= 1'b0;
        end
    endtask

    // Caso de teste padrao: envia 1 byte e verifica o retorno via loopback
    task automatic send_and_verify(input logic [7:0] b);
        begin
            tx_byte(b);
            check_rx_byte(b);
        end
    endtask

    // Vetores de borda: todos zeros, todos uns, alternados, bit unico, etc.
    task automatic run_basic_tests();
        logic [7:0] vectors[0:9] = '{
            8'h00, 8'hFF, 8'h55, 8'hAA,
            8'h01, 8'h80, 8'h0F, 8'hF0,
            8'h7F, 8'h3C
        };
        begin
            $display("\n--- run_basic_tests: vetores de borda ---");
            foreach (vectors[i])
                send_and_verify(vectors[i]);
        end
    endtask

    // N bytes aleatorios, com seed fixa para reprodutibilidade
    task automatic run_random_tests(input int num_tests, input int seed = 32'hDEAD_BEEF);
        begin
            $display("\n--- run_random_tests: %0d bytes aleatorios (seed=0x%08h) ---",
                      num_tests, seed);
            void'($urandom(seed));
            repeat (num_tests)
                send_and_verify($urandom_range(255, 0));
        end
    endtask

    // Comportamento de buffer unico (o receptor nao tem FIFO):
    // se um segundo byte chegar antes de lermos o primeiro, o registrador
    // "data" e SOBRESCRITO e apenas o ULTIMO byte permanece visivel.
    //
    // NOTA: a versao anterior desta task chamava check_rx_byte(second_byte)
    // logo apos disparar os dois bytes. Isso falhava sempre, mas por um
    // motivo do TESTBENCH e nao do DUT: quando check_rx_byte era chamada,
    // "ready" ja estava alto por causa do PRIMEIRO byte, entao ela comparava
    // data_out (= primeiro byte) contra o segundo. Agora o teste espera o
    // primeiro byte chegar (sem limpar "ready"), envia o segundo, espera o
    // quadro inteiro terminar e so entao verifica a sobrescrita.
    task automatic run_back_to_back_test();
        logic [7:0] first_byte  = 8'hC3;
        logic [7:0] second_byte = 8'h5A;
        int cyc;
        begin
            $display("\n--- run_back_to_back_test: sem FIFO, so o ultimo byte deve sobreviver ---");

            // 1) Primeiro byte chega e fica pendente (NAO limpamos "ready")
            tx_byte(first_byte);
            cyc = 0;
            while (!ready && cyc < RX_TIMEOUT_CYCLES) begin
                @(posedge clk);
                cyc++;
            end
            if (!ready || data_out !== first_byte) begin
                $error("[FAIL] Primeiro byte nao chegou corretamente (ready=%b, data_out=0x%02h, esperado 0x%02h)",
                       ready, data_out, first_byte);
                fail_count++;
            end else begin
                $display("[PASS] Primeiro byte 0x%02h pendente em data_out (ready ainda em 1)", first_byte);
                pass_count++;
            end

            // 2) Segundo byte chega sem que o primeiro tenha sido lido
            tx_byte(second_byte);
            wait (tx_busy == 1'b1);
            wait (tx_busy == 1'b0);
            repeat (3 * BIT_PERIOD_CYCLES) @(posedge clk);  // deixa o quadro terminar no rx

            if (data_out === second_byte && ready === 1'b1) begin
                $display("[PASS] Segundo byte 0x%02h sobrescreveu o primeiro, como esperado (sem FIFO)",
                         second_byte);
                pass_count++;
            end else begin
                $error("[FAIL] Sobrescrita nao ocorreu como esperado (ready=%b, data_out=0x%02h, esperado 0x%02h)",
                       ready, data_out, second_byte);
                fail_count++;
            end

            // Limpa "ready" para os proximos testes
            @(posedge clk);
            ready_clr <= 1'b1;
            @(posedge clk);
            ready_clr <= 1'b0;
        end
    endtask

    // Reset no meio de uma transmissao: verifica que o sistema volta para
    // um estado limpo (tx em repouso, tx_busy baixo) e continua funcional.
    task automatic run_reset_midframe_test();
        begin
            $display("\n--- run_reset_midframe_test: reset durante uma transmissao ---");
            wait (tx_busy == 1'b0);
            @(posedge clk);
            data_in <= 8'hA5;
            tx_en   <= 1'b0;
            @(posedge clk);
            tx_en   <= 1'b1;

            // Espera o start bit aparecer DE FATO na linha (tx cai) e entao
            // avanca ~3 periodos de bit, para resetar no meio real do quadro.
            // (Esperar so por tx_busy nao basta: o transmissor fica em
            //  TX_STATE_START ate o proximo tx_clk_en, sem nada na linha.)
            wait (tx == 1'b0);
            repeat (3 * BIT_PERIOD_CYCLES) @(posedge clk);

            // Pulso de reset -- ATIVO EM ALTO, igual a apply_reset()
            rst <= 1'b1;
            repeat (5) @(posedge clk);
            rst <= 1'b0;
            @(posedge clk);

            if (tx_busy !== 1'b0 || tx !== 1'b1) begin
                $error("[FAIL] Apos reset no meio do frame, tx nao voltou ao repouso (tx=%b, tx_busy=%b)",
                       tx, tx_busy);
                fail_count++;
            end else begin
                $display("[PASS] Reset no meio do frame recuperou o transmissor corretamente");
                pass_count++;
            end

            // rx_en e um sinal de entrada dirigido pelo TB; o reset nao o altera.
            // Reafirmamos aqui apenas por clareza/robustez.
            rx_en <= 1'b0;
            @(posedge clk);

            // Confirma que o sistema segue funcional apos o reset
            send_and_verify(8'h3C);
        end
    endtask

    task automatic print_summary();
        begin
            $display("\n=====================================================");
            $display(" RESUMO DOS TESTES");
            $display("   PASS : %0d", pass_count);
            $display("   FAIL : %0d", fail_count);
            $display("=====================================================");
            if (fail_count > 0)
                $fatal(1, "%0d teste(s) FALHARAM", fail_count);
            else
                $display("TODOS OS TESTES PASSARAM");
            $finish;
        end
    endtask

    // =====================================================================
    // SEQUENCIA PRINCIPAL DE ESTIMULO
    // =====================================================================
    initial begin
        apply_reset();

        run_basic_tests();
        run_random_tests(20);
        run_back_to_back_test();
        run_reset_midframe_test();

        print_summary();
    end

    // -------------------------------------------------------------------
    // Sugestoes de extensao (deixe como comentario / adicione se precisar):
    //   - Instanciar um segundo "baudrate" com um clock levemente distinto
    //     (ex.: 49.9 MHz) para o lado rx, simulando desvio de clock real
    //     entre dois dispositivos e validar a margem de tolerancia do
    //     oversampling de 16x.
    //   - Cobertura funcional (covergroup) sobre os valores de data_out e
    //     sobre as transicoes de estado da FSM (via bind/force ou portas
    //     de debug), para garantir que todos os estados/transicoes foram
    //     exercitados.
    //   - Teste de "framing error" injetando um stop bit invalido (forcar
    //     rx em 0 durante a janela do stop bit) e checando o comportamento
    //     do receptor (o RTL atual nao sinaliza erro de framing -- so
    //     encerra o quadro sem marcar erro; isso pode ser adicionado ao
    //     receiver.sv se for um requisito).
    // -------------------------------------------------------------------

endmodule