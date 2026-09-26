"""
logicmin.py - exact two-level minimisation with don't-cares, costed in 2-input AND/OR gates.

A function of n variables is a list f[m] in {0, 1, None} (None = don't care), minterm m with variable 0 as the most
significant bit.  Implicants/implicates are cubes (value, care): bit j of `care` set means variable j appears.

Cost model (the usual textbook one): complemented literals are free (flip-flops provide Q and QN,
inputs are counted separately), a product/sum term with k literals costs k-1 two-input gates and a function made of
m terms costs another m-1, so a single function costs (total literals - 1).  Identical terms shared between
functions are built once (`shared_cost`).
"""
from __future__ import annotations

from functools import lru_cache
from itertools import product


def ones(x):
    return bin(x).count("1")


def minterms_of(cube, n):
    v, care = cube
    free = [j for j in range(n) if not (care >> (n - 1 - j)) & 1]
    out = []
    for bits in product((0, 1), repeat=len(free)):
        m = v
        for j, b in zip(free, bits):
            if b:
                m |= 1 << (n - 1 - j)
        out.append(m)
    return out


def primes(f, n, value=1):
    """prime implicants of f (value=1) or prime implicates of f (value=0), with don't cares."""
    full = (1 << n) - 1
    cur = {(m, full) for m in range(1 << n) if f[m] == value or f[m] is None}
    result = set()
    while cur:
        nxt, used = set(), set()
        lst = sorted(cur)
        by_care = {}
        for c in lst:
            by_care.setdefault(c[1], []).append(c)
        for care, cs in by_care.items():
            s = set(cs)
            for v, _ in cs:
                for j in range(n):
                    bit = 1 << (n - 1 - j)
                    if care & bit and not v & bit:
                        o = (v | bit, care)
                        if o in s:
                            nxt.add((v, care & ~bit))
                            used.add((v, care))
                            used.add(o)
        result |= cur - used
        cur = nxt
    # keep only cubes that cover at least one required point
    req = [m for m in range(1 << n) if f[m] == value]
    return [c for c in sorted(result) if any((m & c[1]) == c[0] for m in req)]


def lits(c):
    return ones(c[1])


def covers(c, m):
    return (m & c[1]) == c[0]


def min_covers(f, n, value=1, limit=64):
    """all minimum-cost covers (cost = total literals, tie -> fewer terms). value=1: SOP, value=0: POS."""
    req = [m for m in range(1 << n) if f[m] == value]
    if not req:
        return [[]]
    ps = primes(f, n, value)
    cov = {m: [i for i, p in enumerate(ps) if covers(p, m)] for m in req}
    best = [None]
    sols = []

    def cost(sel):
        return (sum(lits(ps[i]) for i in sel), len(sel))

    def rec(sel, uncovered):
        c = cost(sel)
        if best[0] is not None and c > best[0]:
            return
        if not uncovered:
            if best[0] is None or c < best[0]:
                best[0] = c
                sols.clear()
            if c == best[0] and len(sols) < limit:
                key = tuple(sorted(sel))
                if key not in {tuple(sorted(s)) for s in sols}:
                    sols.append(list(sel))
            return
        # branch on the uncovered point with the fewest candidate primes
        m = min(uncovered, key=lambda x: len(cov[x]))
        for i in cov[m]:
            if i in sel:
                continue
            rest = [u for u in uncovered if not covers(ps[i], u)]
            rec(sel + [i], rest)

    rec([], req)
    return [[ps[i] for i in s] for s in sols]


def fcost(cover):
    if not cover:
        return 0
    return sum(lits(c) for c in cover) - 1


def term_str(c, names, sop=True):
    n = len(names)
    v, care = c
    parts = []
    for j in range(n):
        bit = 1 << (n - 1 - j)
        if care & bit:
            pos = bool(v & bit)
            if sop:
                parts.append(names[j] + ("" if pos else "'"))
            else:
                parts.append(names[j] + ("'" if pos else ""))
    if sop:
        return "".join(parts) if parts else "1"
    return ("(" + " + ".join(parts) + ")") if len(parts) > 1 else (parts[0] if parts else "0")


def expr(cover, names, sop=True):
    if not cover:
        return "0" if sop else "1"
    if sop:
        return " + ".join(term_str(c, names, True) for c in cover)
    return "".join(term_str(c, names, False) for c in cover)


def shared_cost(covers_by_fn):
    """2-input gate count when identical terms are shared: unique terms (k-1 each) + per function (m-1)."""
    uniq = set()
    total = 0
    for cov in covers_by_fn:
        for c in cov:
            if lits(c) > 1:
                uniq.add(c)
        if len(cov) > 1:
            total += len(cov) - 1
    return total + sum(lits(c) - 1 for c in uniq)


def best_multi(fns, n, value=1, limit=64):
    """choose one minimum cover per function so that the shared cost is minimal.
    fns: list of truth tables. Returns (unshared_cost, shared_cost, covers)."""
    options = [min_covers(f, n, value, limit) for f in fns]
    unshared = sum(fcost(o[0]) for o in options)
    best = None
    # exhaustive over combinations (bounded)
    total = 1
    for o in options:
        total *= len(o)
    if total > 20000:
        options = [o[:4] for o in options]
    for combo in product(*options):
        sc = shared_cost(combo)
        if best is None or sc < best[0]:
            best = (sc, list(combo))
    return unshared, best[0], best[1]


def kmap_str(f, names):
    """ASCII K-map for 3 or 4 variables (rows = last two / last variable, columns = first two, Gray order)."""
    n = len(names)
    gray = ["00", "01", "11", "10"]
    ch = lambda v: "X" if v is None else str(v)
    if n == 4:
        head = f"{names[2]}{names[3]} \\ {names[0]}{names[1]}"
        lines = [f"{head:>10} | " + "  ".join(gray)]
        for r in gray:
            row = [ch(f[int(c + r, 2)]) for c in gray]
            lines.append(f"{r:>10} | " + "   ".join(row))
        return "\n".join(lines)
    if n == 3:
        head = f"{names[2]} \\ {names[0]}{names[1]}"
        lines = [f"{head:>10} | " + "  ".join(gray)]
        for r in "01":
            row = [ch(f[int(c + r, 2)]) for c in gray]
            lines.append(f"{r:>10} | " + "   ".join(row))
        return "\n".join(lines)
    return " ".join(ch(v) for v in f)


if __name__ == "__main__":
    # self-test against brute force on random 4-variable functions
    import random
    rnd = random.Random(1)
    for _ in range(300):
        f = [rnd.choice([0, 1, 1, None]) for _ in range(16)]
        for value in (1, 0):
            best = min_covers(f, 4, value)
            for cov in best:
                for m in range(16):
                    if f[m] is None:
                        continue
                    hit = any(covers(c, m) for c in cov)
                    got = int(hit) if value == 1 else int(not hit)
                    assert got == f[m], (f, value, cov)
            # brute force minimum literal count over all subsets of primes
            ps = primes(f, 4, value)
            req = [m for m in range(16) if f[m] == value]
            bestc = None
            from itertools import combinations
            for k in range(0, len(ps) + 1):
                for sub in combinations(ps, k):
                    if all(any(covers(c, m) for c in sub) for m in req):
                        cc = (sum(lits(c) for c in sub), len(sub))
                        if bestc is None or cc < bestc:
                            bestc = cc
                if bestc is not None and k > bestc[1] + 3:
                    break
            got = (sum(lits(c) for c in best[0]), len(best[0])) if best[0] else (0, 0)
            assert got == bestc or (not req and got == (0, 0)), (f, value, got, bestc)
    print("logicmin self-test passed")
