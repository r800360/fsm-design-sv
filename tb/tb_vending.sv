// tb_vending.sv - self-checking testbench for rtl/vending_machine.sv.
//
// A cycle-accurate reference model written from the specification (balance arithmetic, not the K-maps) predicts
// every output of every cycle, including the till counts, the stock and the change still due. The outputs are Mealy, so they are compared
// after the inputs settle and before the rising edge. The model also checks the machine-level invariants:
//   * a payout never takes a bill the till does not hold, and no bill counter overflows;
//   * no more items are dispensed than are in stock.
//
// +define+CFG=n selects the configuration:
//   2  items counted, change reported as an amount                          (TILL = 0)
//   3  till with 31 bills of each kind, change paid from it                (TILL = 1)
//   4  till starts empty, slots locked when change could not be paid       (TILL = 1, LOCKS = 1)
//   5  smallest safe till: 30 1-bills, 7/5/4-bit counters                  (TILL = 1)
//
// Categories: FUNC directed scenarios, RANDOM customers that follow the protocol, ROBUST bills offered at closed
// slots, random bills in any cycle and resets in the middle of a transaction.
`timescale 1ns/10ps
`include "tb_common.svh"
`ifndef CFG
`define CFG 3
`endif

module tb_vending;
  localparam int CFG   = `CFG;
  localparam bit TILL  = CFG >= 3;
  localparam bit LOCKS = CFG == 4;
  localparam int BARS  = 15;
  localparam int W1 = CFG == 5 ? 7 : 8, W3 = CFG == 5 ? 5 : 8, W5 = CFG == 5 ? 4 : 8;
  localparam int I1 = CFG == 3 ? 31 : CFG == 5 ? 30 : 0;
  localparam int I3 = CFG == 3 ? 31 : 0;
  localparam int I5 = CFG == 3 ? 31 : 0;

  logic clk = 1'b0, rst = 1'b0;
  logic [1:0] bill = 2'b00;
  logic [1:0] dispense, change_amt, bill_out, balance;
  logic empty, busy, lock3, lock5;
  logic [W1-1:0] till1;
  logic [W3-1:0] till3;
  logic [W5-1:0] till5;
  logic [3:0] stock;
  logic [1:0] change_due;

  vending_machine #(.TILL(TILL), .LOCKS(LOCKS), .BARS(BARS), .W1(W1), .W3(W3), .W5(W5),
                    .N1_INIT(8'(I1)), .N3_INIT(8'(I3)), .N5_INIT(8'(I5))) dut (
    .clk, .rst, .bill, .dispense, .change_amt, .bill_out, .empty, .busy, .lock3, .lock5, .balance,
    .till1, .till3, .till5, .stock, .change_due);

  // ---------------------------------------------------------------- reference model
  int m_bal, m_bars, m_owed, m_n1, m_n3, m_n5;
  int x_disp, x_chg, x_bo, x_empty, x_busy, x_l3, x_l5, x_en, x_nxt;   // expected outputs of this cycle
  int inv_errs;
  string inv_first;

  task automatic m_reset();
    m_bal = 0; m_bars = BARS; m_owed = 0; m_n1 = I1; m_n3 = I3; m_n5 = I5;
  endtask

  // value of a bill code; 0 for a refund request
  function automatic int value(input int b);
    case (b) 1: return 1; 2: return 3; 3: return 5; default: return 0; endcase
  endfunction

  task automatic m_locks(output int l3, output int l5);
    int last;
    last = (m_bars == 1);
    l3 = 0;
    l5 = (m_bal == 3 && last);
    if (LOCKS) begin
      case (m_bal)
        0: l5 = (m_n1 < 1);
        1: l5 = (m_n1 < 2);
        2: l5 = (m_n1 < 3 && m_n3 == 0);
        default: l5 = last;
      endcase
      l3 = (m_bal == 3 && m_n1 < 2);
    end
  endtask

  task automatic m_outputs(input int b);
    int t;
    x_empty = (m_bars == 0);
    x_busy  = TILL && m_owed != 0;
    m_locks(x_l3, x_l5);
    x_en = !(x_empty || x_busy || (b == 3 && x_l5) || (b == 2 && x_l3));
    x_nxt = m_bal; x_disp = 0; x_chg = 0;
    if (x_en) begin
      if (b == 0) begin x_nxt = 0; x_chg = m_bal; end
      else begin
        t = m_bal + value(b);
        if (t < 4)      x_nxt = t;
        else if (t < 8) begin x_nxt = 0; x_disp = 1; x_chg = t - 4; end
        else            begin x_nxt = 0; x_disp = 2; end
      end
    end
    x_bo = 0;
    if (TILL && m_owed != 0) x_bo = (m_owed == 3 && m_n3 > 0) ? 2 : 1;
  endtask

  task automatic inv_fail(input string s);
    inv_errs++;
    if (inv_errs == 1) inv_first = s;
  endtask

  task automatic m_step(input int r, input int b);
    if (r) m_reset();
    else m_advance(b);
  endtask
  task automatic m_advance(input int b);
    if (x_disp > m_bars) inv_fail($sformatf("dispensed %0d items with %0d in stock", x_disp, m_bars));
    m_bal = x_nxt;
    m_bars -= x_disp;
    if (TILL) begin
      if (x_bo == 1 && m_n1 == 0) inv_fail($sformatf("paid a 1-bill from an empty till (balance %0d)", m_bal));
      if (x_bo == 2 && m_n3 == 0) inv_fail("paid a 3-bill from an empty till");
      if (x_chg != 0)           m_owed = x_chg;
      else if (m_owed == 3)     m_owed = (m_n3 > 0) ? 0 : 2;
      else if (m_owed != 0)     m_owed--;
      if (x_en && b == 1) m_n1++;
      if (x_en && b == 2) m_n3++;
      if (x_en && b == 3) m_n5++;
      if (x_bo == 1) m_n1--;
      if (x_bo == 2) m_n3--;
      if (m_n1 >= (1 << W1) || m_n3 >= (1 << W3) || m_n5 >= (1 << W5))
        inv_fail($sformatf("bill counter overflow (%0d / %0d / %0d)", m_n1, m_n3, m_n5));
    end
  endtask

  // ---------------------------------------------------------------- one clock cycle: drive, compare, clock, step
  int errs, cycle;
  string first_err, note;
  task automatic put(input int r, input int b, input string why);
    rst = r[0]; bill = b[1:0]; note = why;
    m_outputs(b);
    #1;
    if (!r && (dispense !== 2'(x_disp) || change_amt !== 2'(x_chg) || bill_out !== 2'(x_bo) ||
               empty !== x_empty[0] || busy !== x_busy[0] || lock3 !== x_l3[0] || lock5 !== x_l5[0] ||
               balance !== 2'(m_bal) || till1 !== W1'(m_n1) || till3 !== W3'(m_n3) || till5 !== W5'(m_n5) ||
               stock !== 4'(m_bars) || change_due !== 2'(m_owed))) begin
      errs++;
      if (errs == 1)
        first_err = $sformatf("cycle %0d (%s), bill %0d: dispense %0d/%0d change %0d/%0d bill_out %0d/%0d empty %0b/%0d busy %0b/%0d lock3 %0b/%0d lock5 %0b/%0d balance %0d/%0d till %0d,%0d,%0d/%0d,%0d,%0d stock %0d/%0d due %0d/%0d (DUT/model)",
                              cycle, why, b, dispense, x_disp, change_amt, x_chg, bill_out, x_bo, empty, x_empty,
                              busy, x_busy, lock3, x_l3, lock5, x_l5, balance, m_bal, till1, till3, till5, m_n1, m_n3,
                              m_n5, stock, m_bars, change_due, m_owed);
    end
    #4 clk = 1'b1; #5 clk = 1'b0;
    m_step(r, b);
    cycle++;
  endtask
  task automatic reset_all(); put(1, 0, "reset"); endtask
  task automatic idle_until_free(input int extra = 0);
    int n;
    n = 0;
    while (TILL && m_owed != 0) begin
      put(0, (n % 2 == 0) ? extra : 0, "payout in progress");
      n++;
    end
  endtask
  // present a bill only if its slot is open (a protocol-following customer); returns 1 if presented
  task automatic offer(input int b, input string why, output bit ok);
    int l3, l5;
    m_locks(l3, l5);
    ok = !((b == 3 && l5) || (b == 2 && l3));
    if (ok) put(0, b, why);
  endtask
  string msg;
  task automatic group(input string cat, input string name);
    if (errs != 0) msg = first_err;
    else msg = inv_first;
    `CHECK(cat, name, errs == 0 && inv_errs == 0, msg)
    errs = 0; inv_errs = 0; first_err = ""; inv_first = "";
  endtask

  // ---------------------------------------------------------------- scenarios
  bit ok;
  int allowed [3];
  int na, seed_customers;
  initial begin
    errs = 0; inv_errs = 0; cycle = 0;
    m_reset();
    $display("vending_machine configuration %0d: TILL=%0b LOCKS=%0b till %0d/%0d/%0d, counters %0d/%0d/%0d bits",
             CFG, TILL, LOCKS, I1, I3, I5, W1, W3, W5);
    reset_all();
    group("FUNC", "reset: balance 0, all slots open, nothing paid");

    // 1. every (balance, bill) cell of the transition table, then a refund of what is left
    for (int bal = 0; bal < 4; bal++) begin
      for (int b = 0; b < 4; b++) begin
        reset_all();
        if (LOCKS) begin                       // empty till: first let two customers put 1-bills and a 3-bill in
          for (int i = 0; i < 6; i++) begin
            put(0, (i == 4) ? 2 : 1, "prime the till");
            idle_until_free();
          end
        end
        for (int i = 0; i < bal; i++) put(0, 1, "1-bill");
        put(0, b, $sformatf("balance %0d + bill code %0d", bal, b));
        idle_until_free();
        put(0, 0, "refund leftover");
        idle_until_free();
      end
    end
    group("FUNC", "all 16 (balance, bill) cells: next balance, items, change and its payout");

    // 2. sell out, present every bill while empty (ignored), refill with reset
    reset_all();
    while (m_bars > 0) begin
      if (m_bars >= 2 && m_bal == 0 && !(LOCKS && m_n1 < 2)) begin
        offer(2, "sell-out 3 + 5", ok);
        if (ok) offer(3, "sell-out 3 + 5", ok);
        if (!ok) while (m_bal != 0) put(0, 1, "sell-out 1-bills");
      end else
        for (int i = 0; i < 4 && (i == 0 || m_bal != 0); i++) put(0, 1, "sell-out 1-bills");
      idle_until_free();
    end
    group("FUNC", $sformatf("sell out all %0d items", BARS));
    for (int b = 1; b < 4; b++) put(0, b, "empty: bill ignored");
    put(0, 0, "empty: refund request");
    group("ROBUST", "bills offered while empty are ignored");
    reset_all();
    put(0, 3, "after refill");
    idle_until_free();
    group("FUNC", "reset refills the machine");

    // 3. one item left and balance 3: 3 + 5 would need two items, so the 5-slot closes
    reset_all();
    while (m_bars > 1) begin
      for (int i = 0; i < 4; i++) put(0, 1, "drain to one item");
      idle_until_free();
    end
    for (int i = 0; i < 3; i++) put(0, 1, "balance 3 with one item left");
    group("FUNC", "drain to one item, balance 3");
    put(0, 3, "5-bill at the closed slot");
    group("ROBUST", "last item + balance 3: the 5-slot is closed and a 5-bill is ignored");
    put(0, 1, "buy the last item with a 1-bill");
    idle_until_free();
    group("FUNC", "the last item is bought with a 1-bill, then the machine is empty");

    if (TILL) begin
      // 4. change paid bill by bill
      reset_all();
      for (int s = 0; s < 9; s++) begin
        case (s)
          0: begin put(0, 1, "1"); put(0, 0, "refund 1"); end
          1: begin put(0, 1, "1"); put(0, 1, "1"); put(0, 0, "refund 2"); end
          2: begin put(0, 2, "3"); put(0, 0, "refund 3 (a 3-bill)"); end
          3: begin for (int i = 0; i < 3; i++) put(0, 1, "1"); put(0, 0, "refund 3 (three 1-bills)"); end
          4: begin put(0, 1, "1"); offer(3, "1 + 5: change 2", ok); end
          5: begin put(0, 1, "1"); put(0, 1, "1"); offer(3, "1 + 1 + 5: change 3", ok); end
          6: begin put(0, 2, "3"); offer(2, "3 + 3: change 2", ok); end
          7: begin put(0, 1, "1"); offer(2, "1 + 3: exact", ok); end
          default: begin put(0, 2, "3"); put(0, 1, "3 + 1: exact"); end
        endcase
        idle_until_free();
      end
      group("FUNC", "refunds and change of 1, 2 and 3 paid one bill per clock");
      reset_all();
      for (int s = 0; s < 4; s++) begin
        case (s)
          0: begin for (int i = 0; i < 3; i++) put(0, 1, "1"); put(0, 0, "refund 3"); idle_until_free(1); end
          1: begin put(0, 2, "3"); put(0, 0, "refund 3"); idle_until_free(3); end
          2: begin put(0, 1, "1"); put(0, 1, "1"); offer(3, "change 3", ok); idle_until_free(2); end
          default: begin put(0, 2, "3"); offer(2, "change 2", ok); idle_until_free(1); end
        endcase
      end
      group("ROBUST", "bills offered during a payout are ignored");
      // swap three 1-bills for a 3-bill until the till has no 3-bill left, then 3 + 3 still gets its change
      reset_all();
      na = m_n3 + 2;
      for (int k = 0; k < na; k++) begin
        for (int i = 0; i < 3; i++) put(0, 1, "1");
        put(0, 0, "refund 3");
        idle_until_free();
      end
      offer(2, "3", ok); if (!ok) put(0, 1, "1");
      offer(2, "3 + 3", ok); if (!ok) put(0, 1, "1");
      idle_until_free();
      group("FUNC", "3-bills drained by 1+1+1 refunds; change then comes in 1-bills");
    end

    if (LOCKS) begin
      // 5. empty till: every lock case
      reset_all();
      put(0, 3, "5-bill at the onset: no 1-bill for the change");
      put(0, 2, "3-bill: balance 3, 5-slot opens (two items, no change), 3-slot closes");
      put(0, 2, "3-bill at the closed slot");
      put(0, 3, "5-bill: two items, no change");
      idle_until_free();
      for (int i = 0; i < 4; i++) put(0, 1, "four 1-bills: the till now holds four");
      idle_until_free();
      for (int s = 0; s < 5; s++) begin
        case (s)
          0: offer(3, "5 at balance 0", ok);
          1: begin put(0, 1, "1"); offer(3, "5 at balance 1", ok); end
          2: begin put(0, 1, "1"); put(0, 1, "1"); offer(3, "5 at balance 2", ok); end
          3: begin put(0, 2, "3"); offer(2, "3 at balance 3", ok); end
          default: begin for (int i = 0; i < 3; i++) put(0, 1, "1"); offer(2, "3 at balance 3", ok); end
        endcase
        if (!ok) put(0, (s == 3 || s == 4) ? 2 : 3, "bill at a closed slot");
        idle_until_free();
        put(0, 0, "refund leftover");
        idle_until_free();
      end
      group("FUNC", "empty till: each lock opens and closes with the change the till can pay");
    end

    // 6. random customers following the protocol: bills only at open slots, sometimes a refund
    reset_all();
    tb_rng_state = 32'd140 + CFG;
    seed_customers = 400;
`ifdef VERILATOR
    seed_customers = 20000;
`endif
    for (int k = 0; k < seed_customers; k++) begin
      int b, l3, l5;
      bit fin;
      if (m_bars == 0) reset_all();
      repeat (tb_rand() % 3) put(0, 0, "idle");
      fin = 0;
      while (!fin) begin
        m_locks(l3, l5);
        if (m_bal != 0 && tb_rand() % 100 < 15) begin
          put(0, 0, "refund");
          fin = 1;
        end else begin
          na = 0;
          allowed[na++] = 1;
          if (!l3) allowed[na++] = 2;
          if (!l5) allowed[na++] = 3;
          b = allowed[tb_rand() % na];
          put(0, b, "random customer");
          fin = (m_bal == 0);
        end
      end
      idle_until_free();
    end
    group("RANDOM", $sformatf("%0d random customers (outputs every cycle, till and stock invariants)", seed_customers));

    // 7. anything goes: a random bill every cycle, closed slots included, and an occasional reset
    reset_all();
    for (int i = 0; i < 20000; i++)
      put(tb_rand() % 500 == 0, tb_rand() % 4, "random bill");
    group("ROBUST", "20000 cycles of random bills and resets");

    `REPORT
    $finish;
  end
endmodule
