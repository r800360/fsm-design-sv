# Verification

Every check here runs in CI on the pinned toolchain. `make ci` runs on every push; `make full` adds the exhaustive
products and the slow proofs. Each run writes its logs and reports to `build/`, and `build/SUMMARY.md` collects them.

## Simulation (`make sim`)

The testbenches are self-checking. Each prints one `PASS`/`FAIL` line per check and ends with a summary, and
`scripts/run_sim.sh` fails unless that summary reads `RESULT: PASS`. The check categories are:
* **FUNC**: specified behavior.
* **RANDOM**: random stimulus that follows the protocol.
* **ROBUST**: inputs outside the protocol, such as bills at closed slots or resets mid-operation.

Random stimulus comes from a fixed-seed xorshift generator in `tb/tb_common.svh`, so both simulators see identical
sequences on every run.

| Testbench | Reference model | Stimulus |
|---|---|---|
| `tb_booth.sv` | `$signed(a) * $signed(b)`, and Booth's table for the operation in every cycle | corner operands (0, ±1, max, min, all digits non-zero), 3 000 random pairs (300 000 in Verilator), hold after `done`, operands changing after the load, `clr` mid-operation. Every product's `done` cycle is checked exactly. Runs at N = 13 and N = 6 |
| `tb_detector.sv` | shift-register model of the specification | all 8 190 sequences of length 1–12, a 10⁵-bit random stream (10⁶ in Verilator), resets at random points, power-on without reset. SR and JK run side by side |
| `tb_vending.sv` | cycle model written from the price and change arithmetic | all 16 (balance, bill) cells, sell-out, last-item lock, change sequences, bills offered during payout, till draining, every lock case, 400 random customers (20 000 in Verilator), 20 000 cycles of random bills and resets. Every output is compared every cycle, plus the till and stock invariants. Runs in four configurations |
| `tb_ff.sv` | characteristic equations | 20 000 random cycles; checks that every (P, T, Q) combination occurred |

`make exhaustive` multiplies **all 2²⁶ operand pairs** at N = 13 with both controllers in Verilator, checking every
product and its exact latency.

## Formal (`make formal`, `make formal-quick`)

Each harness in `formal/` instantiates the design next to a small specification model and states properties as
immediate assertions. `formal/run_formal.sh` runs every proof with a stated expected outcome, and exits non-zero if
any outcome differs.

| Proof | Result |
|---|---|
| SR and JK detectors equal the specification, for every input and reset sequence; S = R = 1 never occurs | proved |
| Booth: `done` exactly N + k + 2 cycles after `clr`, product = a × b, no operation after completion. Both controllers, every operand pair and `clr` pattern | proved for N = 4 (8 s) and N = 6 (13–17 min per controller) |
| Vending, empty till with locks | proved (29 s) |
| Vending, 30 one-unit bills with 7/5/4-bit counters | proved (49 s) |
| Vending, 31 bills of each kind | proved (≈ 10 min) |
| **Negative controls** (each must fail): a 29-bill till, a 6-bit 1-bill counter, a 4-bit 3-bill counter, no locks with an empty till, and four broken RTL copies | all fail with counterexamples 2–60 cycles deep |

All proofs are unbounded. The vending properties are:
* no payout takes a bill the till does not hold;
* no counter wraps around;
* no more items are dispensed than are in stock.

They hold for any bill in any cycle and any reset pattern.

**Strengthening.** Stated alone, the vending properties are true but not inductive, and PDR did not converge within 30
minutes. `formal/vending_formal.sv` therefore also asserts five invariants, each derived by hand from the design. They
are true in every reachable state, and together they make the property 1-inductive:

1. **Value conservation:** till value − initial value = 4 × items sold + balance + change due.
2. **The deposit is in the till,** in the bills it must consist of.
3. **The change due is payable** with the serializer's policy.
4. **Fixed till:** at least 2 × stock + need(balance, change due) one-unit bills, because the worst customer takes two
   per item.
5. **The 5-bill counter** never drops below its initial value.

