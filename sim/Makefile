# sim/Makefile — VCS simulation flow for the Ternary CIM Block
#
# Usage (run from any directory):
#   make              → full flow: gen + compile + sim + verify
#   make gen          → generate test vectors (Python)
#   make compile      → compile RTL with VCS
#   make sim          → run simulation (generates tests/sim_output.hex)
#   make verify       → compare sim output vs golden (Python)
#   make saif         → compile+run with SAIF capture (generates lut_build.saif, compute.saif)
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

SIMV                 := $(SIM_DIR)/simv
SIMV_SAIF            := $(SIM_DIR)/simv_saif
SIMV_SPARSE          := $(SIM_DIR)/simv_sparse
SIMV_SPARSE_FSDB     := $(SIM_DIR)/simv_sparse_fsdb
SIM_OUT              := $(TEST_DIR)/sim_output.hex
TESTS_SPARSE_DIR     := $(SIM_DIR)/tests_sparse

# Sparsity configuration — override on the command line, e.g.:
#   make fsdb_sparse SPARSE_TAG=h060_f050_s12
# or let gen_test_vectors_sparse.py auto-generate the tag and pass it here.
SPARSE_TAG  ?= h080_f075_s8
SPARSE_H4   ?= 0.80
SPARSE_F0   ?= 0.75
SPARSE_SIGMA?= 8.0
SPARSE_ZP   ?= 0x39
SPARSE_SEED ?= 42
SPARSE_DIR   = $(TESTS_SPARSE_DIR)/$(SPARSE_TAG)

# Verdi PLI library for FSDB generation (set VERDI_HOME to your Verdi installation)
VERDI_HOME ?= /tools/synopsys/verdi/latest
FSDB_PLI    = -P $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab \
               $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a

# Source list with sparse testbench substituted
SRCS_SPARSE := $(filter-out $(SIM_DIR)/tb_CimBlock.sv, $(SRCS)) \
               $(SIM_DIR)/tb_CimBlock_sparse.sv

# Source list for naive baseline (replaces CimMacro+CimBlock with naive variants)
SRCS_NAIVE := $(filter-out $(SIM_DIR)/tb_CimBlock.sv, $(SRCS))
SRCS_NAIVE := $(filter-out $(HW_DIR)/CimMacro.sv,     $(SRCS_NAIVE))
SRCS_NAIVE := $(filter-out $(HW_DIR)/CimBlock.sv,     $(SRCS_NAIVE))
SRCS_NAIVE += $(HW_DIR)/CimMacro_naive.sv \
              $(HW_DIR)/CimBlock_naive.sv \
              $(SIM_DIR)/tb_CimBlock_naive.sv

SIMV_NAIVE_FSDB := $(SIM_DIR)/simv_naive_fsdb

# ── Targets ────────────────────────────────────────────────────────────────
.PHONY: all gen compile sim verify saif gen_sparse gen_sparse_sweep saif_sparse fsdb_sparse fsdb_naive clean realclean

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

# 5. SAIF capture (two time windows: LUT Build + Compute)
saif: $(TEST_DIR)/weight_mem.hex
	@echo ">>> Compiling RTL for SAIF capture (+define+SAIF)..."
	cd $(SIM_DIR) && $(VCS) $(VCSFLAGS) +define+SAIF $(SRCS) -o simv_saif 2>&1 | tee compile_saif.log
	@grep -E "^(Error|Warning)" $(SIM_DIR)/compile_saif.log | head -20 || true
	@echo ">>> Running SAIF simulation..."
	cd $(SIM_DIR) && ./simv_saif 2>&1 | tee saif.log
	@echo ">>> SAIF output: tests/lut_build.saif  tests/compute.saif"

# 6. Sparse test vector generation
#    Usage: make gen_sparse [SPARSE_TAG=h080_f075_s8] [SPARSE_H4=0.80] ...
gen_sparse:
	@mkdir -p $(SPARSE_DIR)
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors_sparse.py \
	    --tag $(SPARSE_TAG) --h4 $(SPARSE_H4) --flag0 $(SPARSE_F0) \
	    --sigma $(SPARSE_SIGMA) --zp $(SPARSE_ZP) --seed $(SPARSE_SEED)
	@echo ">>> Test vectors in: $(SPARSE_DIR)"

# 6b. Sweep: 5 groups × 5 H4 levels = 25 datasets total.
#     Within each group H4 = 0/20/40/60/80 %, F0 = 80 %, weights identical.
#     Across groups the seed differs so weights differ.
#     Tags: h000_f080_1 … h080_f080_5
#     Usage: make gen_sparse_sweep
SWEEP_F0    ?= 0.80
SWEEP_SIGMA ?= 8.0
SWEEP_ZP    ?= 0x39

# Seeds for groups 1-5 (override any of these on the command line if needed)
SWEEP_SEED_1 ?= 42
SWEEP_SEED_2 ?= 43
SWEEP_SEED_3 ?= 44
SWEEP_SEED_4 ?= 45
SWEEP_SEED_5 ?= 46

