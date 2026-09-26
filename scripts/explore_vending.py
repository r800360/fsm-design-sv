"""explore_vending.py - K-maps and minimal SOP / POS logic of the vending-machine FSM and the change serializer."""
import os
import sys
from itertools import product
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fsm_synth import synth, report  # noqa: E402

from fsms import vending, serializer, VENDING_ENC, SERIALIZER_ENC  # noqa: E402

ST, _, d, o = vending()
enc = VENDING_ENC
print("vending FSM transition table (balance, bill) -> next / items / change")
for s in ST:
    print("  ", s, "  ".join(f"{''.join(map(str, b))}->{d[(s, b)]}/{o['CH1'][(s, b)]}{o['CH0'][(s, b)] if o['CH0'][(s, b)] is not None else 'X'}/{o['RF1'][(s, b)]}{o['RF0'][(s, b)]}"
                            for b in product((0, 1), repeat=2)))
for form in ("SOP", "POS"):
    r = synth(ST, ["B1", "B0"], d, o, enc, "D", form, names=["Q1", "Q0", "B1", "B0"])
    print(report(r, f"\nvending FSM, D flip-flops, {form}:"))

RS, _, rd, ro = serializer()
renc = SERIALIZER_ENC
for form in ("SOP", "POS"):
    r = synth(RS, ["C3"], rd, ro, renc, "D", form, names=["Q1", "Q0", "C3"])
    print(report(r, f"\nchange serializer, D flip-flops, {form}:"))
