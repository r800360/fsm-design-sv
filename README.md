# Gate-level state-machine design in SystemVerilog

Four sequential designs taken from a symbolic state machine to gate-level SystemVerilog:
* a Booth multiplier whose controller skips the add/subtract cycle when it isn't needed;
* a composite sequence detector;
* a vending machine that pays change from its own till;
* flip-flop conversions.

The flow is automated. The state machines are written once in Python. Scripts then minimize the states, search
**every** state encoding, and compute exact minimum two-level logic for SR, JK or D flip-flops. The gate-level RTL is
*generated* from the result, so the RTL and the design-space search can never disagree.

Every design is verified three ways:
* self-checking testbenches against independent reference models;
* **unbounded formal proofs** (ABC PDR/IC3), with negative controls that must fail;
* **mutation testing** of the testbenches: 21 deliberately broken designs, all detected.

## Designs

| Design | What it shows | Result |
|---|---|---|
| `booth_skip_mult` | radix-2 Booth multiplier; the controller skips the add/subtract cycle for Booth pairs 00 / 11 | latency N + k + 2 (k = non-zero Booth digits): 15–28 cycles for N = 13, 21.5 on average over all multipliers, against a fixed 27 without skipping |
| `booth_ctrl_mealy` / `booth_ctrl_moore` | 4-state Mealy and 6-state Moore controllers, SR flip-flops | 6 + 5 and 10 + 6 two-input gates (next state + outputs), best of all encodings |
| `seq_detector_sr` / `_jk` | detects 101 always and 011 until it fires, then only 101 until that fires | 10-state product machine minimized to 8 states; 9 (SR) / 7 (JK) gates of next-state logic |
| `vending_machine` | price 4, bills 1/3/5, change paid bill by bill from a counted till; optional slot locks | smallest safe till (30 1-bills) and lock rules **proven** sufficient and necessary |
| `ff_primitives` | SR → D, JK → "PT", PT → SR conversions | 0, 1 and 1 gates |

## Design flow

```
scripts/fsms.py                symbolic FSMs: states, next-state and output tables with don't-cares, chosen encodings
   │
   ├─ explore_*.py             state minimization (partition refinement), encoding search, prioritized adjacency
   │   └─ fsm_synth.py         SR / JK / D excitation tables → K-maps
   │       └─ logicmin.py      exact two-level minimization (SOP or POS) with don't-cares, 2-input gate cost
   │
   └─ emit_sv.py  ──────────►  rtl/booth_ctrl_*.sv, seq_detector_*.sv, vending_fsm.sv, change_serializer.sv
                               ("make check-rtl" fails if the committed RTL differs from the generator)
```

**Cost model.** The unit is the two-input AND/OR gate. Q and Q' are both available, so complemented state bits cost
nothing. A term with k literals costs k − 1 gates, and m terms cost another m − 1. Terms shared between functions are
counted once in the "shared" figures.

## The designs in more detail

### Booth multiplier with a skipping controller

The datapath has four registers:
* A (N + 1 bits, one guard bit);
* Q (the multiplier);
* M (the multiplicand);
* a shift counter.

The controller's `ex_op` selects one of four operations: load, A += M, A −= M, or an arithmetic shift of {A, Q}. After
N shifts the datapath freezes and `done` rises. The guard bit makes the product exact for every pair, including
(−2^(N−1))².

* **Mealy controller** (INIT, A = "last bit 0", B = "last bit 1", END). The four window states of the textbook
  machine merge into A and B. The same Booth pair that caused an add or subtract then causes the shift on the next
  cycle. `explore_booth_controllers.py` synthesizes all six encodings with INIT = 00 (the power-on state). The chosen
  one is minimum-bit-change and costs 6 + 5 gates in POS:
  `S1 = Q0(X + C)`, `R1 = Q0X'C'`, `S0 = Q1'Q0'`, `R0 = Q0C`.
* **Moore controller** (INIT, S00, S01, S10, S11, END). It has separate states for add/subtract and for shift.
  `explore_moore.py` synthesizes all 2520 encodings with INIT = 000. The optimum costs 10 + 6 gates, and its core
  states still form a Gray cycle. Its INIT state must choose S00 or S10 on the same edge that loads Q, so it looks
  at bit 0 of the value being loaded (`q_d[0]`), not at Q.

### Composite sequence detector

The base machine detects 101 on z1 and 011 on z2, both overlapping. In the composite machine:
* once z2 fires, only z1 is reported;
* once z1 then fires, both are reported again.

