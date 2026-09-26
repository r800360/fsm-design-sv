"""explore_moore.py - Moore Booth controller with INIT and END (3 RS flip-flops): survey of all encodings with INIT = 000."""
import os
import sys
from itertools import product
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fsm_synth import synth, report, all_encodings  # noqa: E402

from fsms import moore  # noqa: E402

ST, IN, d, o = moore()

res = []
for enc in all_encodings(ST, 3, {"INIT": (0, 0, 0)}):
    best = None
    for form in ("SOP", "POS"):
        r = synth(ST, IN, d, o, enc, "SR", form)
        tot = r["next_unshared"] + r["out_unshared"]
        if best is None or tot < best[0]:
            best = (tot, form, r)
    res.append((best[0], enc, best[1], best[2]))
res.sort(key=lambda t: (t[0], t[3]["next_unshared"]))
print("best 12 encodings of 2520 (INIT=000):")
for tot, enc, form, r in res[:12]:
    print(f"  total {tot:2d} (next {r['next_unshared']:2d}, out {r['out_unshared']:2d}) {form}  " +
          " ".join(f"{k}={''.join(map(str, v))}" for k, v in enc.items()))
# the separable encoding suggested for readability: core states keep the (minimum-bit-change) window code in Q1Q0
sep = [t for t in res if all(t[1][s][1:] == tuple(int(b) for b in s[1:]) and t[1][s][0] == 1 for s in ("S00", "S01", "S10", "S11"))]
print("\nseparable encodings (core = 1<window>):")
for tot, enc, form, r in sep:
    print(f"  total {tot:2d} (next {r['next_unshared']:2d}, out {r['out_unshared']:2d}) {form}  " +
          " ".join(f"{k}={''.join(map(str, v))}" for k, v in enc.items()))
tot, enc, form, r = sep[0]
print("\nseparable alternative (Q1Q0 = Booth window, one gate more):", {k: ''.join(map(str, v)) for k, v in enc.items()}, form)
print(report(r, "Moore controller logic, separable alternative (Q2 Q1 Q0 X CS C):"))

print("\n==== CHOSEN: global optimum (fsms.MOORE_ENC); its core states still form a Gray cycle")
tot, enc, form, r = res[0]
print({k: ''.join(map(str, v)) for k, v in enc.items()}, form)
from fsms import MOORE_ENC
assert enc == MOORE_ENC, (enc, MOORE_ENC)
print(report(r, "Moore controller logic, chosen (Q2 Q1 Q0 X CS C):"))
