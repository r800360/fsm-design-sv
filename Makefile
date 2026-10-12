# Gate-level state machines: generation, lint, simulation, formal verification, mutation testing, synthesis.
# Toolchain: Python 3, Icarus Verilog, Verilator, Yosys + yosys-abc (exact versions in scripts/install-tools.sh).

FF    := rtl/ff_primitives.sv
BOOTH := $(FF) rtl/booth_ctrl_mealy.sv rtl/booth_ctrl_moore.sv rtl/booth_skip_mult.sv
DET   := $(FF) rtl/seq_detector_sr.sv rtl/seq_detector_jk.sv
VEND  := rtl/vending_fsm.sv rtl/change_serializer.sv rtl/vending_machine.sv
RUN   := bash scripts/run_sim.sh

.PHONY: all ci full summary rtl check-rtl lint sim sim-icarus sim-verilator exhaustive formal formal-quick synth \
        mutants explore clean

all: check-rtl lint sim

# CI entry points (.github/workflows): `make ci` runs on every push, `make full` adds the long runs
ci: check-rtl lint sim mutants formal-quick synth explore summary
full: check-rtl lint sim mutants synth explore exhaustive formal summary

summary:
	@bash scripts/summary.sh > /dev/null && echo "wrote build/SUMMARY.md"

# regenerate the gate-level state machines from scripts/fsms.py
rtl:
	python3 scripts/emit_sv.py

# fail if the committed RTL differs from what the generator produces
check-rtl:
	@mkdir -p build/regen && cp rtl/*.sv build/regen/ && python3 scripts/emit_sv.py > /dev/null && \
	  for f in rtl/*.sv; do cmp -s $$f build/regen/$$(basename $$f) || { echo "$$f is out of date"; exit 1; }; done; \
	  echo "generated RTL is up to date"

lint:
	verilator --lint-only -Wall --top-module booth_skip_mult $(BOOTH)
	verilator --lint-only -Wall --top-module booth_skip_mult -GMOORE="1'b1" $(BOOTH)
	verilator --lint-only -Wall --top-module seq_detector_sr $(DET)
	verilator --lint-only -Wall --top-module seq_detector_jk $(DET)
	verilator --lint-only -Wall --top-module sr_ff_from_pt $(FF)
	verilator --lint-only -Wall --top-module d_ff_from_sr $(FF)
	verilator --lint-only -Wall --top-module vending_machine $(VEND)
	verilator --lint-only -Wall --top-module vending_machine -GTILL="1'b0" $(VEND)
	verilator --lint-only -Wall --top-module vending_machine -GLOCKS="1'b1" $(VEND)

sim: sim-icarus sim-verilator

define TESTS
	$(RUN) $(1) ff           tb/tb_ff.sv       ""        $(FF)
	$(RUN) $(1) booth_mealy  tb/tb_booth.sv    ""        $(BOOTH)
	$(RUN) $(1) booth_moore  tb/tb_booth.sv    "MOORE"   $(BOOTH)
	$(RUN) $(1) booth_mealy6 tb/tb_booth.sv    "N=6"     $(BOOTH)
	$(RUN) $(1) booth_moore6 tb/tb_booth.sv    "MOORE N=6" $(BOOTH)
	$(RUN) $(1) detector     tb/tb_detector.sv ""        $(DET)
	$(RUN) $(1) vending2     tb/tb_vending.sv  "CFG=2"   $(VEND)
	$(RUN) $(1) vending3     tb/tb_vending.sv  "CFG=3"   $(VEND)
	$(RUN) $(1) vending4     tb/tb_vending.sv  "CFG=4"   $(VEND)
	$(RUN) $(1) vending5     tb/tb_vending.sv  "CFG=5"   $(VEND)
endef

sim-icarus:
	$(call TESTS,icarus)

sim-verilator:
	$(call TESTS,verilator)

# all 2^26 operand pairs of the 13-bit multiplier, both controllers (Verilator, several minutes each)
exhaustive:
	$(RUN) verilator booth_mealy_exh tb/tb_booth.sv "EXHAUSTIVE"       $(BOOTH)
	$(RUN) verilator booth_moore_exh tb/tb_booth.sv "EXHAUSTIVE MOORE" $(BOOTH)

formal:
	bash formal/run_formal.sh

# the formal campaign without Booth N = 6 and the 31-bill till (about 2 minutes)
formal-quick:
	QUICK=1 bash formal/run_formal.sh

synth:
	bash scripts/synth.sh

# deliberately broken copies of the RTL: every one must make a testbench fail
mutants:
	bash scripts/mutation_test.sh

# re-run the design-space exploration that justifies the encodings and the till (logs in build/explore)
explore:
	@mkdir -p build/explore
	for s in explore_booth_controllers explore_moore explore_detector explore_detector_pick explore_vending \
	         vending_bounds; do echo "== $$s"; python3 scripts/$$s.py > build/explore/$$s.log || exit 1; done
	tail -n 4 build/explore/*.log > build/explore/summary.txt

clean:
	rm -rf build obj_dir scripts/__pycache__
