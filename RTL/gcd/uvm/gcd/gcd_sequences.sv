// ---------------------------------------------------------------------
//  gcd_directed_seq  --  the same 9 fixed cases gcd_tb.sv drives against
//                         dut_small (AMOUNT_OF_NUMBERS=5), padded out to
//                         AMOUNT_OF_NUMBERS with trailing zeros. This is
//                         safe and exact: gcd.sv folds the array
//                         left-to-right and euclidian_gcd's documented
//                         convention is gcd(acc, 0) == acc, so trailing
//                         zeros never change the expected result -- only
//                         the 5 real values below drive it.
//
//  gcd_random_seq  --  reproduces gcd_tb.sv's random-trial generation
//                       scheme exactly: every other trial plants a common
//                       factor in [1,64] so the expected gcd isn't almost
//                       always 1 (same `trial % 2 == 0` alternation as
//                       the original), and each element is
//                       factor * a value in [0,1023]. Built procedurally
//                       (rather than via `randomize() with` constraints)
//                       since this non-uniform "factor" distribution
//                       doesn't map cleanly onto constraints;
//                       $urandom_range is the idiomatic UVM equivalent of
//                       the original's `$random`. Operands are kept small
//                       on purpose -- euclidian_gcd is subtraction based,
//                       O(a/b) cycles per pairwise call, chained
//                       AMOUNT_OF_NUMBERS-1 times here -- exactly the
//                       comment in gcd_tb.sv.
// ---------------------------------------------------------------------
class gcd_directed_seq #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_sequence #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE));

    `uvm_object_param_utils(gcd_directed_seq #(AMOUNT_OF_NUMBERS, SIZE))

    function new(string name = "gcd_directed_seq");
        super.new(name);
    endfunction

    // sends one item made of the 5 given values followed by
    // AMOUNT_OF_NUMBERS-5 zero pads
    task send5(input logic [SIZE-1:0] a, b, c, d, e);
        gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE) item;
        item = gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("item");
        foreach (item.in[i]) item.in[i] = '0;
        item.in[0] = a;
        item.in[1] = b;
        item.in[2] = c;
        item.in[3] = d;
        item.in[4] = e;
        start_item(item);
        finish_item(item);
    endtask

    task body();
        send5(12, 18, 24, 36, 60);      // -> 6
        send5(1071, 462, 21, 105, 84);  // -> 21
        send5(9, 6, 3, 12, 15);         // -> 3
        send5(8, 8, 8, 8, 4);           // -> 4
        // every number equal, the gcd is the number itself
        send5(7, 7, 7, 7, 7);           // -> 7
        // coprimes, gcd is 1 (also exercises the early exit)
        send5(13, 17, 19, 23, 29);      // -> 1
        // zeros are neutral, gcd(0, x) = x
        send5(100, 0, 50, 0, 25);       // -> 25
        send5(0, 0, 0, 0, 25);          // -> 25
        // all zeros, nothing to divide
        send5(0, 0, 0, 0, 0);           // -> 0
    endtask

endclass

class gcd_random_seq #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_sequence #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE));

    `uvm_object_param_utils(gcd_random_seq #(AMOUNT_OF_NUMBERS, SIZE))

    int unsigned num_txns = 50;

    function new(string name = "gcd_random_seq");
        super.new(name);
    endfunction

    task body();
        gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE) item;
        logic [SIZE-1:0] factor;

        for (int trial = 0; trial < num_txns; trial++) begin
            item = gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("item");

            // half of the trials get a planted common factor so the
            // expected gcd is not almost always 1
            factor = (trial % 2 == 0) ? (SIZE'($urandom_range(0, 32'h0000_003F)) + 1'b1)
                                       : SIZE'(1);

            for (int i = 0; i < AMOUNT_OF_NUMBERS; i++)
                item.in[i] = factor * SIZE'($urandom_range(0, 32'h0000_03FF));

            start_item(item);
            finish_item(item);
        end
    endtask

endclass