Construction and encoding:
* **Product machine:** two copies of the 5-state base machine, 10 states.
* **Minimization:** partition refinement merges two pairs of states, leaving **8 states**.
* **Encoding:** `explore_detector.py` scores all 840 encodings (8! up to bit permutation and complement) by
  prioritized adjacency and synthesizes each one for both SR and JK flip-flops.
* **Result:** the chosen encoding needs **9 gates with SR** and **7 with JK** for the next state, plus 5 for the
  outputs. The heuristic's favorite needs 16. In this encoding Q1 is the complement of the last input bit, so
  `S1 = X'` and `R1 = X` are free.

JK needs fewer gates because its excitation table has a don't-care on *every* transition. That removes the Q0' and
Q0 factors SR needs in `S0` and `R0`.

### Vending machine

The balance FSM is a Mealy machine with D flip-flops, generated from its table: price 4, balance 0–3. Balances of
4–7 dispense one item plus change. 3 + 5 = 8 dispenses two items. The parameterized top adds:
* **Stock** (15 items) and a single clock with *enables*, not gated clocks. A bill at a closed slot is ignored: the
  FSM is frozen, and its Mealy outputs are masked.
* **Till** (`TILL = 1`): bill counters and a change serializer that pays one bill per clock. It pays a 3-bill when
  3 is owed and one is in the till, and 1-bills otherwise. All slots close while a payout is in progress.
* **Locks** (`LOCKS = 1`): the till may start empty. A slot closes exactly when accepting that bill could leave change
  that cannot be paid:
  `lock5 = [n1 < 1, n1 < 2, n1 < 3 ∧ n3 = 0, last item][balance]` and `lock3 = (balance = 3) ∧ (n1 < 2)`.
  The locks are a function of registered state, so no lock flip-flops are needed.

`scripts/vending_bounds.py` explores every customer behavior (breadth-first over all reachable states):
* **Fixed till:** at least 30 1-bills (and no 3- or 5-bills) are needed. With 29, a specific customer sequence makes
  the machine shortchange. The counters need 7 / 5 / 4 bits (maxima 90 / 30 / 15).
* **Zero-deposit locks:** 2936 reachable states. No state shortchanges, so the locks are sufficient. In every one of
  the 201 lock5 and 63 lock3 cases, accepting the bill would shortchange a customer or over-dispense, so the locks
  are necessary.

The formal proofs below confirm on the RTL itself that these tills are safe, and that 29 bills or narrower counters
are not.

## Verification

### Simulation: `make sim` (Icarus Verilog and Verilator)

Each testbench reports PASS/FAIL per check and a summary. Categories are FUNC (specified behavior), RANDOM
(protocol-following random stimulus) and ROBUST (inputs outside the protocol: closed slots, mid-operation resets).

| Testbench | Reference | Stimulus |
|---|---|---|
| `tb_booth.sv` | `$signed(a) * $signed(b)`, and Booth's table for the per-cycle operation | corner operands (0, ±1, max, min, all-digits-non-zero), 3 000 random pairs (300 000 with Verilator), hold after done, operands changing after load, clr mid-operation; exact `done` cycle on every product. Also N = 6. `make exhaustive`: all 2²⁶ pairs, both controllers |
| `tb_detector.sv` | shift-register model of the specification | all 8 190 sequences of length 1–12, a 100 000-bit random stream (10⁶ with Verilator), resets at random points, power-on without reset; SR and JK side by side |
| `tb_vending.sv` | cycle model written from the price/change arithmetic | all 16 (balance, bill) cells, sell-out, last-item lock, change sequences, bills during payout, till draining, every lock case, 400 random customers (20 000 with Verilator), 20 000 cycles of random bills and resets. Checks every output every cycle (including the till counts, the stock and the change still due), plus the till and stock invariants. Four configurations |
| `tb_ff.sv` | characteristic equations | 20 000 random cycles; the testbench confirms that every (P, T, Q) combination occurred |

### Formal: `make formal` (Yosys + ABC PDR)

Each harness in `formal/` uses immediate assertions over the design and a small specification model. Every run
states its expected outcome, and the script fails if any outcome differs.

| Proof | Result |
|---|---|
| SR and JK detectors ≡ specification, for every input and reset sequence; S = R = 1 never occurs | proved (unbounded) |
| Booth: `done` exactly N + k + 2 cycles after clr, product = a × b, no operation after completion; both controllers, every operand pair and clr pattern | proved (unbounded) for N = 4 (8 s) and N = 6 (≈ 17 min per controller) |
| Vending, empty till with locks | proved (29 s) |
| Vending, 30 1-bills and 7/5/4-bit counters | proved (49 s) |
| Vending, till of 31 of each bill | proved (≈ 10 min) |
| *Negative controls:* 29 1-bills; a 6-bit 1-bill counter; a 4-bit 3-bill counter; no locks with an empty till; four RTL mutants (a detector gate, the accumulator's sign extension, the Moore controller's lookahead bit, the 3-slot lock) | every one fails with a counterexample (2 to 60 cycles deep) |

