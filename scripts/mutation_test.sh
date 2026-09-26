#!/bin/bash
# mutation_test.sh - measures the testbenches: each mutant is a copy of the RTL with one deliberate bug, and the
# named testbench must FAIL on it (Icarus Verilog). Prints the first failing check per mutant. Exit 1 if any mutant
# survives. Summary: build/mutants/summary.txt.
cd "$(dirname "$0")/.."
M=build/mutants; mkdir -p $M
S=$M/summary.txt; : > $S
FF=rtl/ff_primitives.sv
BOOTH="$FF rtl/booth_ctrl_mealy.sv rtl/booth_ctrl_moore.sv rtl/booth_skip_mult.sv"
DET="$FF rtl/seq_detector_sr.sv rtl/seq_detector_jk.sv"
VEND="rtl/vending_fsm.sv rtl/change_serializer.sv rtl/vending_machine.sv"
survived=0; total=0
mutant() {  # name tb "defines" "rtl files" file-to-mutate sed-expression
  local name=$1 tb=$2 defs=$3 files=$4 src=$5 expr=$6
  total=$((total + 1))
  mkdir -p $M/$name
  sed "$expr" $src > $M/$name/$(basename $src)
  if cmp -s $src $M/$name/$(basename $src); then echo "$name: mutation did not apply" | tee -a $S; survived=1; return; fi
  local f=$(echo "$files" | sed "s#$src#$M/$name/$(basename $src)#")
  local df=""; for d in $defs; do df="$df -D$d"; done
  iverilog -g2012 -I tb $df -o $M/$name/sim.vvp $tb $f > $M/$name/log.txt 2>&1 && vvp -n $M/$name/sim.vvp >> $M/$name/log.txt 2>&1
  if grep -q "^RESULT: PASS" $M/$name/log.txt; then
    printf '%-22s SURVIVED\n' $name | tee -a $S; survived=1
  else
    printf '%-22s killed: %s\n' $name "$(grep -m1 '^FAIL' $M/$name/log.txt | cut -c1-110)" | tee -a $S
  fi
}
# flip-flop conversions
mutant pt_k_wrong        tb/tb_ff.sv "" "$FF" $FF 's/.k(p ^ t)/.k(t)/'
mutant srpt_t_wrong      tb/tb_ff.sv "" "$FF" $FF 's/.t(s | r)/.t(r)/'
mutant d_from_sr_wrong   tb/tb_ff.sv "" "$FF" $FF 's/.s(d), .r(~d)/.s(d), .r(1'"'"'b0)/'
# Booth multiplier
mutant booth_no_sign_ext tb/tb_booth.sv "" "$BOOTH" rtl/booth_skip_mult.sv 's/2.b01: a_d = a + {m\[N-1\], m};/2'"'"'b01: a_d = a + {1'"'"'b0, m};/'
mutant booth_no_freeze   tb/tb_booth.sv "" "$BOOTH" rtl/booth_skip_mult.sv 's/end else if (!completed) begin/end else begin/'
mutant booth_count_short tb/tb_booth.sv "" "$BOOTH" rtl/booth_skip_mult.sv "s/assign completed = (count == CW'(N));/assign completed = (count == CW'(N - 1));/"
mutant booth_mealy_gate  tb/tb_booth.sv "" "$BOOTH" rtl/booth_ctrl_mealy.sv 's/assign ex0    = q\[0\] \& (q\[1\] | ~shift_in);/assign ex0    = q[0];/'
mutant booth_moore_cs    tb/tb_booth.sv "MOORE" "$BOOTH" rtl/booth_skip_mult.sv 's/.current_shift(q_d\[0\])/.current_shift(q[0])/'
mutant booth_moore_gate  tb/tb_booth.sv "MOORE" "$BOOTH" rtl/booth_ctrl_moore.sv 's/assign r2     = (qn\[1\] \& q\[0\] \& ~shift_in \& ~completed);/assign r2     = (qn[1] \& q[0] \& ~shift_in);/'
# sequence detectors
mutant det_sr_s0         tb/tb_detector.sv "" "$DET" rtl/seq_detector_sr.sv 's/assign s0     = qn\[0\] \& (qn\[2\] | q\[1\]);/assign s0     = qn[0] \& qn[2];/'
mutant det_jk_k2         tb/tb_detector.sv "" "$DET" rtl/seq_detector_jk.sv 's/assign k2     = q\[0\] \& ~x \& qn\[1\];/assign k2     = q[0] \& ~x;/'
mutant det_z2_no_mode    tb/tb_detector.sv "" "$DET" rtl/seq_detector_jk.sv 's/assign z2     = q\[2\] \& q\[0\] \& x \& qn\[1\];/assign z2     = q[0] \& x \& qn[1] \& qn[2] | q[2] \& q[0] \& x \& qn[1];/'
# vending machine
mutant vend_fsm_d0       tb/tb_vending.sv "CFG=2" "$VEND" rtl/vending_fsm.sv 's/assign d0     = (bill\[1\] | bill\[0\]) \& /assign d0     = /'
mutant vend_no_last_lock tb/tb_vending.sv "CFG=2" "$VEND" rtl/vending_machine.sv "s/    lock5 = (balance == 2'd3) \&\& last;/    lock5 = 1'b0;/"
mutant vend_have3_stuck  tb/tb_vending.sv "CFG=3" "$VEND" rtl/vending_machine.sv "s/assign have3  = (n3 != '0);/assign have3  = 1'b1;/"
mutant vend_count_closed tb/tb_vending.sv "CFG=3" "$VEND" rtl/vending_machine.sv "s/assign accept = en \&\& (bill != 2'b00);/assign accept = (bill != 2'b00);/"
mutant vend_ignore_busy  tb/tb_vending.sv "CFG=3" "$VEND" rtl/vending_machine.sv "s/assign en = !(empty || busy ||/assign en = !(empty ||/"
mutant vend_serial_bo0   tb/tb_vending.sv "CFG=3" "$VEND" rtl/change_serializer.sv 's/assign bo0    = (owed\[1\] | owed\[0\]) \& (~owed\[1\] | ~owed\[0\] | ~have3)/assign bo0    = (owed[1] | owed[0])/'
mutant vend_no_lock3     tb/tb_vending.sv "CFG=4" "$VEND" rtl/vending_machine.sv "s/      lock3 = (balance == 2'd3) \&\& (n1 < W1'(2));/      lock3 = 1'b0;/"
mutant vend_lock5_bal1   tb/tb_vending.sv "CFG=4" "$VEND" rtl/vending_machine.sv "s/2'd1: lock5 = (n1 < W1'(2));/2'd1: lock5 = (n1 < W1'(1));/"
mutant vend_lock5_bal2   tb/tb_vending.sv "CFG=4" "$VEND" rtl/vending_machine.sv "s/2'd2: lock5 = (n1 < W1'(3)) \&\& (n3 == '0);/2'd2: lock5 = (n1 < W1'(3));/"
echo "$total mutants" | tee -a $S
[ $survived -eq 0 ] && echo "ALL MUTANTS KILLED" | tee -a $S || echo "SOME MUTANTS SURVIVED" | tee -a $S
exit $survived
