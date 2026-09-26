// detector_formal.sv - the SR and JK gate-level detectors are equivalent to the specification model, for every
// input sequence and every reset pattern, from power-on (all flip-flops 0).
//
// The specification is the same as in tb/tb_detector.sv: z1 = last three bits 101; z2 = last three bits 011 in
// "both" mode; z2 switches to "z1 only" mode and z1 switches back. It is written as a small shift register, not as
// the state table the detectors were synthesised from. The SR flip-flops also assert that S and R are never both 1
// (ff_primitives.sv, under FORMAL).
module detector_formal (
  input logic clk,
  input logic rst,
  input logic x
);
  logic z1_sr, z2_sr, z1_jk, z2_jk;
  seq_detector_sr u_sr (.clk, .rst, .x, .z1(z1_sr), .z2(z2_sr));
  seq_detector_jk u_jk (.clk, .rst, .x, .z1(z1_jk), .z2(z2_jk));

  // specification
  logic [1:0] hist = 2'b00;     // previous two bits
  logic [1:0] nbits = 2'd0;     // bits since reset, saturating at 2
  logic       zmode = 1'b0;     // 1 = "z1 only" mode
  logic       ez1, ez2;
  assign ez1 = (nbits == 2'd2) && ({hist, x} == 3'b101);
  assign ez2 = (nbits == 2'd2) && !zmode && ({hist, x} == 3'b011);
  always_ff @(posedge clk) begin
    if (rst) begin
      hist <= 2'b00; nbits <= 2'd0; zmode <= 1'b0;
    end else begin
      hist <= {hist[0], x};
      if (nbits != 2'd2) nbits <= nbits + 1'b1;
      if (ez2)             zmode <= 1'b1;
      else if (ez1 && zmode) zmode <= 1'b0;
    end
  end

  always_comb begin
    assert (z1_sr == ez1);
    assert (z2_sr == ez2);
    assert (z1_jk == ez1);
    assert (z2_jk == ez2);
  end
endmodule
