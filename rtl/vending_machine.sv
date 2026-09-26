// vending_machine.sv - vending machine built around the gate-level balance FSM (vending_fsm.sv).
//
// Price 4; bills of 1, 3 and 5 (bill code 01 / 10 / 11, 00 = "refund my balance"); BARS items in stock.
// A purchase that brings the balance to 4..7 dispenses one item and returns the excess as change; 3 + 5 = 8
// dispenses two items.
//
//   TILL = 0   change is reported as an amount (change_amt) in the same cycle.
//   TILL = 1   the machine counts the bills in its till (N1_INIT / N3_INIT / N5_INIT at reset) and pays change
//              and refunds from it, one bill per clock (change_serializer.sv): a 3-bill when 3 is owed and the till
//              has one, 1-bills otherwise. While a payout is in progress (busy) the bill slots are closed.
//   LOCKS = 1  (with TILL = 1) the till may start empty: a slot is closed whenever accepting that bill could leave
//              the machine owing change it cannot pay. scripts/vending_bounds.py proves, over every reachable
//              state, that these locks are sufficient and that each one is necessary.
//
// In every configuration the 5-slot is closed at balance 3 when only one item is left (3 + 5 would need two),
// and every slot is closed while the machine is empty. A bill offered at a closed slot is ignored: the FSM is
// frozen through its enable input, and its outputs are suppressed. One clock, no gated clocks.
module vending_machine #(
  parameter bit          TILL    = 1'b1,
  parameter bit          LOCKS   = 1'b0,
  parameter int          BARS    = 15,
  parameter int          W1      = 8,    // bill counter widths
  parameter int          W3      = 8,
  parameter int          W5      = 8,
  parameter logic [7:0]  N1_INIT = 8'd31,
  parameter logic [7:0]  N3_INIT = 8'd31,
  parameter logic [7:0]  N5_INIT = 8'd31
) (
  input  logic       clk,
  input  logic       rst,         // synchronous: balance 0, BARS items, till refilled, no payout pending
  input  logic [1:0] bill,        // 00 none / refund request, 01 = 1, 10 = 3, 11 = 5
  output logic [1:0] dispense,    // items dispensed this cycle (0, 1 or 2)
  output logic [1:0] change_amt,  // change or refund produced this cycle (0..3)
  output logic [1:0] bill_out,    // TILL = 1: bill paid out this cycle, 00 none, 01 a 1-bill, 10 a 3-bill
  output logic       empty,       // no items left: all slots closed
  output logic       busy,        // payout in progress: all slots closed
  output logic       lock3,       // 3-slot closed
  output logic       lock5,       // 5-slot closed
  output logic [1:0] balance,
  output logic [W1-1:0] till1,    // bills in the till (operator display); 0 when TILL = 0
  output logic [W3-1:0] till3,
  output logic [W5-1:0] till5,
  output logic [$clog2(BARS+1)-1:0] stock,  // items left
  output logic [1:0] change_due   // TILL = 1: change still to be paid out (0 when TILL = 0)
);
  localparam int BW = $clog2(BARS + 1);

  // ---------------------------------------------------------------- stock and till
  logic [BW-1:0] bars;
  logic [W1-1:0] n1;
  logic [W3-1:0] n3;
  logic [W5-1:0] n5;
  assign till1 = n1;
  assign till3 = n3;
  assign till5 = n5;
  assign stock = bars;

  // ---------------------------------------------------------------- slot control
  logic en, last;
  assign last  = (bars == BW'(1));
  assign empty = (bars == '0);
  always_comb begin
    lock3 = 1'b0;
    lock5 = (balance == 2'd3) && last;
    if (TILL && LOCKS) begin
      case (balance)
        2'd0: lock5 = (n1 < W1'(1));                     // change 1 needs a 1-bill
        2'd1: lock5 = (n1 < W1'(2));                     // change 2 needs two 1-bills
        2'd2: lock5 = (n1 < W1'(3)) && (n3 == '0);       // change 3: a 3-bill or three 1-bills
        2'd3: lock5 = last;                              // 3 + 5 = two items, no change
      endcase
      lock3 = (balance == 2'd3) && (n1 < W1'(2));        // 3 + 3: change 2 needs two 1-bills
    end
  end
  assign en = !(empty || busy || (bill == 2'b11 && lock5) || (bill == 2'b10 && lock3));

  // ---------------------------------------------------------------- balance FSM (gate level)
  logic [1:0] item;
  vending_fsm u_fsm (.clk, .rst, .en, .bill, .item, .change(change_amt), .balance);
  assign dispense = item[1] ? 2'd2 : {1'b0, item[0]};   // item code: 00 none, 01 one, 1x two

  always_ff @(posedge clk)
    if (rst) bars <= BW'(BARS);
    else     bars <= bars - BW'(dispense);

  // ---------------------------------------------------------------- till and payout
  if (TILL) begin : g_till
    logic have3, accept;
    assign have3  = (n3 != '0);
    assign accept = en && (bill != 2'b00);
    change_serializer u_pay (.clk, .rst, .load(change_amt != 2'b00), .amount(change_amt), .have3, .bill_out, .busy,
                             .owed(change_due));

    // bills in the till, the customer's own deposit included; payouts only happen while busy (slots closed),
    // so a counter never counts up and down in the same cycle
    always_ff @(posedge clk) begin
      if (rst) begin
        n1 <= W1'(N1_INIT);
        n3 <= W3'(N3_INIT);
        n5 <= W5'(N5_INIT);
      end else begin
        n1 <= n1 + W1'(accept && bill == 2'b01) - W1'(bill_out == 2'b01);
        n3 <= n3 + W3'(accept && bill == 2'b10) - W3'(bill_out == 2'b10);
        n5 <= n5 + W5'(accept && bill == 2'b11);
      end
    end
  end else begin : g_no_till
    assign bill_out   = 2'b00;
    assign busy       = 1'b0;
    assign change_due = 2'b00;
    assign n1 = '0;
    assign n3 = '0;
    assign n5 = '0;
  end
endmodule