# Generate one group: $(1)=group index, $(2)=seed
define gen_one_group
	@echo ">>> Group $(1) (seed=$(2)): h000/020/040/060/080_f080_$(1)"
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors_sparse.py \
	    --tag h000_f080_$(1) --h4 0.00 --flag0 $(SWEEP_F0) \
	    --sigma $(SWEEP_SIGMA) --zp $(SWEEP_ZP) --seed $(2)
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors_sparse.py \
	    --tag h020_f080_$(1) --h4 0.20 --flag0 $(SWEEP_F0) \
	    --sigma $(SWEEP_SIGMA) --zp $(SWEEP_ZP) --seed $(2)
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors_sparse.py \
	    --tag h040_f080_$(1) --h4 0.40 --flag0 $(SWEEP_F0) \
	    --sigma $(SWEEP_SIGMA) --zp $(SWEEP_ZP) --seed $(2)
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors_sparse.py \
	    --tag h060_f080_$(1) --h4 0.60 --flag0 $(SWEEP_F0) \
	    --sigma $(SWEEP_SIGMA) --zp $(SWEEP_ZP) --seed $(2)
	cd $(SIM_DIR) && $(PYTHON) gen_test_vectors_sparse.py \
	    --tag h080_f080_$(1) --h4 0.80 --flag0 $(SWEEP_F0) \
	    --sigma $(SWEEP_SIGMA) --zp $(SWEEP_ZP) --seed $(2)
endef

gen_sparse_sweep:
	@echo ">>> Generating 5 groups × 5 H4 levels = 25 datasets..."
	$(call gen_one_group,1,$(SWEEP_SEED_1))
	$(call gen_one_group,2,$(SWEEP_SEED_2))
	$(call gen_one_group,3,$(SWEEP_SEED_3))
	$(call gen_one_group,4,$(SWEEP_SEED_4))
	$(call gen_one_group,5,$(SWEEP_SEED_5))
	@echo ">>> Done. 25 datasets under tests_sparse/h{000,020,040,060,080}_f080_{1..5}"

saif_sparse: $(SPARSE_DIR)/weight_mem_sparse.hex
	@echo ">>> [SPARSE_TAG=$(SPARSE_TAG)] Compiling RTL for sparse SAIF capture..."
	cd $(SIM_DIR) && $(VCS) $(VCSFLAGS) +define+SAIF $(SRCS_SPARSE) \
	    -o simv_sparse 2>&1 | tee compile_sparse.log
	@grep -E "^(Error|Warning)" $(SIM_DIR)/compile_sparse.log | head -20 || true
	@echo ">>> Running sparse SAIF simulation..."
	cd $(SIM_DIR) && ./simv_sparse +sparse_dir=tests_sparse/$(SPARSE_TAG) 2>&1 | tee saif_sparse.log
	@echo ">>> SAIF: $(SPARSE_DIR)/sim_sparse.saif"

# 7. Sparse FSDB capture for PTPX time-based power analysis
#    Usage: make fsdb_sparse [SPARSE_TAG=h080_f075_s8]
#    Requires Verdi PLI — set VERDI_HOME to your Verdi installation if needed.
fsdb_sparse: $(SPARSE_DIR)/weight_mem_sparse.hex
	@echo ">>> [SPARSE_TAG=$(SPARSE_TAG)] Compiling RTL for sparse FSDB capture..."
	cd $(SIM_DIR) && $(VCS) $(VCSFLAGS) +define+FSDB $(FSDB_PLI) $(SRCS_SPARSE) \
	    -o simv_sparse_fsdb 2>&1 | tee compile_sparse_fsdb.log
	@grep -E "^(Error|Warning)" $(SIM_DIR)/compile_sparse_fsdb.log | head -20 || true
	@echo ">>> Running sparse FSDB simulation..."
	cd $(SIM_DIR) && ./simv_sparse_fsdb +sparse_dir=tests_sparse/$(SPARSE_TAG) \
	    2>&1 | tee sim_sparse_fsdb.log
	@echo ">>> FSDB: $(SPARSE_DIR)/tb_CimBlock_sparse.fsdb"
	@echo ">>> Check sim_sparse_fsdb.log for [PTPX] timestamps to fill in -time {}"

# 7b. Compile sparse FSDB binary once, then run for any tag separately.
#     compile_sparse_fsdb : build simv_sparse_fsdb (one-time)
#     run_sparse_fsdb     : run existing binary for SPARSE_TAG (no recompile)
.PHONY: compile_sparse_fsdb run_sparse_fsdb fsdb_sparse_sweep

compile_sparse_fsdb: $(SIMV_SPARSE_FSDB)

$(SIMV_SPARSE_FSDB): $(SRCS_SPARSE)
	@echo ">>> Compiling sparse FSDB binary (one-time)..."
	cd $(SIM_DIR) && $(VCS) $(VCSFLAGS) +define+FSDB $(FSDB_PLI) $(SRCS_SPARSE) \
	    -o simv_sparse_fsdb 2>&1 | tee compile_sparse_fsdb.log
	@grep -E "^(Error|Warning)" $(SIM_DIR)/compile_sparse_fsdb.log | head -20 || true

