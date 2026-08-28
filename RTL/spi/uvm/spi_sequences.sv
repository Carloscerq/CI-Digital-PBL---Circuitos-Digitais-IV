// ---------------------------------------------------------------------
//  spi_directed_seq  --  the six single-word exchange() calls from
//                         spi_controller_tb.sv's initial block, alternating
//                         slave 0 (mode 0, CLK_DIV=4) and slave 1 (mode 3,
//                         CLK_DIV=6), including the 0xFF/0x00 all-ones/
//                         all-zeros edge cases.
//
//  spi_random_seq     --  back-to-back random word pairs across both
//                          slaves, no idle gap between exchanges -- the
//                          driver's forever loop naturally starts the next
//                          item's exchange() right after the previous one
//                          settles, same cadence as the tb's own for loop.
//
//  spi_hold_seq        --  reproduces spi_controller_tb.sv's first
//                           transaction() call: a held 3-word transfer to
//                           slave 0 (command byte + two payload bytes),
//                           select down for the first two words and
//                           released on the last, proving hold_select and
//                           the "idle exactly once" invariant.
//
//  Not reproduced from the original tb (left out of scope, see the
//  final report): the remaining two transaction() calls (slave 1's 2-word
//  transfer and slave 0's 4-word transfer) and the trailing plain
//  exchange() after a held transaction. spi_hold_seq already exercises
//  the same hold/next_slave_word mechanism those would, just with fewer
//  repetitions.
// ---------------------------------------------------------------------
class spi_directed_seq #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_sequence #(spi_seq_item #(SIZE, N_SLAVES));

    `uvm_object_param_utils(spi_directed_seq #(SIZE, N_SLAVES))

    function new(string name = "spi_directed_seq");
        super.new(name);
    endfunction

    task body();
        send(0, 8'hA5, 8'h5A);
        send(1, 8'h01, 8'h80);
        send(0, 8'hFF, 8'h00);
        send(1, 8'h00, 8'hFF);
        send(0, 8'h3C, 8'hC3);
        send(1, 8'h12, 8'h34);
    endtask

    task automatic send(int slv, logic [SIZE-1:0] mw, logic [SIZE-1:0] sw);
        spi_seq_item #(SIZE, N_SLAVES) item;
        item = spi_seq_item #(SIZE, N_SLAVES)::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            slave       == slv;
            master_word == mw;
            slave_word  == sw;
            hold        == 1'b0;
        })
            `uvm_error("RAND", "directed item randomize failed")
        item.next_slave_word = '0;
        finish_item(item);
    endtask

endclass


class spi_random_seq #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_sequence #(spi_seq_item #(SIZE, N_SLAVES));

    `uvm_object_param_utils(spi_random_seq #(SIZE, N_SLAVES))

    int unsigned num_txns = 4;

    function new(string name = "spi_random_seq");
        super.new(name);
    endfunction

    task body();
        spi_seq_item #(SIZE, N_SLAVES) item;
        repeat (num_txns) begin
            item = spi_seq_item #(SIZE, N_SLAVES)::type_id::create("item");
            start_item(item);
            if (!item.randomize() with { hold == 1'b0; })
                `uvm_error("RAND", "random item randomize failed")
            item.next_slave_word = '0;
            finish_item(item);
        end
    endtask

endclass


class spi_hold_seq #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_sequence #(spi_seq_item #(SIZE, N_SLAVES));

    `uvm_object_param_utils(spi_hold_seq #(SIZE, N_SLAVES))

    function new(string name = "spi_hold_seq");
        super.new(name);
    endfunction

    task body();
        // transaction(0, '{8'h2A, 8'h00, 8'h1F}, '{8'hAA, 8'hBB, 8'hCC})
        send(0, 8'h2A, 8'hAA, 1'b1, 8'hBB);
        send(0, 8'h00, 8'hBB, 1'b1, 8'hCC);
        send(0, 8'h1F, 8'hCC, 1'b0, 8'h00);
    endtask

    task automatic send(int slv, logic [SIZE-1:0] mw, logic [SIZE-1:0] sw,
                         bit hold_, logic [SIZE-1:0] next_sw);
        spi_seq_item #(SIZE, N_SLAVES) item;
        item = spi_seq_item #(SIZE, N_SLAVES)::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            slave       == slv;
            master_word == mw;
            slave_word  == sw;
            hold        == hold_;
        })
            `uvm_error("RAND", "hold item randomize failed")
        item.next_slave_word = next_sw;
        finish_item(item);
    endtask

endclass
