// ff_primitives.sv - clocked SR and JK flip-flops used by the gate-level state machines, and the three flip-flop
// conversions built from them.
//
// The SR flip-flop treats S = R = 1 as illegal: simulation reports it and makes the state unknown, so a design
// whose excitation logic ever drives both inputs high is caught by the testbenches. The generated state machines
// never do (their S and R covers are disjoint on every reachable state, see scripts/emit_sv.py).

// verilator lint_off DECLFILENAME
module sr_ff (
  input  logic clk,
  input  logic s,
  input  logic r,
  output logic q,
  output logic qn
);
  initial q = 1'b0;
  always_ff @(posedge clk) begin
    unique case ({s, r})
      2'b10:   q <= 1'b1;
      2'b01:   q <= 1'b0;
      2'b00:   q <= q;
      default: begin
        q <= 1'bx;
`ifndef SYNTHESIS
`ifndef FORMAL
        $error("sr_ff: S and R both high");
`endif
`endif
      end
    endcase
  end
  assign qn = ~q;
`ifdef FORMAL
  always_comb assert (!(s && r));
`endif
endmodule

module jk_ff (
  input  logic clk,
  input  logic j,
  input  logic k,
  output logic q,
  output logic qn
);
  initial q = 1'b0;
  always_ff @(posedge clk) begin
    case ({j, k})
      2'b10:   q <= 1'b1;
      2'b01:   q <= 1'b0;
      2'b11:   q <= ~q;
      default: q <= q;
    endcase
  end
  assign qn = ~q;
endmodule

// D flip-flop from an SR flip-flop: S = D, R = D' (one inverter, no other gate)
module d_ff_from_sr (
  input  logic clk,
  input  logic d,
  output logic q,
  output logic qn
);
  sr_ff u_ff (.clk, .s(d), .r(~d), .q, .qn);
endmodule

// "PT" flip-flop from a JK flip-flop. PT = 00 hold, 01 reset, 10 toggle, 11 set.
// J only matters when Q = 0, where Q+ = P; K only matters when Q = 1, where Q+ = 0 iff P != T.
module pt_ff_from_jk (
  input  logic clk,
  input  logic p,
  input  logic t,
  output logic q,
  output logic qn
);
  jk_ff u_ff (.clk, .j(p), .k(p ^ t), .q, .qn);
endmodule

// SR flip-flop from the PT flip-flop: P = S, T = S + R (one OR gate; S = R = 1 is not allowed).
module sr_ff_from_pt (
  input  logic clk,
  input  logic s,
  input  logic r,
  output logic q,
  output logic qn
);
  pt_ff_from_jk u_ff (.clk, .p(s), .t(s | r), .q, .qn);
endmodule
