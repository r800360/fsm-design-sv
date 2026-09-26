#!/bin/bash
# synth.sh - Yosys synthesis of every block to a generic gate library (synth -flatten; abc -g gates); prints
# flip-flops, two-input gates and inverters per block. Full statistics in build/synth/<block>.txt.
cd "$(dirname "$0")/.."
B=build/synth; mkdir -p $B
FF=rtl/ff_primitives.sv
BOOTH="$FF rtl/booth_ctrl_mealy.sv rtl/booth_ctrl_moore.sv rtl/booth_skip_mult.sv"
DET="$FF rtl/seq_detector_sr.sv rtl/seq_detector_jk.sv"
VEND="rtl/vending_fsm.sv rtl/change_serializer.sv rtl/vending_machine.sv"
printf '%-34s %6s %6s %6s %6s\n' block FFs gates inv total | tee $B/summary.txt
one() {  # name top files [chparam]
  local name=$1 top=$2 files=$3 ch=""
  [ -n "${4:-}" ] && ch="chparam $4 $top;"
  yosys -q -p "read_verilog -sv $files; $ch synth -top $top -flatten; abc -g gates; opt_clean; tee -q -o $B/$name.txt stat" \
    > $B/$name.log 2>&1 || { echo "$name: yosys failed (see $B/$name.log)"; return; }
  awk -v n="$name" '
    /^ +\$_/ { c=$1; v=$2; if (c ~ /DFF|DLATCH|SR_/) ff+=v; else if (c=="$_NOT_") inv+=v; else g+=v }
    END { printf "%-34s %6d %6d %6d %6d\n", n, ff, g, inv, ff+g+inv }' $B/$name.txt | tee -a $B/summary.txt
}
one booth_ctrl_mealy            booth_ctrl_mealy "$BOOTH"
one booth_ctrl_moore            booth_ctrl_moore "$BOOTH"
one booth_skip_mult_mealy_n13   booth_skip_mult  "$BOOTH" "-set MOORE 0"
one booth_skip_mult_moore_n13   booth_skip_mult  "$BOOTH" "-set MOORE 1"
one seq_detector_sr             seq_detector_sr  "$DET"
one seq_detector_jk             seq_detector_jk  "$DET"
one vending_fsm                 vending_fsm      "$VEND"
one change_serializer           change_serializer "$VEND"
one vending_machine_no_till     vending_machine  "$VEND" "-set TILL 0"
one vending_machine_till31      vending_machine  "$VEND"
one vending_machine_locks       vending_machine  "$VEND" "-set LOCKS 1 -set N1_INIT 0 -set N3_INIT 0 -set N5_INIT 0"
one vending_machine_min_till    vending_machine  "$VEND" "-set N1_INIT 30 -set N3_INIT 0 -set N5_INIT 0 -set W1 7 -set W3 5 -set W5 4"
