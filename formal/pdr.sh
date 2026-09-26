#!/bin/bash
# pdr.sh TAG TOP "FILES" ["CHPARAM"] - unbounded safety proof of every assertion of formal harness TOP with ABC's
# PDR (IC3), the engine SymbiYosys calls "abc pdr". FILES are relative to the repository root; CHPARAM is a list of
# "-set NAME VALUE" pairs for the harness. TO = time limit in seconds (default 1800).
# Prints one line: "TAG: PROVED ...", "TAG: FAILED ...", "TAG: TIMEOUT ..." or "TAG: ERROR ...".
TAG=$1; TOP=$2; FILES=$3; PARAMS=${4:-}
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD
CH=""; [ -n "$PARAMS" ] && CH="chparam $PARAMS $TOP;"
yosys -q -l $OUTD/$TAG.yosys.log -p "read_verilog -sv -formal -DFORMAL $FILES; $CH \
  prep -top $TOP; flatten; async2sync; chformal -lower; chformal -assume -early; chformal -cover -remove; \
  opt_clean; setundef -anyseq; opt -keepdc -fast; techmap; opt -fast; dffunmap; abc -g AND -fast; opt_clean; \
  write_aiger -I -B -zinit -map $OUTD/$TAG.aim $OUTD/$TAG.aig" > /dev/null 2>&1 || { echo "$TAG: ERROR (yosys, see $OUTD/$TAG.yosys.log)"; exit 2; }
# the AIGER header "aag M I L O A B C J F": B = bad-state properties (the assertions); 0 would be a vacuous "proof"
nb=$(head -1 $OUTD/$TAG.aig | awk '{print $7}')
[ "${nb:-0}" -gt 0 ] || { echo "$TAG: ERROR (no assertions in the model)"; exit 2; }
start=$(date +%s)
timeout ${TO:-1800} yosys-abc -c "read_aiger $OUTD/$TAG.aig; fold; strash; pdr" > $OUTD/$TAG.pdr.log 2>&1
rc=$?
t=$(( $(date +%s) - start ))
if grep -q "Property proved" $OUTD/$TAG.pdr.log; then
  echo "$TAG: PROVED ($nb assertions, unbounded) in ${t}s"
elif grep -qE "was asserted|Counter-example" $OUTD/$TAG.pdr.log; then
  echo "$TAG: FAILED (counterexample, frame $(grep -oE 'frame [0-9]+' $OUTD/$TAG.pdr.log | head -1 | cut -d' ' -f2)) in ${t}s"
elif [ $rc -eq 124 ]; then
  echo "$TAG: TIMEOUT after ${t}s"
else
  echo "$TAG: ERROR (rc=$rc): $(tail -2 $OUTD/$TAG.pdr.log | tr '\n' ' ')"
fi