The vending properties are:
* no payout takes a bill the till does not hold;
* no counter wraps around;
* no more items are dispensed than are in stock.

Any bill may be offered in any cycle, and reset may be asserted at any time.

**Making the vending proofs converge.** Stated alone, these safety properties are not inductive: PDR ran for 30
minutes per configuration without converging. The harness therefore also asserts five invariants, each derived by hand
from the design, and these make the property 1-inductive:
* **value conservation:** till value − initial value = 4 × items sold + balance + change still due;
* **the deposit is in the till:** the customer's deposit is in the till in the bills it must be made of;
* **the change due is payable** with the serializer's policy;
* **fixed till:** it always holds at least 2 × stock + need(balance, change due) 1-bills, because the worst customer
  takes two 1-bills per item;
* **5-bill counter:** it never drops below its initial value.

With them, the three configurations prove in 29 s, 49 s and about 10 minutes. The negative controls run without the
invariants, so they fail on a real shortchange, overflow or over-dispense, not on an invariant.

> Yosys ≥ 0.30 turns `assert` into `$check` cells. Without `chformal -lower`, the exported model contains no
> properties, and every "proof" passes vacuously. `formal/pdr.sh` therefore refuses to run on a model with zero
> assertions.

### Mutation testing: `make mutants`

`scripts/mutation_test.sh` builds 21 mutants and runs the relevant testbench on each one. Every mutant must make the
testbench fail. The mutants include:
* a wrong gate in each generated controller and detector;
* a missing sign extension;
* no freeze after completion;
* the lock rules weakened or removed;
* bills counted at closed slots;
* the serializer's 3-bill choice.

All 21 are detected.

### Synthesis: `make synth`

Yosys `synth -flatten; abc -g gates` maps each block to a generic library of two-input gates. The counts below include
the synchronous resets, the SR/JK flip-flops built from D flip-flops and the enables, which the hand cost model
leaves out:

| Block | Flip-flops | Gates | Inverters |
|---|---:|---:|---:|
| booth_ctrl_mealy | 2 | 13 | 0 |
| booth_ctrl_moore | 3 | 17 | 0 |
| booth_skip_mult, Mealy, N = 13 | 46 | 227 | 2 |
| booth_skip_mult, Moore, N = 13 | 47 | 236 | 1 |
| seq_detector_sr | 3 | 14 | 0 |
| seq_detector_jk | 3 | 15 | 0 |
| vending_fsm | 2 | 27 | 0 |
| change_serializer | 2 | 12 | 1 |
| vending_machine, no till | 6 | 49 | 2 |
| vending_machine, till of 31 each | 32 | 159 | 4 |
| vending_machine, empty till with locks | 32 | 178 | 2 |
| vending_machine, 30 1-bills, 7/5/4-bit counters | 24 | 128 | 3 |

## Repository layout

```
rtl/        ff_primitives.sv, booth_skip_mult.sv, vending_machine.sv (hand-written)
            booth_ctrl_{mealy,moore}.sv, seq_detector_{sr,jk}.sv, vending_fsm.sv, change_serializer.sv (generated)
tb/         self-checking testbenches, tb_common.svh (checks, summary, portable PRNG)
formal/     *_formal.sv harnesses, pdr.sh (one proof), run_formal.sh (campaign with expected outcomes)
scripts/    fsms.py, logicmin.py, fsm_synth.py, explore_*.py, vending_bounds.py, emit_sv.py,
            run_sim.sh, synth.sh, mutation_test.sh
```

## Running

```bash
make                 # check the generated RTL, lint, and all simulations (Icarus and Verilator)
make exhaustive      # every 13 x 13-bit product with both controllers (Verilator)
make formal          # PDR proofs and negative controls
make mutants         # testbench mutation score
make synth           # gate counts
make explore         # re-run the encoding searches and the till analysis (logs in build/explore)
make rtl             # regenerate the gate-level RTL from scripts/fsms.py
```

Requirements: Python 3, Verilator 5, Icarus Verilog 12, Yosys ≥ 0.30 with yosys-abc. Tested with Verilator 5.032,
Icarus 12.0 and Yosys 0.52.

## Background

These designs started as university digital-design lab assignments, built as schematics. This repository is a
from-scratch re-implementation in SystemVerilog, written after an analysis of those first versions. Its focus is what
the schematics lacked: exhaustive and formal evidence that each design is correct and minimal.
