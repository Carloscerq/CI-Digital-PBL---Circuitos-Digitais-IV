module gcd #(
  parameter AMOUNT_OF_NUMBERS = 33,
  parameter SIZE = 8
) (
  input logic clk,
  input logic reset_n,
  input logic start,
  input logic  [SIZE-1: 0] in [AMOUNT_OF_NUMBERS],
  output logic [SIZE-1: 0] out,
  output logic ready
);

  localparam STATE_IDLE = 2'd0,
             STATE_LOAD = 2'd1,
             STATE_CALC = 2'd2,
             STATE_DONE = 2'd3;

  localparam IDX_SIZE = (AMOUNT_OF_NUMBERS > 1) ? $clog2(AMOUNT_OF_NUMBERS) : 1;
  localparam LAST_IDX = IDX_SIZE'(AMOUNT_OF_NUMBERS - 1);
  localparam FIRST_IDX = IDX_SIZE'((AMOUNT_OF_NUMBERS > 1) ? 1 : 0);

  logic [1: 0] current_state;
  logic [1: 0] next_state;
  logic [IDX_SIZE-1: 0] idx;
  logic [SIZE-1: 0] acc;

  logic sub_start;
  logic sub_ready;
  logic [SIZE-1: 0] sub_out;
  logic last_pair;

  // gcd(acc, in[idx]) is issued for a single cycle while in STATE_LOAD, the
  // euclidian_gcd is idle by then so it latches the operands on that edge
  assign sub_start = (current_state == STATE_LOAD);
  assign last_pair = (idx == LAST_IDX);

  euclidian_gcd #(.SIZE(SIZE)) pair_gcd (
    .clk(clk),
    .reset_n(reset_n),
    .start(sub_start),
    .in_a(acc),
    .in_b(in[idx]),
    .out(sub_out),
    .ready(sub_ready)
  );

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) current_state <= STATE_IDLE;
    else current_state <= next_state;
  end

  always_comb begin
    case (current_state)
      STATE_IDLE: begin
        if (start) next_state = (AMOUNT_OF_NUMBERS > 1) ? STATE_LOAD : STATE_DONE;
        else next_state = STATE_IDLE;
      end
      STATE_LOAD: begin
        next_state = STATE_CALC;
      end
      STATE_CALC: begin
        // once the running gcd hits 1 no other number can lower it
        if (sub_ready) next_state = (last_pair || sub_out == 1) ? STATE_DONE : STATE_LOAD;
        else next_state = STATE_CALC;
      end
      STATE_DONE: begin
        next_state = STATE_IDLE;
      end
      default: next_state = STATE_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      acc <= 0;
      idx <= FIRST_IDX;
      out <= 0;
      ready <= 0;
    end else begin
      ready <= 0;
      out <= 0;

      case (current_state)
        STATE_IDLE: begin
          if (start) begin
            acc <= in[0];
            idx <= FIRST_IDX;
          end
        end
        STATE_LOAD: begin
          // waiting for euclidian_gcd to latch acc and in[idx]
        end
        STATE_CALC: begin
          if (sub_ready) begin
            acc <= sub_out;
            if (!last_pair) idx <= idx + 1;
          end
        end
        STATE_DONE: begin
          out <= acc;
          ready <= 1;
        end
        default: begin
          acc <= 0;
          idx <= FIRST_IDX;
        end
      endcase
    end
  end

endmodule
