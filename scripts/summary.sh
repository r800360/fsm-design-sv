#!/bin/bash
# summary.sh - collects every result under build/ into build/SUMMARY.md: testbench verdicts, formal outcomes,
# mutation score, synthesis statistics and the other reports the make targets write. CI shows it on the run page and
# attaches it to releases.
cd "$(dirname "$0")/.."
mkdir -p build
REV=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}
{
  echo "# $(basename "$(pwd)") verification summary"
  echo
  echo "Commit \`${REV:0:12}\`, $(date -u '+%Y-%m-%d %H:%M UTC')."
  sims=$(ls build/*.icarus.log build/*.verilator.log 2>/dev/null)
  if [ -n "$sims" ]; then
    echo; echo "## Testbenches"; echo; echo "| Testbench | Simulator | Result | Checks |"; echo "|---|---|---|---|"
    for f in $sims; do
      b=$(basename "$f" .log); name=${b%.*}; sim=${b##*.}
      res=$(grep -m1 -oE "RESULT: [A-Z]+" "$f" | cut -d' ' -f2); res=${res:-ERROR}
      checks=$(grep -m1 -oE "SUMMARY: [0-9]+ passed, [0-9]+ failed" "$f" | sed 's/SUMMARY: //')
      echo "| $name | $sim | $res | ${checks:--} |"
    done
  fi
  for sec in "formal:Formal verification" "mutants:Mutation testing" "synth:Synthesis (Yosys, generic gates)" \
             "gates:Structural gate counts" "equivalence:Equivalence checking" "explore:Design-space exploration"; do
    r="build/${sec%%:*}/summary.txt"
    [ -s "$r" ] || continue
    echo; echo "## ${sec#*:}"; echo; echo '```'; cat "$r"; echo '```'
  done
} > build/SUMMARY.md
cat build/SUMMARY.md
