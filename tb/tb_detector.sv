// tb_detector.sv - self-checking testbench for the composite sequence detector, SR and JK versions side by side.
//
// Specification (the reference model below, independent of the state tables):
//   z1 = 1 when the last three bits, the current one included, are 1 0 1          (overlapping)
//   z2 = 1 when the last three bits are 0 1 1, but only in "both" mode             (overlapping)
//   the machine starts in "both" mode; z2 firing switches to "z1 only" mode, and z1 firing in that mode switches
//   back. Bits before a reset do not count.
// Outputs are Mealy: they are checked after x settles, before the rising edge.
//
//   FUNC    power-on without reset; every sequence of length 1..12 after reset (8190 sequences); a long random
//           stream (100 000 bits, 1 000 000 with Verilator)
//   ROBUST  reset asserted at random points, i.e. from every state
`timescale 1ns/10ps
`include "tb_common.svh"

module tb_detector;
  logic clk = 1'b0, rst = 1'b0, x = 1'b0;
  logic z1_sr, z2_sr, z1_jk, z2_jk;

  seq_detector_sr dut_sr (.clk, .rst, .x, .z1(z1_sr), .z2(z2_sr));
  seq_detector_jk dut_jk (.clk, .rst, .x, .z1(z1_jk), .z2(z2_jk));

  // ---------------------------------------------------------------- reference model
  logic [1:0] hist;     // the two previous bits
  int nbits;            // bits since reset (saturating at 2)
  bit both;
  bit ez1, ez2;
  task automatic m_reset(); hist = 2'b00; nbits = 0; both = 1'b1; endtask
  task automatic m_out(input bit b);
    ez1 = (nbits >= 2) && ({hist, b} == 3'b101);
    ez2 = (nbits >= 2) && both && ({hist, b} == 3'b011);
  endtask
  task automatic m_step(input bit b);
    if (ez2) both = 1'b0;
    else if (ez1 && !both) both = 1'b1;
    hist = {hist[0], b};
    if (nbits < 2) nbits++;
  endtask

  // ---------------------------------------------------------------- one cycle
  int errs, cyc, s_fires1, s_fires2;
  string first_err, ctx;
  task automatic step(input bit b);
    x = b;
    m_out(b);
    #1;
    if ({z1_sr, z2_sr} !== {ez1, ez2} || {z1_jk, z2_jk} !== {ez1, ez2}) begin
      errs++;
      if (errs == 1)
        first_err = $sformatf("%s, bit %0d: SR z1 z2 = %b %b, JK z1 z2 = %b %b, expected %b %b",
                              ctx, cyc, z1_sr, z2_sr, z1_jk, z2_jk, ez1, ez2);
    end
    s_fires1 += ez1; s_fires2 += ez2;
    #4 clk = 1'b1; #5 clk = 1'b0;
    m_step(b);
    cyc++;
  endtask
  task automatic do_reset();
    rst = 1'b1; x = 1'b0; #5 clk = 1'b1; #5 clk = 1'b0; rst = 1'b0;
    m_reset(); cyc = 0;
  endtask
  task automatic group(input string cat, input string name);
    `CHECK(cat, name, errs == 0, first_err)
    errs = 0; first_err = "";
  endtask

  int nrand;
  initial begin
    errs = 0; cyc = 0; s_fires1 = 0; s_fires2 = 0;
    m_reset();
    ctx = "power-on";
    for (int i = 0; i < 12; i++) step((12'b1011_0110_1101 >> i) & 1);
    group("FUNC", "power-on without reset starts in the reset state");

    for (int len = 1; len <= 12; len++)
      for (int v = 0; v < (1 << len); v++) begin
        do_reset();
        ctx = $sformatf("sequence %0d'b%b", len, v[11:0]);
        for (int i = len - 1; i >= 0; i--) step((v >> i) & 1);
      end
    group("FUNC", $sformatf("every sequence of length 1..12 after reset (%0d z1 and %0d z2 detections)",
                            s_fires1, s_fires2));

    nrand = 100000;
`ifdef VERILATOR
    nrand = 1000000;
`endif
    do_reset();
    ctx = "random stream";
    tb_rng_state = 32'd1011;
    s_fires1 = 0; s_fires2 = 0;
    for (int i = 0; i < nrand; i++) step(tb_rand() & 1);
    group("FUNC", $sformatf("%0d-bit random stream (%0d z1, %0d z2)", nrand, s_fires1, s_fires2));

    ctx = "random stream with resets";
    for (int i = 0; i < 20000; i++) begin
      if (tb_rand() % 16 == 0) do_reset();
      step(tb_rand() & 1);
    end
    group("ROBUST", "reset asserted at random points (from every state)");
    `REPORT
    $finish;
  end
endmodule
