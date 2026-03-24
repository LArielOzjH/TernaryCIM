# sim/Makefile — VCS simulation flow for the Ternary CIM Block
#
# Usage (run from any directory):
#   make              → full flow: gen + compile + sim + verify
#   make gen          → generate test vectors (Python)
#   make compile      → compile RTL with VCS
#   make sim          → run simulation (generates tests/sim_output.hex)
#   make verify       → compare sim output vs golden (Python)
#   make clean        → remove build artifacts (preserves test vectors)
#   make realclean    → remove everything including tests/
#
# Optional waveform flags:
#   make sim VCD=1    → dump VCD waveform (tb_CimBlock.vcd)
#   make sim FSDB=1   → dump FSDB waveform (tb_CimBlock.fsdb, needs Verdi)

VCS    ?= vcs
PYTHON ?= python3

# Absolute directory paths
SIM_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
HW_DIR  := $(SIM_DIR)/../hw

# Test vector directory (relative paths in testbench are relative to CWD at sim time)
TEST_DIR := $(SIM_DIR)/tests

# ── VCS flags ──────────────────────────────────────────────────────────────
VCSFLAGS := \
    -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/1ps \
    -debug_access+all

# Optional waveform defines
ifdef VCD
VCSFLAGS  += +define+VCD
endif
ifdef FSDB
VCSFLAGS  += +define+FSDB
endif

# ── RTL source list ────────────────────────────────────────────────────────
# Order: leaf cells → SRAM primitives → compute modules → top → testbench
SRCS := \
    $(HW_DIR)/S8T1.v \
    $(HW_DIR)/WD7T.v \
    $(HW_DIR)/RA6T.v \
    $(HW_DIR)/ClockGate.v \
    $(HW_DIR)/CimDecoder.v \
    $(HW_DIR)/CimDecoderBuffer.v \
    $(HW_DIR)/CimRow.sv \
    $(HW_DIR)/CellArray.sv \
    $(HW_DIR)/ZpSplitter.sv \
    $(HW_DIR)/LutBuilder.sv \
    $(HW_DIR)/LutLookup.sv \
    $(HW_DIR)/WeightPopcount.sv \
    $(HW_DIR)/DualAdderTree.sv \
    $(HW_DIR)/ZpCompensate.sv \
    $(HW_DIR)/OutReg.sv \
    $(HW_DIR)/CimMacro.sv \
    $(HW_DIR)/CimBlock.sv \
    $(SIM_DIR)/sim_cells.v \
    $(SIM_DIR)/tb_CimBlock.sv

SIMV    := $(SIM_DIR)/simv
SIM_OUT := $(TEST_DIR)/sim_output.hex

# ── Targets ────────────────────────────────────────────────────────────────
.PHONY: all gen compile sim verify clean realclean

all: gen compile sim verify

# 1. Generate test vectors
gen: $(TEST_DIR)/weight_mem.hex

$(TEST_DIR)/weight_mem.hex:
	@echo ">>> Generating test vectors..."
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors.py

# 2. Compile RTL
compile: $(SIMV)

$(SIMV): $(SRCS)
	@echo ">>> Compiling RTL with VCS..."
	cd $(SIM_DIR) && $(VCS) $(VCSFLAGS) $(SRCS) -o simv 2>&1 | tee compile.log
	@grep -E "^(Error|Warning)" $(SIM_DIR)/compile.log | head -20 || true
	@echo ">>> Compile log: $(SIM_DIR)/compile.log"

# 3. Run simulation
sim: $(TEST_DIR)/weight_mem.hex $(SIMV)
	@echo ">>> Running simulation..."
	cd $(SIM_DIR) && ./simv 2>&1 | tee sim.log
	@echo ">>> Simulation log: $(SIM_DIR)/sim.log"

# 4. Verify results
verify: $(SIM_OUT)
	@echo ">>> Verifying simulation output..."
	cd $(SIM_DIR) && $(PYTHON) verify_sim_output.py

$(SIM_OUT):
	@echo ">>> sim_output.hex not found; running simulation first..."
	@$(MAKE) sim

# ── Waveform helpers ───────────────────────────────────────────────────────
.PHONY: sim_vcd sim_fsdb
sim_vcd:
	@$(MAKE) sim VCD=1

sim_fsdb:
	@$(MAKE) sim FSDB=1

# ── Cleanup ────────────────────────────────────────────────────────────────
clean:
	rm -rf $(SIMV) $(SIMV).daidir $(SIM_DIR)/csrc \
	       $(SIM_DIR)/compile.log $(SIM_DIR)/sim.log \
	       $(SIM_DIR)/ucli.key \
	       $(SIM_DIR)/tb_CimBlock.vcd \
	       $(SIM_DIR)/tb_CimBlock.fsdb \
	       $(SIM_OUT)

realclean: clean
	rm -rf $(TEST_DIR)
