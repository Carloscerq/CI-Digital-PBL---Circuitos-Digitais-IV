module euclidian_gcd (
  parameter SIZE = 8
) (
  input logic clk,
  input logic reset_n,
  input logic start,
  input logic [SIZE-1: 0] in_a,
  input logic [SIZE-1: 0] in_b,
  output logic [SIZE-1: 0] out,
  output logic ready
);

  localparam STATE_IDLE = 2'd0,
             STATE_CALC = 2'd1,
             STATE_DONE = 2'd2;

  logic [1: 0] current_state;
  logic [1: 0] next_state;
  logic [SIZE-1: 0] a_reg;
  logic [SIZE-1: 0] b_reg;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) current_state <= STATE_IDLE;
    else current_state <= next_state;
  end

  always_comb begin
    case (current_state)
      STATE_IDLE: begin
        if (start) next_state = STATE_CALC;
        else next_state = STATE_IDLE;
      end
      STATE_CALC: begin
        if (a_reg == 0 || b_reg == 0) next_state = STATE_DONE;
        else next_state = STATE_CALC;
      end
      STATE_DONE: begin
        next_state = STATE_IDLE;
      end
      default: next_state = STATE_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!reset_n) begin
      a_reg <= 0;
      b_reg <= 0;
      out <= 0;
      done <= 0;
    end else begin
      done <= 0;
      out <= 0;
      a_reg <= 0;
      b_reg <= 0;

      case (current_state)
        STATE_IDLE: begin
          if (start) begin
            a_reg <= in_a;
            b_reg <= in_b;
          end
        end
        STATE_CALC: begin
          if (a_reg > b_reg) begin
            a_reg <= a_reg - b_reg;
          end else if (b_reg > a_reg) begin
            b_reg <= b_reg - a_reg;
          end else begin
            b_reg <= 0;
          end
        end
        STATE_DONE: begin
          out <= (a_reg != 0) ? a_reg : b_reg;
          ready <= 1;
        end
      endcase
    end
  end

endmodule