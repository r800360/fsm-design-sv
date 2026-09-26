"""
explore_detector_pick.py - among the detector encodings that satisfy the most priority-1 adjacencies (scored by
explore_detector.py, which must run first), lists the cheapest and prints the full synthesis report of the best one.
"""
import os
import pickle
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fsm_synth import report  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "explore")
d = pickle.load(open(os.path.join(OUT, "detector.pkl"), "rb"))
res = d["res"]
maxp1 = max(r[0][0] for r in res)
top = sorted([r for r in res if r[0][0] == maxp1], key=lambda r: (r[2]['next_unshared'] + r[3]['next_unshared'], -r[0][1]))
print("encodings satisfying the maximum priority-1 weight, best first:")
for sc, enc, sr, jk in top[:10]:
    print(f"  P2 {sc[1]}  SR {sr['next_unshared']:2d}/{sr['next_shared']:2d}  JK {jk['next_unshared']:2d}/{jk['next_shared']:2d}  out {sr['out_unshared']}  " +
          " ".join(f"{k}={''.join(map(str, v))}" for k, v in enc.items()))
sc, enc, sr, jk = top[0]
print("\nCHOSEN:", {k: ''.join(map(str, v)) for k, v in enc.items()}, "priority score", sc)
print(report(sr, "RS flip-flops, POS:"))
print(report(jk, "JK flip-flops, POS:"))
