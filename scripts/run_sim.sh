#!/bin/bash
# run_sim.sh SIM NAME TB "DEFINES" RTL... - compiles and runs one testbench with Icarus Verilog (SIM=icarus) or
# Verilator (SIM=verilator), writes build/NAME.SIM.log and prints its FAIL / SUMMARY / RESULT lines.
# Exit status 1 unless the log ends in "RESULT: PASS".
set -u
SIM=$1; NAME=$2; TB=$3; DEFS=$4; shift 4
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=$ROOT/build; mkdir -p "$B"
LOG=$B/$NAME.$SIM.log
cd "$ROOT"
DF=""; for d in $DEFS; do DF="$DF -D$d"; done
if [ "$SIM" = icarus ]; then
  iverilog -g2012 -I tb $DF -o "$B/$NAME.vvp" "$TB" "$@" > "$LOG" 2>&1 && vvp -n "$B/$NAME.vvp" >> "$LOG" 2>&1
else
  top=$(basename "$TB" .sv)
  verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Itb $DF --top-module "$top" \
    -Mdir "$B/obj_$NAME" -o "V$NAME" "$TB" "$@" > "$LOG" 2>&1 && "$B/obj_$NAME/V$NAME" >> "$LOG" 2>&1
fi
printf '%-22s %-9s ' "$NAME" "$SIM"
grep -E "^RESULT" "$LOG" || echo "RESULT: ERROR (see $LOG)"
grep -E "^FAIL" "$LOG" | sed 's/^/    /' | cut -c1-220
grep -q "^RESULT: PASS" "$LOG"
