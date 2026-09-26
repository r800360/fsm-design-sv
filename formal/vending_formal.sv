// vending_formal.sv - safety of vending_machine for every input sequence after the first reset: any bill in any
// cycle (closed slots included), refund requests and resets at any time.
//   P1  a payout never takes a bill the till does not hold
//   P2  no bill counter wraps around
//   P3  never more items dispensed than are in stock, and the stock never wraps
// Parameters as in vending_machine.sv, so the same harness proves the configurations and shows that a smaller till
// or narrower counters fail.
//
// LEMMAS = 1 adds invariants that hold in every reachable state and make P1-P3 inductive (PDR then proves them
// quickly; without them it does not converge within 30 minutes):
//   L1  value conservation: till value - initial value = 4 x items sold + balance + change still due
//   L2  the customer's deposit is in the till: balance 1 -> a 1-bill, 2 -> two, 3 -> three 1-bills or a 3-bill
//   L3  the change due can be paid with the serializer's policy: 1 or 2 -> that many 1-bills, 3 -> a 3-bill or three
//   L4  (fixed till, no locks) the worst customer takes two 1-bills per item, so the till always holds at least
//       2 x stock + need(balance, change due) 1-bills; need = 1 / 2 for a balance of 1 / 2, 3 for a balance of 3
//       when no 3-bill is left (a refund pays three 1-bills), plus the change due unless it is paid with a 3-bill
//   L5  the 5-bill counter never goes below its initial value
// The negative controls run with LEMMAS = 0, so they fail on a real payout, overflow or over-dispense.
module vending_formal #(
  parameter bit         LEMMAS  = 1'b1,
  parameter bit         TILL    = 1'b1,
  parameter bit         LOCKS   = 1'b0,
  parameter int         W1      = 8,
  parameter int         W3      = 8,
  parameter int         W5      = 8,
  parameter logic [7:0] N1_INIT = 8'd31,
  parameter logic [7:0] N3_INIT = 8'd31,
  parameter logic [7:0] N5_INIT = 8'd31
) (
  input logic       clk,
  input logic       rst,
  input logic [1:0] bill
);
  logic [1:0] dispense, change_amt, bill_out, balance;
  logic empty, busy, lock3, lock5;
  logic [W1-1:0] till1;
  logic [W3-1:0] till3;
  logic [W5-1:0] till5;
  logic [3:0] stock;
  logic [1:0] change_due;
  vending_machine #(.TILL(TILL), .LOCKS(LOCKS), .BARS(15), .W1(W1), .W3(W3), .W5(W5), .N1_INIT(N1_INIT),
                    .N3_INIT(N3_INIT), .N5_INIT(N5_INIT)) dut (
    .clk, .rst, .bill, .dispense, .change_amt, .bill_out, .empty, .busy, .lock3, .lock5, .balance, .till1, .till3,
    .till5, .stock, .change_due);

  // the machine is specified from its reset: the first cycle is a reset cycle
  logic started = 1'b0;
  logic [W1-1:0] p1;
  logic [W3-1:0] p3;
  logic [W5-1:0] p5;
  logic [3:0] ps;
  logic prst;
  always_ff @(posedge clk) begin
    started <= 1'b1;
    p1 <= till1; p3 <= till3; p5 <= till5; ps <= stock; prst <= rst;
  end
  always_comb if (!started) assume (rst);

  always_comb begin
    if (started && !rst) begin
      if (bill_out == 2'b01) assert (till1 != '0);
      if (bill_out == 2'b10) assert (till3 != '0);
      assert (bill_out != 2'b11);
      assert ({2'b00, dispense} <= stock);
    end
    if (started && !prst) begin
      assert (!(p1 == '1 && till1 == '0));
      assert (!(p3 == '1 && till3 == '0));
      assert (!(p5 == '1 && till5 == '0));
      assert (!(ps == '0 && stock == 4'hf));
    end
  end

  // ---------------------------------------------------------------- inductive strengthening
  localparam int VINIT = int'(N1_INIT) + 3 * int'(N3_INIT) + 5 * int'(N5_INIT);
  logic [11:0] value_now, value_exp;
  logic [8:0]  need;
  logic [1:0]  bneed, oneed;
  always_comb begin
    value_now = 12'(till1) + 12'(till3) * 12'd3 + 12'(till5) * 12'd5;
    value_exp = 12'(VINIT) + 12'd4 * (12'd15 - 12'(stock)) + 12'(balance) + 12'(change_due);
    bneed = (balance == 2'd3) ? ((till3 == '0) ? 2'd3 : 2'd0) : balance;
    oneed = (change_due == 2'd3 && till3 != '0) ? 2'd0 : change_due;
    need  = 9'(stock) * 9'd2 + 9'(bneed) + 9'(oneed);
    if (LEMMAS && started) begin
      assert (value_now == value_exp);
      if (balance == 2'd1) assert (till1 >= W1'(1));
      if (balance == 2'd2) assert (till1 >= W1'(2));
      if (balance == 2'd3) assert (till1 >= W1'(3) || till3 != '0);
      if (change_due == 2'd1) assert (till1 >= W1'(1));
      if (change_due == 2'd2) assert (till1 >= W1'(2));
      if (change_due == 2'd3) assert (till1 >= W1'(3) || till3 != '0);
      assert (12'(till5) >= 12'(N5_INIT));
      if (!LOCKS) assert (9'(till1) >= need);
    end
  end
endmodule
