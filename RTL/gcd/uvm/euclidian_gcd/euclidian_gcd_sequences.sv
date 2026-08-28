// ---------------------------------------------------------------------
//  euclidian_gcd_directed_seq  --  the 4 vectors from euclidian_gcd_tb.sv
//                                   ((10,5), (1071,462), (462,1071),
//                                   (5,10)), plus the edge cases the
//                                   DUT's documented convention cares
//                                   about:
//                                     (0,0)   -> 0   (both zero)
//                                     (0,25)  -> 25  (a is neutral)
//                                     (25,0)  -> 25  (b is neutral)
//                                     (7,7)   -> 7   (equal, nonzero
//                                                     operands; b hits 0
//                                                     on the very first
//                                                     CALC cycle)
//                                     (13,17) -> 1   (coprime; exercises
//                                                     the "other side"
//                                                     early exit, where
//                                                     a hits 0 while b
//                                                     still has bits)
//
//  euclidian_gcd_random_seq  --  constrained-random (in_a, in_b) pairs.
//
//  euclidian_gcd subtracts instead of dividing, so a pair (a, b) takes
//  O(max(a,b)/min(a,b)) cycles to settle: an unconstrained pair at, say,
//  SIZE=32 could in the worst case take billions of cycles. gcd_tb.sv
//  (one directory up, RTL/gcd/gcd_tb.sv) makes exactly this point and
//  deliberately keeps its random operands small, masking them down to an
//  11-bit magnitude (`$random & 32'h0000_03FF` is actually a 10-bit mask,
//  factored up by a small `factor`). This sequence follows the same
//  reasoning directly: both operands are bounded to MAX_OPERAND (4095,
//  i.e. 12 bits), so the very worst case for one trial -- one operand at
//  the bound, the other at 1 -- is only ~4095 CALC cycles, keeping every
//  trial's simulation time small regardless of how wide SIZE actually is.
//  `num_trials` is public so a test can crank the sweep up, mirroring
//  mac_random_seq's num_trials / gcd_tb.sv's RANDOM_TRIALS.
// ---------------------------------------------------------------------
class euclidian_gcd_directed_seq #(
    int SIZE = 32
) extends uvm_sequence #(euclidian_gcd_seq_item #(SIZE));

    `uvm_object_param_utils(euclidian_gcd_directed_seq #(SIZE))

    function new(string name = "euclidian_gcd_directed_seq");
        super.new(name);
    endfunction

    task body();
        send(10, 5);
        send(1071, 462);
        send(462, 1071);
        send(5, 10);

        // zeros are neutral, matching the DUT's documented convention:
        // gcd(0,0)=0, gcd(0,b)=b, gcd(a,0)=a
        send(0, 0);
        send(0, 25);
        send(25, 0);

        // equal nonzero operands
        send(7, 7);

        // coprime operands (also exercises the early exit)
        send(13, 17);
    endtask

    task send(input logic [SIZE-1:0] a, input logic [SIZE-1:0] b);
        euclidian_gcd_seq_item #(SIZE) item;
        item = euclidian_gcd_seq_item #(SIZE)::type_id::create("item");
        start_item(item);
        item.in_a = a;
        item.in_b = b;
        finish_item(item);
    endtask

endclass

class euclidian_gcd_random_seq #(
    int SIZE = 32
) extends uvm_sequence #(euclidian_gcd_seq_item #(SIZE));

    `uvm_object_param_utils(euclidian_gcd_random_seq #(SIZE))

    // a few thousand at most, see the file header comment above
    localparam logic [SIZE-1:0] MAX_OPERAND = SIZE'(4095);

    int unsigned num_trials = 80;

    function new(string name = "euclidian_gcd_random_seq");
        super.new(name);
    endfunction

    task body();
        euclidian_gcd_seq_item #(SIZE) item;

        repeat (num_trials) begin
            item = euclidian_gcd_seq_item #(SIZE)::type_id::create("item");
            start_item(item);
            if (!item.randomize() with {
                    in_a inside {[0 : MAX_OPERAND]};
                    in_b inside {[0 : MAX_OPERAND]};
                })
                `uvm_error("RAND", "random item randomize failed")
            finish_item(item);
        end
    endtask

endclass
