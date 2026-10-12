#!/bin/bash
# run_formal.sh - formal campaign (Yosys + ABC PDR). Every line states the expected outcome; the script exits 1 if
# any outcome differs. Summary: build/formal/summary.txt.
#   1. detector equivalence (SR and JK) against the specification
#   2. Booth multiplier: exact product and latency for every operand pair, both controllers, N = 4 and 6
#   3. vending machine safety for the three till configurations (with the inductive lemmas of vending_formal.sv)
#   4. negative controls: a smaller till, narrower counters, no locks, and broken RTL must all FAIL
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD/mutants
OUT=$OUTD/summary.txt; : > $OUT
FF=rtl/ff_primitives.sv
DET="$FF rtl/seq_detector_sr.sv rtl/seq_detector_jk.sv formal/detector_formal.sv"
BOOTH="$FF rtl/booth_ctrl_mealy.sv rtl/booth_ctrl_moore.sv rtl/booth_skip_mult.sv formal/booth_formal.sv"
VEND="rtl/vending_fsm.sv rtl/change_serializer.sv rtl/vending_machine.sv formal/vending_formal.sv"
bad=0
check() {  # expected tag top files params
  local exp=$1; shift
  local r; r=$(bash formal/pdr.sh "$@")
  local got=${r#*: }; got=${got%% *}
  if [ "$got" = "$exp" ]; then echo "  ok        $r" | tee -a $OUT
  else echo "  UNEXPECTED (expected $exp) $r" | tee -a $OUT; bad=1; fi
}
echo "== detector: SR and JK implementations equal the specification" | tee -a $OUT
check PROVED detector detector_formal "$DET"
echo "== Booth multiplier: product, exact latency N+k+2, no operation after completion" | tee -a $OUT
# QUICK=1 (make formal-quick, used by CI on every push) skips the two slowest groups: Booth N = 6 and the
# 31-bill till. TO is the time limit per proof (seconds); the default leaves room for slower CI machines.
export TO=${TO:-5400}
BOOTH_N=${BOOTH_N:-$([ -n "${QUICK:-}" ] && echo 4 || echo "4 6")}
for n in $BOOTH_N; do
  check PROVED booth_mealy_n$n booth_formal "$BOOTH" "-set N $n -set MOORE 0"
  check PROVED booth_moore_n$n booth_formal "$BOOTH" "-set N $n -set MOORE 1"
done
echo "== vending machine: no payout from an empty till, no counter wrap, no dispensing beyond stock" | tee -a $OUT
[ -n "${QUICK:-}" ] || check PROVED vend_till31      vending_formal "$VEND" "-set N1_INIT 31 -set N3_INIT 31 -set N5_INIT 31"
check PROVED vend_locks       vending_formal "$VEND" "-set LOCKS 1 -set N1_INIT 0 -set N3_INIT 0 -set N5_INIT 0"
check PROVED vend_min_till    vending_formal "$VEND" "-set N1_INIT 30 -set N3_INIT 0 -set N5_INIT 0 -set W1 7 -set W3 5 -set W5 4"
echo "== negative controls: each must FAIL" | tee -a $OUT
check FAILED vend_till29      vending_formal "$VEND" "-set LEMMAS 0 -set N1_INIT 29 -set N3_INIT 0 -set N5_INIT 0 -set W1 7 -set W3 5 -set W5 4"
check FAILED vend_w1_6        vending_formal "$VEND" "-set LEMMAS 0 -set N1_INIT 30 -set N3_INIT 0 -set N5_INIT 0 -set W1 6 -set W3 5 -set W5 4"
check FAILED vend_w3_4        vending_formal "$VEND" "-set LEMMAS 0 -set N1_INIT 30 -set N3_INIT 0 -set N5_INIT 0 -set W1 7 -set W3 4 -set W5 4"
check FAILED vend_no_locks    vending_formal "$VEND" "-set LEMMAS 0 -set LOCKS 0 -set N1_INIT 0 -set N3_INIT 0 -set N5_INIT 0"
mut() {  # name source-file sed-expression files-with-substitution...
  local name=$1 src=$2 expr=$3; shift 3
  sed "$expr" $src > $OUTD/mutants/$name.sv
  cmp -s $src $OUTD/mutants/$name.sv && { echo "  mutation $name did not apply" | tee -a $OUT; bad=1; return; }
  local files; files=$(echo "$*" | sed "s#$src#$OUTD/mutants/$name.sv#")
  echo "$files"
}
f=$(mut det_gate rtl/seq_detector_jk.sv 's/assign k0     = (q\[2\] | ~x) \& (qn\[1\] | x);/assign k0     = (q[2] | ~x);/' "$DET")
[ -n "$f" ] && check FAILED mut_det_gate detector_formal "$f"
f=$(mut booth_no_guard rtl/booth_skip_mult.sv 's/2.b01: a_d = a + {m\[N-1\], m};/2'"'"'b01: a_d = a + {1'"'"'b0, m};/' "$BOOTH")
[ -n "$f" ] && check FAILED mut_booth_no_guard booth_formal "$f" "-set N 4 -set MOORE 0"
f=$(mut booth_moore_cs rtl/booth_skip_mult.sv 's/.current_shift(q_d\[0\])/.current_shift(q[0])/' "$BOOTH")
[ -n "$f" ] && check FAILED mut_booth_moore_cs booth_formal "$f" "-set N 4 -set MOORE 1"
f=$(mut vend_lock3 rtl/vending_machine.sv 's/      lock3 = (balance == 2.d3) \&\& (n1 < W1.(2));/      lock3 = 1'"'"'b0;/' "$VEND")
[ -n "$f" ] && check FAILED mut_vend_lock3 vending_formal "$f" "-set LEMMAS 0 -set LOCKS 1 -set N1_INIT 0 -set N3_INIT 0 -set N5_INIT 0"
if [ $bad -eq 0 ]; then echo "ALL OUTCOMES AS EXPECTED" | tee -a $OUT; else echo "SOME OUTCOMES UNEXPECTED" | tee -a $OUT; fi
exit $bad
