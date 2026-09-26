"""
fsms.py - symbolic definitions of every state machine in this repository and the encodings chosen for the RTL.
Used by explore_*.py (which justify the choices) and by emit_sv.py (which writes the gate-level RTL from them).
"""
import os
import sys
from itertools import product

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fsm_synth import synth  # noqa: E402

B = (0, 1)


# ------------------------------------------------------------------ Booth multiplier controller, Mealy
def mealy():
    states = ["INIT", "A", "B", "END"]           # A = last multiplier bit 0 (old 00/01), B = last bit 1 (old 10/11)
    inputs = ["X", "C"]                          # X = SHIFT_IN = multiplier LSB, C = COMPLETED
    d, o = {}, {"EX1": {}, "EX0": {}, "DONE": {}}
    for x, c in product(B, B):
        k = (x, c)
        d[("INIT", k)] = "A"
        d[("END", k)] = "END"
        for s in ("A", "B"):
            d[(s, k)] = "END" if c else ("B" if x else "A")
        o["EX1"][("INIT", k)] = o["EX0"][("INIT", k)] = 0
        for s, (e1, e0) in (("A", (1, 0) if x else (1, 1)), ("B", (1, 1) if x else (0, 1))):
            o["EX1"][(s, k)] = None if c else e1        # COMPLETED freezes the datapath -> don't care
            o["EX0"][(s, k)] = None if c else e0
        o["EX1"][("END", k)] = o["EX0"][("END", k)] = None
        for s in states:
            o["DONE"][(s, k)] = int(s == "END")
    return states, inputs, d, o


MEALY_ENC = {"INIT": (0, 0), "A": (0, 1), "B": (1, 1), "END": (1, 0)}
MEALY_FORM = "POS"


# ------------------------------------------------------------------ Booth multiplier controller, Moore
# (separate states for add / subtract and for shift: S00, S11 shift, S01 add, S10 subtract)
def moore():
    states = ["INIT", "S00", "S01", "S10", "S11", "END"]
    inputs = ["X", "CS", "C"]     # X = SHIFT_IN = multiplier bit 1, CS = CURRENT_SHIFT (bit 0 being loaded), C = COMPLETED
    d = {}
    for x, cs, c in product(B, B, B):
        k = (x, cs, c)
        d[("INIT", k)] = None if c else ("S10" if cs else "S00")   # the counter is cleared whenever INIT is entered
        d[("END", k)] = "END"
        if c:
            for s in ("S00", "S01", "S10", "S11"):
                d[(s, k)] = "END"
        else:
            d[("S00", k)] = "S10" if x else "S00"
            d[("S11", k)] = "S11" if x else "S01"
            d[("S01", k)] = "S00"
            d[("S10", k)] = "S11"
    ex = {"INIT": (0, 0), "S00": (1, 1), "S01": (0, 1), "S10": (1, 0), "S11": (1, 1), "END": (None, None)}
    o = {"EX1": {}, "EX0": {}, "DONE": {}, "INIT": {}}
    for s in states:
        for k in product(B, B, B):
            o["EX1"][(s, k)], o["EX0"][(s, k)] = ex[s]
            o["DONE"][(s, k)] = int(s == "END")
            o["INIT"][(s, k)] = int(s == "INIT")
    return states, inputs, d, o


MOORE_ENC = {"INIT": (0, 0, 0), "S00": (0, 1, 1), "S01": (0, 0, 1), "S10": (1, 1, 1), "S11": (1, 0, 1), "END": (1, 0, 0)}
MOORE_FORM = "SOP"


# ------------------------------------------------------------------ vending machine balance FSM and change serializer
BILL_VALUE = {(0, 1): 1, (1, 0): 3, (1, 1): 5}


def vending():
    states = ["b0", "b1", "b2", "b3"]            # balance 0..3
    d, o = {}, {"CH1": {}, "CH0": {}, "RF1": {}, "RF0": {}}
    for i, s in enumerate(states):
        for bill in product(B, B):
            if bill == (0, 0):
                nxt, ch, rf = 0, 0, i
            else:
                t = i + BILL_VALUE[bill]
                nxt, ch, rf = (t, 0, 0) if t < 4 else ((0, 1, t - 4) if t < 8 else (0, 2, 0))
            d[(s, bill)] = states[nxt]
            o["CH1"][(s, bill)] = int(ch == 2)
            o["CH0"][(s, bill)] = None if ch == 2 else int(ch == 1)   # 1X = two items
            o["RF1"][(s, bill)], o["RF0"][(s, bill)] = rf >> 1, rf & 1
    return states, ["B1", "B0"], d, o


VENDING_ENC = {"b0": (0, 0), "b1": (0, 1), "b2": (1, 0), "b3": (1, 1)}
VENDING_FORM = "POS"