The negative controls run without these invariants. So each one fails on a real shortchange, overflow or
over-dispense, never on an invariant.

`make formal-quick` (used by CI on every push) skips Booth N = 6 and the 31-bill till.

## Mutation testing (`make mutants`)

`scripts/mutation_test.sh` applies 21 single-point bugs with `sed`, then runs the relevant testbench in Icarus. Every
mutant must make the testbench fail. The mutants include:
* a wrong gate in each generated controller and detector;
* a missing sign extension;
* no freeze after completion;
* weakened or missing lock rules;
* bills counted at closed slots;
* the serializer's 3-bill choice.

All 21 are caught. The summary lists the first failing check for each mutant.

## Tools and how they are run

| Tool (version) | Used for | Command (from the scripts) |
|---|---|---|
| Icarus Verilog 12.0 | event-driven simulation | `iverilog -g2012 -I tb -D<defines> -o build/<test>.vvp <tb> <rtl>`, then `vvp -n build/<test>.vvp` |
| Verilator 5.032 | lint, compiled simulation | `verilator --lint-only -Wall --top-module <top> <rtl>`; `verilator --binary --timing -O2 -Itb -D<defines> --top-module <tb> -Mdir build/obj_<test> <tb> <rtl>` |
| Yosys 0.52 | synthesis | `synth -top <top> -flatten; abc -g gates; opt_clean; stat; write_verilog` |
| Yosys + ABC (yosys-abc) | unbounded proofs | `formal/pdr.sh`: Yosys writes an AIGER model, then `yosys-abc -c "read_aiger m.aig; fold; strash; pdr"` |
| Python 3 | FSM models, minimization, generator, bounds | `python3 scripts/<script>.py` |

`scripts/run_sim.sh` wraps both simulators: one command per testbench, a log in `build/<test>.<sim>.log`, and a
non-zero exit unless the log ends in `RESULT: PASS`.

**The formal flow (`formal/pdr.sh`).** The Yosys script is:

```
read_verilog -sv -formal -DFORMAL <rtl> <harness>; chparam <parameters> <harness>
prep -top <harness>; flatten; async2sync
chformal -lower                  # turn $check cells into $assert / $assume (see the pitfall below)
chformal -assume -early          # assumptions constrain the same cycle
chformal -cover -remove
opt_clean; setundef -anyseq      # anything undriven becomes a free input
opt -keepdc -fast; techmap; opt -fast; dffunmap; abc -g AND -fast; opt_clean
write_aiger -I -B -zinit m.aig   # bad-state properties; uninitialized registers become free inputs
```

ABC's `pdr` (property-directed reachability, also called IC3) either proves every bad state unreachable, which is a
proof for all time, or returns a counterexample. Before it runs, the script reads the number of properties from the
AIGER header and refuses a model that has none.

**Pitfalls worth knowing:**
* **Vacuous proofs.** Yosys 0.52 elaborates `assert` into `$check` cells. Without `chformal -lower`, the model has no
  properties, and every proof "passes".
* **Assertion timing.** Clocked concurrent assertions are sampled one cycle late in this flow. The harnesses use
  immediate assertions over explicitly registered previous-cycle values instead.
* **Icarus 12 limits.** It rejects or crashes on string ternaries, `return` inside tasks, and `inside`. The testbenches
  avoid all three, so both simulators run the same code.

## CI

| Workflow | Trigger | Runs |
|---|---|---|
| CI (`.github/workflows/ci.yml`) | every push to `main`, pull requests | `check-rtl`, `lint`, `sim`, `mutants`, `formal-quick`, `synth`, `explore` |
| Full verification (`full.yml`) | manual, or a `v*` tag | the CI steps, plus `exhaustive` and the full `formal` campaign; a tag also publishes a release |

Both workflows run in the pinned `ubuntu:26.04` image and install the toolchain with `scripts/install-tools.sh`, the
same script the `Dockerfile` uses. The job summary shows `build/SUMMARY.md`, and `build/` is uploaded as an artifact.
Verilator object files and compiled Icarus images are left out of the artifact, since they are rebuilt on every run.
