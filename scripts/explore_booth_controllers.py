"""
explore_booth_controllers.py - Mealy and Moore (core) Booth skip controllers: every candidate state encoding with its
minimum-bit-change cost and exact SOP / POS gate counts (RS flip-flops).
"""
import os
import sys
from itertools import product
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fsm_synth import synth, report, all_encodings, bit_change_cost  # noqa: E402

from fsms import mealy  # noqa: E402

X = (0, 1)
MS, MI, md, mo = mealy()

def survey(name, states, inputs, delta, outs, nbits, fixed, form_list=("SOP", "POS")):
    rows = []
    for enc in all_encodings(states, nbits, fixed):
        bc = bit_change_cost(delta, enc)
        r = {f: synth(states, inputs, delta, outs, enc, "SR", f) for f in form_list}
        rows.append((bc, enc, r))
    best_bc = min(r[0] for r in rows)
    note = " (INIT fixed to all-zeros = power-on state)" if fixed else ""
    print(f"===== {name}: {len(rows)} encodings{note}")
    print(f"{'encoding':44s} bitchg  " + "  ".join(f"{f}:next/out" for f in form_list))
    for bc, enc, r in sorted(rows, key=lambda t: (t[0], min(r['next_unshared'] + r['out_unshared'] for r in t[2].values()))):
        es = " ".join(f"{k}={''.join(map(str, v))}" for k, v in enc.items())
        mark = " <- min bit change" if bc == best_bc else ""
        print(f"{es:44s} {bc:5d}   " + "  ".join(f"{r[f]['next_unshared']:3d}/{r[f]['out_unshared']:<3d}   " for f in form_list) + mark)
    return rows, best_bc

rows, best_bc = survey("Mealy controller", MS, MI, md, mo, 2, {"INIT": (0, 0)})
cands = [(bc, enc, r) for bc, enc, r in rows if bc == best_bc]
bc, enc, r = min(cands, key=lambda t: (min(t[2][f]["next_unshared"] + t[2][f]["out_unshared"] for f in t[2]),))
form = min(r, key=lambda f: r[f]["next_unshared"] + r[f]["out_unshared"])
print("\nCHOSEN Mealy encoding:", {k: "".join(map(str, v)) for k, v in enc.items()}, "form", form)
print(report(r[form], "Mealy controller logic (Q1 Q0 X C):"))

# ---------------- Moore: core states S00 shift, S01 add, S10 sub, S11 shift; input X = next bit (Q[1])
CS = ["S00", "S01", "S10", "S11"]
cd = {("S00", (0,)): "S00", ("S00", (1,)): "S10", ("S01", (0,)): "S00", ("S01", (1,)): "S00",
      ("S10", (0,)): "S11", ("S10", (1,)): "S11", ("S11", (0,)): "S01", ("S11", (1,)): "S11"}
co = {"EX1": {}, "EX0": {}}
for s, (e1, e0) in (("S00", (1, 1)), ("S01", (0, 1)), ("S10", (1, 0)), ("S11", (1, 1))):
    for x in X:
        co["EX1"][(s, (x,))], co["EX0"][(s, (x,))] = e1, e0
rows, best_bc = survey("Moore core (4 states; INIT and END left out)", CS, ["X"], cd, co, 2, None)
