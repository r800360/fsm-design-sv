// booth_skip_mult.sv - signed radix-2 Booth multiplier that skips the add/subtract cycle when the Booth pair is 00
// or 11, with either the Mealy or the Moore gate-level controller.
//
// Registers: accumulator A (N+1 bits), multiplier Q (N bits), multiplicand M (N bits), shift counter.
// ex_op from the controller: 00 load (A = 0, Q = multiplier, M = multiplicand, count = 0), 01 A += M, 10 A -= M,
// 11 arithmetic shift right of {A, Q} and count += 1. Once N shifts are done (completed) the datapath is frozen,
// the controller moves to END and raises done, and product holds until the next clr.
//
// Latency: clr, then done is high after N + k + 2 rising edges, where k = number of non-zero Booth digits of the
// multiplier (0 <= k <= N): one load cycle, N shifts, k add/subtract cycles and the move to END.
// For N = 13 that is 15 to 28 cycles; a fixed-sequence controller (load, then N add/subtract-or-nothing cycles
// each followed by a shift) takes 2N + 1 = 27 cycles for every operand pair.
//
// The accumulator has one guard bit, so the product is exact for every pair, including -2^(N-1) x -2^(N-1).
module booth_skip_mult #(
  parameter int N    = 13,
  parameter bit MOORE = 1'b0           // 0: Mealy controller (4 states, 2 SR FFs), 1: Moore (6 states, 3 SR FFs)
) (
  input  logic             clk,
  input  logic             clr,          // synchronous: controller to INIT, A = Q = count = 0
  input  logic [N-1:0]     multiplicand, // sampled in the load cycle (first rising edge after clr)
  input  logic [N-1:0]     multiplier,
  output logic [2*N-1:0]   product,      // two's complement
  output logic             done,
  output logic [1:0]       op            // operation the datapath performs at the next edge (00 once completed)
);
  localparam int CW = $clog2(N + 1);

  logic [N:0]    a, a_d;
  logic [N-1:0]  q, q_d, m, m_d;
  logic [CW-1:0] count, count_d;
  logic [1:0]    ex_op;
  logic          completed;

  assign completed = (count == CW'(N));

  always_comb begin
    a_d = a; q_d = q; m_d = m; count_d = count;
    case (ex_op)
      2'b00: begin a_d = '0; q_d = multiplier; m_d = multiplicand; count_d = '0; end
      2'b01: a_d = a + {m[N-1], m};
      2'b10: a_d = a - {m[N-1], m};
      2'b11: begin {a_d, q_d} = {a[N], a, q[N-1:1]}; count_d = count + 1'b1; end
    endcase
  end

  initial begin a = '0; q = '0; m = '0; count = '0; end
  always_ff @(posedge clk) begin
    if (clr) begin
      a <= '0; q <= '0; count <= '0;
    end else if (!completed) begin
      a <= a_d; q <= q_d; m <= m_d; count <= count_d;
    end
  end

  if (MOORE) begin : g_moore
    // the Moore controller picks S00 / S10 on the load edge, when Q does not yet hold the multiplier:
    // it looks at bit 0 of the value being loaded (q_d[0]) and afterwards at q[1], the next bit to enter the window
    logic init_unused;
    booth_ctrl_moore u_ctrl (.clk, .rst(clr), .shift_in(q[1]), .current_shift(q_d[0]), .completed,
                             .ex_op, .done, .init(init_unused));
  end else begin : g_mealy
    booth_ctrl_mealy u_ctrl (.clk, .rst(clr), .shift_in(q[0]), .completed, .ex_op, .done);
  end

  assign product = {a[N-1:0], q};
  assign op      = completed ? 2'b00 : ex_op;
endmodule
