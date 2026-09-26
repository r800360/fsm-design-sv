// tb_ff.sv - self-checking testbench for the flip-flops and flip-flop conversions of rtl/ff_primitives.sv.
//
// Each flip-flop is driven with 20 000 random input combinations (SR: never S = R = 1) and its state is compared with
// its characteristic equation after every rising edge:
//   SR  Q+ = S + R'Q        JK  Q+ = JQ' + K'Q        D  Q+ = D        PT  00 hold, 01 reset, 10 toggle, 11 set
// Random inputs visit every (state, input) combination many times.
`timescale 1ns/10ps
`include "tb_common.svh"

module tb_ff;
  logic clk = 1'b0;
  logic s, r, j, k, d, p, t;
  logic q_sr, q_jk, q_d, q_pt, q_srpt;
  logic qn_sr, qn_jk, qn_d, qn_pt, qn_srpt;

  sr_ff         u_sr   (.clk, .s,        .r,        .q(q_sr),   .qn(qn_sr));
  jk_ff         u_jk   (.clk, .j,        .k,        .q(q_jk),   .qn(qn_jk));
  d_ff_from_sr  u_d    (.clk, .d,                     .q(q_d),    .qn(qn_d));
  pt_ff_from_jk u_pt   (.clk, .p,        .t,        .q(q_pt),   .qn(qn_pt));
  sr_ff_from_pt u_srpt (.clk, .s,        .r,        .q(q_srpt), .qn(qn_srpt));

  logic e_sr, e_jk, e_d, e_pt;
  int f_sr, f_jk, f_d, f_pt, f_srpt, f_qn;
  int seen_pt [4][2];    // (PT, Q) combinations exercised
  initial begin
    f_sr = 0; f_jk = 0; f_d = 0; f_pt = 0; f_srpt = 0; f_qn = 0;
    e_sr = 1'b0; e_jk = 1'b0; e_d = 1'b0; e_pt = 1'b0;     // power-on state of every flip-flop is 0
    for (int a = 0; a < 4; a++) for (int b = 0; b < 2; b++) seen_pt[a][b] = 0;
    tb_rng_state = 32'd77;
    for (int i = 0; i < 20000; i++) begin
      logic [31:0] v;
      v = tb_rand();
      {s, r} = v[1:0]; if (s && r) r = 1'b0;
      {j, k} = v[3:2]; d = v[4]; {p, t} = v[6:5];
      #1;
      seen_pt[{p, t}][q_pt]++;
      #4 clk = 1'b1; #1;
      e_sr = s | (~r & e_sr);
      e_jk = (j & ~e_jk) | (~k & e_jk);
      e_d  = d;
      case ({p, t}) 2'b00: e_pt = e_pt; 2'b01: e_pt = 1'b0; 2'b10: e_pt = ~e_pt; default: e_pt = 1'b1; endcase
      f_sr   += (q_sr   !== e_sr);
      f_srpt += (q_srpt !== e_sr);          // the SR-from-PT flip-flop sees the same S, R
      f_jk   += (q_jk   !== e_jk);
      f_d    += (q_d    !== e_d);
      f_pt   += (q_pt   !== e_pt);
      f_qn   += (qn_sr !== ~q_sr) + (qn_jk !== ~q_jk) + (qn_d !== ~q_d) + (qn_pt !== ~q_pt) + (qn_srpt !== ~q_srpt);
      #4 clk = 1'b0;
    end
    `CHECK("FUNC", "SR flip-flop: Q+ = S + R'Q", f_sr == 0, $sformatf("%0d wrong cycles", f_sr))
    `CHECK("FUNC", "JK flip-flop: Q+ = JQ' + K'Q", f_jk == 0, $sformatf("%0d wrong cycles", f_jk))
    `CHECK("FUNC", "D from SR (S = D, R = D')", f_d == 0, $sformatf("%0d wrong cycles", f_d))
    `CHECK("FUNC", "PT from JK (J = P, K = P xor T): hold / reset / toggle / set", f_pt == 0,
           $sformatf("%0d wrong cycles", f_pt))
    `CHECK("FUNC", "SR from PT (P = S, T = S + R)", f_srpt == 0, $sformatf("%0d wrong cycles", f_srpt))
    `CHECK("FUNC", "QN is the complement of Q everywhere", f_qn == 0, $sformatf("%0d wrong", f_qn))
    begin
      int miss;
      miss = 0;
      for (int a = 0; a < 4; a++) for (int b = 0; b < 2; b++) miss += (seen_pt[a][b] == 0);
      `CHECK("FUNC", "stimulus covers every (PT, Q) combination", miss == 0, $sformatf("%0d not covered", miss))
    end
    `REPORT
    $finish;
  end
endmodule