run_sparse_fsdb: $(SIMV_SPARSE_FSDB) $(SPARSE_DIR)/weight_mem_sparse.hex
	@echo ">>> [SPARSE_TAG=$(SPARSE_TAG)] Running sparse FSDB simulation..."
	cd $(SIM_DIR) && ./simv_sparse_fsdb +sparse_dir=tests_sparse/$(SPARSE_TAG) \
	    2>&1 | tee sim_sparse_fsdb_$(SPARSE_TAG).log
	@echo ">>> FSDB: $(SPARSE_DIR)/tb_CimBlock_sparse.fsdb"

# Run all 25 sweep FSDBs using the pre-compiled binary.
# Usage: make fsdb_sparse_sweep  (compile_sparse_fsdb is a prerequisite)
SWEEP_TAGS := \
    h000_f080_1 h020_f080_1 h040_f080_1 h060_f080_1 h080_f080_1 \
    h000_f080_2 h020_f080_2 h040_f080_2 h060_f080_2 h080_f080_2 \
    h000_f080_3 h020_f080_3 h040_f080_3 h060_f080_3 h080_f080_3 \
    h000_f080_4 h020_f080_4 h040_f080_4 h060_f080_4 h080_f080_4 \
    h000_f080_5 h020_f080_5 h040_f080_5 h060_f080_5 h080_f080_5

fsdb_sparse_sweep: $(SIMV_SPARSE_FSDB)
	@echo ">>> Running FSDB sim for all 25 sweep tags..."
	$(foreach tag,$(SWEEP_TAGS), \
	    cd $(SIM_DIR) && ./simv_sparse_fsdb +sparse_dir=tests_sparse/$(tag) \
	        2>&1 | tee sim_sparse_fsdb_$(tag).log ; \
	    echo ">>> Done: tests_sparse/$(tag)/tb_CimBlock_sparse.fsdb" ;)

$(SPARSE_DIR)/weight_mem_sparse.hex:
	@$(MAKE) gen_sparse

# 8. Naive baseline FSDB capture (ablation study: no LUT, direct MAC)
#    Uses the same test vectors as fsdb_sparse (pass same SPARSE_TAG).
#    Usage: make fsdb_naive [SPARSE_TAG=h080_f075_s8]
fsdb_naive: $(SPARSE_DIR)/weight_mem_sparse.hex
	@echo ">>> [SPARSE_TAG=$(SPARSE_TAG)] Compiling RTL for naive FSDB capture..."
	cd $(SIM_DIR) && $(VCS) $(VCSFLAGS) +define+FSDB $(FSDB_PLI) $(SRCS_NAIVE) \
	    -o simv_naive_fsdb 2>&1 | tee compile_naive_fsdb.log
	@grep -E "^(Error|Warning)" $(SIM_DIR)/compile_naive_fsdb.log | head -20 || true
	@echo ">>> Running naive FSDB simulation..."
	cd $(SIM_DIR) && ./simv_naive_fsdb +sparse_dir=tests_sparse/$(SPARSE_TAG) \
	    2>&1 | tee sim_naive_fsdb.log
	@echo ">>> FSDB: $(SPARSE_DIR)/tb_CimBlock_naive.fsdb"
	@echo ">>> Check sim_naive_fsdb.log for [PTPX] timestamps to fill in -time {}"

# ── Waveform helpers ───────────────────────────────────────────────────────
.PHONY: sim_vcd sim_fsdb
sim_vcd:
	@$(MAKE) sim VCD=1

sim_fsdb:
	@$(MAKE) sim FSDB=1

# ── Cleanup ────────────────────────────────────────────────────────────────
clean:
	rm -rf $(SIMV) $(SIMV).daidir $(SIMV_SAIF) $(SIMV_SAIF).daidir \
	       $(SIMV_SPARSE) $(SIMV_SPARSE).daidir \
	       $(SIMV_SPARSE_FSDB) $(SIMV_SPARSE_FSDB).daidir \
	       $(SIM_DIR)/csrc \
	       $(SIM_DIR)/compile.log $(SIM_DIR)/sim.log \
	       $(SIM_DIR)/compile_saif.log $(SIM_DIR)/saif.log \
	       $(SIM_DIR)/compile_sparse.log $(SIM_DIR)/saif_sparse.log \
	       $(SIM_DIR)/compile_sparse_fsdb.log $(SIM_DIR)/sim_sparse_fsdb.log \
	       $(SIM_DIR)/ucli.key \
	       $(SIM_DIR)/tb_CimBlock.vcd \
	       $(SIM_DIR)/tb_CimBlock.fsdb \
	       $(TEST_DIR)/sim.saif \
	       $(TESTS_SPARSE_DIR)/sim_sparse.saif \
	       $(TESTS_SPARSE_DIR)/tb_CimBlock_sparse.fsdb \
	       $(TESTS_SPARSE_DIR)/sim_output_sparse.hex \
	       $(SIM_OUT)

realclean: clean
	rm -rf $(TEST_DIR)