def serializer():
    states = ["r0", "r1", "r2", "r3"]            # amount still owed
    d, o = {}, {"BO1": {}, "BO0": {}, "BUSY": {}}
    for c3 in B:
        k = (c3,)
        d[("r0", k)], d[("r1", k)], d[("r2", k)] = "r0", "r0", "r1"
        d[("r3", k)] = "r0" if c3 else "r2"
        for s, bo in (("r0", (0, 0)), ("r1", (0, 1)), ("r2", (0, 1)), ("r3", (1, 0) if c3 else (0, 1))):
            o["BO1"][(s, k)], o["BO0"][(s, k)] = bo
            o["BUSY"][(s, k)] = int(s != "r0")
    return states, ["C3"], d, o


SERIALIZER_ENC = {"r0": (0, 0), "r1": (0, 1), "r2": (1, 0), "r3": (1, 1)}
SERIALIZER_FORM = "POS"


# ------------------------------------------------------------------ composite Z1 (101) / Z2 (011) detector
BASE_DETECTOR = {  # the 5-state base machine: state -> {input: (next, Z1, Z2)}; S1 = "..0", S2 = "..1", S3 = "01", S4 = "10"
    "S0": {0: ("S1", 0, 0), 1: ("S2", 0, 0)},
    "S1": {0: ("S1", 0, 0), 1: ("S3", 0, 0)},
    "S2": {0: ("S4", 0, 0), 1: ("S2", 0, 0)},
    "S3": {0: ("S4", 0, 0), 1: ("S2", 0, 1)},
    "S4": {0: ("S1", 0, 0), 1: ("S3", 1, 0)},
}


def composite10():
    """Z2 edges of the original machine enter the Z1-only copy (T*), Z1 edges of the copy return to the original."""
    C = {}
    for s, tr in BASE_DETECTOR.items():
        C[s] = {b: (("T" + n[1:]) if z2 else n, z1, z2) for b, (n, z1, z2) in tr.items()}
        C["T" + s[1:]] = {b: (n if z1 else "T" + n[1:], z1, 0) for b, (n, z1, z2) in tr.items()}
    return C


def minimise(M):
    blocks = {}
    for s in M:
        blocks.setdefault(tuple(M[s][b][1:] for b in B), []).append(s)
    part = list(blocks.values())
    while True:
        idx = {s: i for i, bl in enumerate(part) for s in bl}
        new = []
        for bl in part:
            g = {}
            for s in bl:
                g.setdefault(tuple(idx[M[s][b][0]] for b in B), []).append(s)
            new.extend(g.values())
        if len(new) == len(part):
            return new
        part = new


def detector8():
    C = composite10()
    part = minimise(C)
    rep = {s: "/".join(bl) for bl in part for s in bl}
    M = {}
    for bl in part:
        s = bl[0]
        M[rep[s]] = {b: (rep[C[s][b][0]], C[s][b][1], C[s][b][2]) for b in B}
    return M


def detector():
    M = detector8()
    states = list(M)
    d = {(s, (b,)): M[s][b][0] for s in states for b in B}
    o = {"Z1": {(s, (b,)): M[s][b][1] for s in states for b in B},
         "Z2": {(s, (b,)): M[s][b][2] for s in states for b in B}}
    return states, ["X"], d, o


DETECTOR_ENC = {"S0": (0, 0, 0), "T0/T1": (1, 1, 1), "S1": (0, 1, 1), "S2": (0, 0, 1), "T2/T3": (1, 0, 0),
                "S3": (1, 0, 1), "S4": (0, 1, 0), "T4": (1, 1, 0)}


# ------------------------------------------------------------------ chosen implementations
def chosen():
    """name -> (fsm tuple, encoding, flip-flop type, form, variable names, synth result)"""
    out = {}
    specs = {
        "MealyController": (mealy(), MEALY_ENC, "SR", MEALY_FORM, ["Q1", "Q0", "X", "C"]),
        "MooreController": (moore(), MOORE_ENC, "SR", MOORE_FORM, ["Q2", "Q1", "Q0", "X", "CS", "C"]),
        "VendingFSM": (vending(), VENDING_ENC, "D", VENDING_FORM, ["Q1", "Q0", "B1", "B0"]),
        "ChangeSerializer": (serializer(), SERIALIZER_ENC, "D", SERIALIZER_FORM, ["Q1", "Q0", "C3"]),
        "SRCompositeDetector": (detector(), DETECTOR_ENC, "SR", "POS", ["Q2", "Q1", "Q0", "X"]),
        "JKCompositeDetector": (detector(), DETECTOR_ENC, "JK", "POS", ["Q2", "Q1", "Q0", "X"]),
    }
    for name, (fsm, enc, ff, form, names) in specs.items():
        states, inputs, d, o = fsm
        out[name] = (fsm, enc, ff, form, names, synth(states, inputs, d, o, enc, ff, form, names=names))
    return out
