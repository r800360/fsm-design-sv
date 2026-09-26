// tb_booth.sv - self-checking testbench for rtl/booth_skip_mult.sv (Mealy or Moore controller).
//
// Every multiplication is checked for
//   * product == multiplicand x multiplier (2N-bit two's complement) from the cycle done rises, and held afterwards;
//   * done rises after exactly N + k + 2 rising edges after clr (k = non-zero Booth digits of the multiplier), so the
//     add/subtract cycle really is skipped for Booth pairs 00 and 11;
//   * op, the operation of every cycle, follows Booth's table: load, then per multiplier bit an optional add
//     (pair 01) or subtract (pair 10) followed by a shift.
//
// +define+MOORE selects the Moore controller, +define+N=n the operand width (default 13).
// +define+EXHAUSTIVE also multiplies every pair of N-bit operands (2^26 pairs for N = 13, use Verilator).
`timescale 1ns/10ps
`include "tb_common.svh"
`ifndef N
`define N 13
`endif
`ifdef MOORE
`define CTRL_MOORE 1'b1
`else
`define CTRL_MOORE 1'b0
`endif

module tb_booth;
  localparam int N = `N;
  localparam logic signed [N-1:0] MAXV = {1'b0, {(N-1){1'b1}}}, MINV = {1'b1, {(N-1){1'b0}}};

  logic clk = 1'b0, clr = 1'b0;
  logic [N-1:0] multiplicand = '0, multiplier = '0;
  logic [2*N-1:0] product;
  logic done;
  logic [1:0] op;

  booth_skip_mult #(.N(N), .MOORE(`CTRL_MOORE)) dut (.clk, .clr, .multiplicand, .multiplier, .product, .done, .op);

  task automatic tick(); #1 clk = 1'b1; #1 clk = 1'b0; #1; endtask

  // expected operation sequence: ops[0] = load, then per multiplier bit an optional add / subtract and a shift
  int ops [0:3*`N+2];
  int nops;
  task automatic booth_ops(input logic [N-1:0] mlt);
    logic prev;
    nops = 0;
    ops[nops++] = 0;
    prev = 1'b0;
    for (int i = 0; i < N; i++) begin
      if (mlt[i] && !prev) ops[nops++] = 2;
      else if (!mlt[i] && prev) ops[nops++] = 1;
      ops[nops++] = 3;
      prev = mlt[i];
    end
  endtask

  int e_prod, e_done, e_op, e_clr;
  // one multiplication: optional clr, operands applied, `cycles` rising edges with checks after each
  task automatic multiply(input logic [N-1:0] a, input logic [N-1:0] b, input bit with_clr, output bit ok,
                          input int cycles = 3 * `N, input bit scramble = 0);
    logic signed [2*N-1:0] expv;
    int L;
    bit p_ok, d_ok, o_ok;
    ok = 1'b1; p_ok = 1'b1; d_ok = 1'b1; o_ok = 1'b1;
    expv = $signed(a) * $signed(b);
    booth_ops(b);
    L = nops + 1;                                        // = N + k + 2
    if (with_clr) begin
      clr = 1'b1; multiplicand = '0; multiplier = '0; tick();
      clr = 1'b0;
      if (product !== '0 || done !== 1'b0 || op !== 2'b00) begin ok = 1'b0; e_clr++; end
    end
    multiplicand = a; multiplier = b;
    for (int r = 1; r <= cycles; r++) begin
      tick();
      if (scramble) begin multiplicand = N'(tb_rand()); multiplier = N'(tb_rand()); end   // ignored after the load
      if (done !== (r >= L)) d_ok = 1'b0;
      if (op !== ((r < nops) ? 2'(ops[r]) : 2'b00)) o_ok = 1'b0;
      if (r >= L && product !== expv) p_ok = 1'b0;
    end
    if (!p_ok) e_prod++;
    if (!d_ok) e_done++;
    if (!o_ok) e_op++;
    ok = ok & p_ok & d_ok & o_ok;
    if (!ok && e_prod + e_done + e_op + e_clr <= 3)
      $display("   %0d x %0d: product %0d (expected %0d), done timing %s (expected after edge %0d), op sequence %s",
               $signed(a), $signed(b), $signed(product), expv, d_ok ? "ok" : "WRONG", L, o_ok ? "ok" : "WRONG");
  endtask

  task automatic group(input string cat, input string name, input int fails, input int n);
    `CHECK(cat, $sformatf("%s (%0d products)", name, n), fails == 0,
           $sformatf("%0d wrong: product %0d, done timing %0d, op sequence %0d, state after clr %0d", fails,
                     e_prod, e_done, e_op, e_clr))
    e_prod = 0; e_done = 0; e_op = 0; e_clr = 0;
  endtask

  // corner operands: 0, +-1, +-2, max, -max, min, +-2^(N-2), the alternating patterns ...1010 and ...0101 (as a
  // multiplier, ...0101 makes every one of the N Booth digits non-zero: the longest latency, 2N + 2), ...1011, 7
  function automatic logic [N-1:0] corner(input int i);
    logic [N-1:0] alt;
    for (int j = 0; j < N; j++) alt[j] = j[0];                // ...1010
    case (i)
      0: return '0;         1: return N'(1);        2: return '1;          3: return N'(2);
      4: return -N'(2);     5: return MAXV;         6: return -MAXV;       7: return MINV;
      8: return N'(1) << (N - 2);                   9: return -(N'(1) << (N - 2));
      10: return alt;       11: return ~alt;        12: return {alt[N-1:1], 1'b1};
      default: return N'(7);
    endcase
  endfunction
  localparam int NC = 14;

  bit ok;
  int fails, n, nrand, max_lat, min_lat;
  logic [N-1:0] a, b;
  initial begin
    e_prod = 0; e_done = 0; e_op = 0; e_clr = 0;
    $display("booth_skip_mult: N = %0d, %s controller", N, `CTRL_MOORE ? "Moore" : "Mealy");

    multiply(N'(5), N'(3), 1'b0, ok);
    group("FUNC", "power-on, no clr: 5 x 3", !ok, 1);

    fails = 0; n = 0; max_lat = 0; min_lat = 1000;
    for (int i = 0; i < NC; i++) for (int j = 0; j < NC; j++) begin
      multiply(corner(i), corner(j), 1'b1, ok); n++; fails += !ok;
      if (nops + 1 > max_lat) max_lat = nops + 1;
      if (nops + 1 < min_lat) min_lat = nops + 1;
    end
    group("FUNC", $sformatf("corner operands incl. min x min and all-digits-non-zero multipliers, latency %0d..%0d",
                            min_lat, max_lat), fails, n);

    fails = 0; n = 0;
    nrand = 3000;
`ifdef VERILATOR
    nrand = 300000;
`endif
    tb_rng_state = 32'd5140;
    for (int i = 0; i < nrand; i++) begin
      a = N'(tb_rand()); b = N'(tb_rand());
      multiply(a, b, 1'b1, ok); n++; fails += !ok;
    end
    group("FUNC", "random operand pairs", fails, n);

    fails = 0; n = 0;
    for (int i = 0; i < 40; i++) begin
      a = N'(tb_rand()); b = N'(tb_rand());
      multiply(a, b, 1'b1, ok, 3 * N + 10); n++; fails += !ok;
    end
    group("FUNC", "product and done hold for 10+ cycles after completion", fails, n);

    fails = 0; n = 0;
    for (int i = 0; i < 200; i++) begin
      a = N'(tb_rand()); b = N'(tb_rand());
      multiply(a, b, 1'b1, ok, 3 * N, 1'b1); n++; fails += !ok;
    end
    group("ROBUST", "operands changing every cycle after the load are ignored", fails, n);

    fails = 0; n = 0;
    for (int i = 0; i < 200; i++) begin
      int stop;
      a = N'(tb_rand()); b = N'(tb_rand());
      stop = 1 + int'(tb_rand() % (2 * N));
      multiply(a, b, 1'b1, ok, stop);                 // abandoned half-way (checks up to that point still apply)
      fails += !ok;
      a = N'(tb_rand()); b = N'(tb_rand());
      multiply(a, b, 1'b1, ok); n++; fails += !ok;
    end
    group("ROBUST", "clr in the middle of a multiplication restarts cleanly", fails, n);

`ifdef EXHAUSTIVE
    fails = 0;
    for (int ia = 0; ia < (1 << N); ia++) begin
      for (int ib = 0; ib < (1 << N); ib++) begin
        int L, cyc;
        logic signed [2*N-1:0] expv;
        clr = 1'b1; tick(); clr = 1'b0;
        multiplicand = N'(ia); multiplier = N'(ib);
        booth_ops(N'(ib));
        L = nops + 1;
        cyc = 0;
        while (done !== 1'b1 && cyc < 3 * N) begin tick(); cyc++; end
        expv = $signed(N'(ia)) * $signed(N'(ib));
        if (cyc != L || product !== expv) begin
          fails++;
          if (fails <= 3) $display("   %0d x %0d: product %0d after %0d cycles (expected %0d after %0d)",
                                   $signed(N'(ia)), $signed(N'(ib)), $signed(product), cyc, expv, L);
        end
      end
    end
    `CHECK("FUNC", $sformatf("EXHAUSTIVE: all %0d operand pairs (product and exact latency)", 64'(1) << (2 * N)),
           fails == 0, $sformatf("%0d wrong", fails))
`endif
    `REPORT
    $finish;
  end
endmodule
