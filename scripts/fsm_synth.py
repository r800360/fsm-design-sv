"""
fsm_synth.py - next-state / output logic synthesis for small FSMs with SR, JK or D flip-flops.

An FSM is given symbolically:
    states  : list of state names
    inputs  : list of input variable names (1 bit each)
    delta   : dict (state, input_tuple) -> next state        (missing = don't care)
    outputs : dict name -> dict (state, input_tuple) -> 0/1/None   (Mealy; a Moore output ignores the inputs)
An encoding maps each state to a tuple of bits (MSB first).  Truth tables are indexed by the minterm
(state bits ... , input bits ...), MSB first, so K-maps read "Q2 Q1 Q0 X".
"""
from __future__ import annotations

from itertools import permutations, product

from logicmin import best_multi, expr, fcost, kmap_str, min_covers

EXC = {
    "SR": {(0, 0): (0, None), (0, 1): (1, 0), (1, 0): (0, 1), (1, 1): (None, 0)},
    "JK": {(0, 0): (0, None), (0, 1): (1, None), (1, 0): (None, 1), (1, 1): (None, 0)},
    "D": {(0, 0): (0,), (0, 1): (1,), (1, 0): (0,), (1, 1): (1,)},
}
PINS = {"SR": ("S", "R"), "JK": ("J", "K"), "D": ("D",)}


def tables(states, inputs, delta, outputs, enc, ff):
    nb = len(next(iter(enc.values())))
    ni = len(inputs)
    n = nb + ni
    code2state = {tuple(v): k for k, v in enc.items()}
    fns = {}
    for b in range(nb):
        for p in PINS[ff]:
            fns[f"{p}{nb - 1 - b}"] = [None] * (1 << n)
    outs = {o: [None] * (1 << n) for o in outputs}
    for m in range(1 << n):
        bits = [(m >> (n - 1 - j)) & 1 for j in range(n)]
        q, x = tuple(bits[:nb]), tuple(bits[nb:])
        s = code2state.get(q)
        if s is None:
            continue
        for o in outputs:
            outs[o][m] = outputs[o].get((s, x))
        nxt = delta.get((s, x))
        if nxt is None:
            continue
        qn = enc[nxt]
        for b in range(nb):
            ex = EXC[ff][(q[b], qn[b])]
            for p, v in zip(PINS[ff], ex):
                fns[f"{p}{nb - 1 - b}"][m] = v
    return n, fns, outs


def synth(states, inputs, delta, outputs, enc, ff, form="SOP", names=None):
    """returns dict with per-function covers and gate counts (next-state and outputs separately)."""
    n, fns, outs = tables(states, inputs, delta, outputs, enc, ff)
    nb = n - len(inputs)
    names = names or [f"Q{nb - 1 - b}" for b in range(nb)] + list(inputs)
    value = 1 if form == "SOP" else 0
    keys = list(fns)
    un, sh, covs = best_multi([fns[k] for k in keys], n, value)
    okeys = list(outs)
    oun, osh, ocovs = best_multi([outs[k] for k in okeys], n, value) if okeys else (0, 0, [])
    return {
        "n": n, "names": names, "form": form,
        "next": {k: (fns[k], c) for k, c in zip(keys, covs)}, "next_unshared": un, "next_shared": sh,
        "out": {k: (outs[k], c) for k, c in zip(okeys, ocovs)}, "out_unshared": oun, "out_shared": osh,
    }


def report(res, title=""):
    sop = res["form"] == "SOP"
    lines = [title] if title else []
    for grp, key in (("next-state", "next"), ("output", "out")):
        for k, (f, c) in res[key].items():
            lines.append(f"  {k:6s} = {expr(c, res['names'], sop):40s} [{fcost(c)} gates]")
            if len(res["names"]) in (3, 4):
                lines.append("    " + kmap_str(f, res["names"]).replace("\n", "\n    "))
    lines.append(f"  next-state logic: {res['next_unshared']} two-input gates ({res['next_shared']} with shared terms);"
                 f" outputs: {res['out_unshared']} ({res['out_shared']} shared)")
    return "\n".join(lines)


def all_encodings(states, nbits, fixed=None):
    codes = list(product((0, 1), repeat=nbits))
    fixed = fixed or {}
    free_states = [s for s in states if s not in fixed]
    free_codes = [c for c in codes if c not in fixed.values()]
    for perm in permutations(free_codes, len(free_states)):
        enc = dict(fixed)
        enc.update(zip(free_states, perm))
        yield enc


def hamming(a, b):
    return sum(x != y for x, y in zip(a, b))


def bit_change_cost(delta, enc, ninputs_weight=None):
    """minimum-bit-change heuristic: sum over transitions of (#input combinations) x Hamming distance."""
    return sum(hamming(enc[s], enc[t]) for (s, x), t in delta.items() if t is not None)
