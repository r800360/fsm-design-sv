// booth_formal.sv - properties of booth_skip_mult for every operand pair and every clr pattern, from power-on.
//
// The harness counts the rising edges t since the last clr (power-on counts as a clr) and captures the operands at
// the load edge (the first edge after clr). With k = number of non-zero Booth digits of the captured multiplier:
//   P1  done == (t >= N + k + 2)                      exact latency: the skipped add/subtract cycles really are skipped
//   P2  done -> product == multiplicand x multiplier  (2N-bit signed)
//   P3  op == 00 whenever t >= 1 and the multiplier is exhausted (no operation after completion)
// and, from ff_primitives.sv, S and R of every SR flip-flop are never both 1.
module booth_formal #(
  parameter int N = 4,
  parameter bit MOORE = 1'b0
) (
  input logic         clk,
  input logic         clr,
  input logic [N-1:0] multiplicand,
  input logic [N-1:0] multiplier
);
  logic [2*N-1:0] product;
  logic done;
  logic [1:0] op;
  booth_skip_mult #(.N(N), .MOORE(MOORE)) dut (.clk, .clr, .multiplicand, .multiplier, .product, .done, .op);

  localparam int TW = $clog2(2 * N + 4) + 1;
  logic [TW-1:0] t = '0;
  logic [N-1:0]  ma = '0, mb = '0;
  always_ff @(posedge clk) begin
    if (clr) t <= '0;
    else begin
      if (t == '0) begin ma <= multiplicand; mb <= multiplier; end
      if (t != '1) t <= t + 1'b1;
    end
  end

  function automatic int digits(input logic [N-1:0] m);
    digits = (m[0] != 1'b0);
    for (int i = 1; i < N; i++) digits = digits + (m[i] != m[i-1]);
  endfunction

  logic [TW-1:0] lat;
  logic signed [2*N-1:0] expv;
  assign lat  = TW'(N + 2 + digits(mb));
  assign expv = $signed(ma) * $signed(mb);

  always_comb begin
    if (t != '0) begin
      assert (done == (t >= lat));
      if (done) assert (product == expv);
      if (t >= lat - 1'b1) assert (op == 2'b00);
    end
  end
endmodule
