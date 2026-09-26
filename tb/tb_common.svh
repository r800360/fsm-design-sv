// tb_common.svh - small self-checking testbench helpers shared by the testbenches of this repository.
//
//   `CHECK("CATEGORY", "name", condition, "message if it fails")
//   `REPORT            summary line; the run passes when no check outside category INFO failed
//
// INFO checks document behaviour that is outside the specification (reported, never counted as a failure).
`ifndef TB_COMMON_SVH
`define TB_COMMON_SVH

int tb_pass = 0, tb_fail = 0, tb_info_pass = 0, tb_info_fail = 0;

`define CHECK(CAT, NAME, COND, MSG) \
  begin \
    if (COND) begin \
      $display("PASS [%-6s] %s", (CAT), NAME); \
      if ((CAT) == "INFO") tb_info_pass++; else tb_pass++; \
    end else begin \
      $display("FAIL [%-6s] %s :: %s", (CAT), NAME, MSG); \
      if ((CAT) == "INFO") tb_info_fail++; else tb_fail++; \
    end \
  end

// xorshift32: identical pseudo-random sequences in every simulator
logic [31:0] tb_rng_state = 32'h1234_5678;
function automatic logic [31:0] tb_rand();
  logic [31:0] x;
  x = tb_rng_state;
  x ^= x << 13; x ^= x >> 17; x ^= x << 5;
  tb_rng_state = x;
  return x;
endfunction

`define REPORT \
  begin \
    $display("------------------------------------------------------------------"); \
    $display("SUMMARY: %0d passed, %0d failed   (info: %0d passed, %0d failed)", tb_pass, tb_fail, tb_info_pass, \
             tb_info_fail); \
    if (tb_fail == 0) $display("RESULT: PASS"); else $display("RESULT: FAIL"); \
    $display("------------------------------------------------------------------"); \
  end

`endif
