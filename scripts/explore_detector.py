"""
explore_detector.py - composite Z1 (101) / Z2 (011) detector: builds the 10-state composite machine, minimises it to
8 states, lists the prioritized-adjacency groups and scores all 8! encodings (RS and JK flip-flops, POS logic).
"""
import os
import sys
from itertools import combinations, permutations, product
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fsm_synth import synth, report  # noqa: E402

from fsms import BASE_DETECTOR as A, composite10, minimise  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "explore")

# the base machine: see fsms.BASE_DETECTOR (S1 = '..0', S2 = '..1', S3 = '01', S4 = '10').
# brute-force check that the decoded machine is a 101 / 011 recogniser
def run(m, start, seq):
    s, out = start, []
    for b in seq:
        s, z1, z2 = m[s][b]
        out.append((z1, z2))
    return out
for L in range(1, 11):
    for seq in product((0, 1), repeat=L):
        got = run(A, "S0", seq)
        for i in range(L):
            w = seq[max(0, i - 2):i + 1]
            assert got[i] == (int(w == (1, 0, 1)), int(w == (0, 1, 1))), (seq, i)
print("base machine: Z1 detects 101, Z2 detects 011 (overlapping) - verified on all sequences up to length 10")

# ---- composite machine (fsms.composite10): Z2 edges enter the Z1-only copy T*, Z1 edges of the copy return.
C = composite10()
print("\n10-state composite FSM (state: input -> next/Z1Z2):")
for s in C:
    print("  ", s, "  ".join(f"{b}->{n}/{z1}{z2}" for b, (n, z1, z2) in C[s].items()))

# ---- minimisation by partition refinement (fsms.minimise)
part = minimise(C)
print("\nequivalence classes:", part)
rep = {s: bl[0] if len(bl) == 1 else "/".join(bl) for bl in part for s in bl}
M = {}
for bl in part:
    s = bl[0]
    M[rep[s]] = {b: (rep[C[s][b][0]], C[s][b][1], C[s][b][2]) for b in (0, 1)}
print("8-state machine:")
for s in M:
    print("  ", s, "  ".join(f"{b}->{n}/{z1}{z2}" for b, (n, z1, z2) in M[s].items()))
ST = list(M)

# ---- prioritized adjacency groups
p1 = []   # same next state under the same input
for b in (0, 1):
    grp = {}
    for s in ST:
        grp.setdefault(M[s][b][0], []).append(s)
    for n, ss in grp.items():
        if len(ss) > 1:
            p1.append((tuple(ss), f"-> {n} on {b}"))
p2 = [((M[s][0][0], M[s][1][0]), f"next states of {s}") for s in ST if M[s][0][0] != M[s][1][0]]
p3 = []
for a, b in combinations(ST, 2):
    if all(M[a][x][1:] == M[b][x][1:] for x in (0, 1)):
        p3.append((a, b))
print("\npriority 1 groups:", [g for g, _ in p1])
print("priority 2 groups:", [g for g, _ in p2])
print(f"priority 3 (same outputs): {len(p3)} pairs")

def pair_w(groups):
    w = {}
    for g, _ in groups:
        for a, b in combinations(sorted(g), 2):
            w[(a, b)] = w.get((a, b), 0) + 1
    return w
w1, w2 = pair_w(p1), pair_w(p2)

def adj(enc, a, b):
    return sum(x != y for x, y in zip(enc[a], enc[b])) == 1

def score(enc):
    return (sum(w for (a, b), w in w1.items() if adj(enc, a, b)),
            sum(w for (a, b), w in w2.items() if adj(enc, a, b)))

X = (0, 1)
delta = {(s, (b,)): M[s][b][0] for s in ST for b in X}
outs = {"Z1": {(s, (b,)): M[s][b][1] for s in ST for b in X}, "Z2": {(s, (b,)): M[s][b][2] for s in ST for b in X}}
codes = list(product((0, 1), repeat=3))
seen = set()
rows = []
for perm in permutations(codes):
    enc = dict(zip(ST, perm))
    # canonical form under bit permutation / complement (these do not change POS cost for SR / JK: complementing a
    # state bit swaps S<->R (J<->K) and literal polarity, both free)
    canon = None
    for bp in permutations(range(3)):
        for cm in product((0, 1), repeat=3):
            t = tuple(tuple(enc[s][bp[i]] ^ cm[i] for i in range(3)) for s in ST)
            if canon is None or t < canon:
                canon = t
    if canon in seen:
        continue
    seen.add(canon)
    rows.append((score(enc), enc))
print(f"\n{len(rows)} encodings up to bit permutation/complement")
res = []
for sc, enc in rows:
    sr = synth(ST, ["X"], delta, outs, enc, "SR", "POS", names=["Q2", "Q1", "Q0", "X"])
    jk = synth(ST, ["X"], delta, outs, enc, "JK", "POS", names=["Q2", "Q1", "Q0", "X"])
    res.append((sc, enc, sr, jk))
maxp1 = max(r[0][0] for r in res)
top = [r for r in res if r[0][0] == maxp1]
maxp2 = max(r[0][1] for r in top)
heur = [r for r in top if r[0][1] == maxp2]
print(f"max priority-1 weight satisfied: {maxp1} of {sum(w1.values())}; then max priority-2: {maxp2} of {sum(w2.values())};"
      f" {len(heur)} encodings reach both")
for sc, enc, sr, jk in sorted(heur, key=lambda r: (r[2]['next_unshared'] + r[3]['next_unshared'])):
    print(f"  SR next {sr['next_unshared']:2d} ({sr['next_shared']:2d} shared)  JK next {jk['next_unshared']:2d} "
          f"({jk['next_shared']:2d} shared)  out {sr['out_unshared']}  " + " ".join(f"{k}={''.join(map(str, v))}" for k, v in enc.items()))
bsr = min(res, key=lambda r: (r[2]['next_unshared'], r[2]['next_shared']))
bjk = min(res, key=lambda r: (r[3]['next_unshared'], r[3]['next_shared']))
print(f"\nexhaustive optimum: SR next {bsr[2]['next_unshared']} (priority score {bsr[0]}), JK next {bjk[3]['next_unshared']} (priority score {bjk[0]})")
import pickle
os.makedirs(OUT, exist_ok=True)
pickle.dump({"M": M, "ST": ST, "p1": p1, "p2": p2, "res": res, "heur": heur, "delta": delta, "outs": outs},
            open(os.path.join(OUT, "detector.pkl"), "wb"))
