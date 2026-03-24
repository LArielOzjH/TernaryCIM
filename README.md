# BitCIM — Ternary Compute-In-Memory Macro

RTL implementation and simulation infrastructure for a Ternary CIM macro targeting
BitNet 1.58 LLM acceleration (W1.58A8: ternary weights ∈ {−1, 0, +1}, INT8 activations).
Technology: TSMC 28nm HPC+ (`tcbn28hpcplusbwp30p140hvt`).

---

## Hardware (`hw/`)

### Architecture Overview

The CIM macro processes one SRAM row per cycle. Each row holds 64 weight groups encoded
in 5-Pack-3 format (320 bits total). For a given activation vector, the macro produces a
32-bit signed dot-product result two cycles after asserting `cim_ren`.

```
act_valid ──► ZpSplitter × 64 ──► LutBuilder × 64 ──► LUT Registers
                                                              │
cim_ren ───► CellArray (SRAM) ──► LutLookup × 64 ──► DualAdderTree ──► final + ZpComp ──► OutReg ──► cim_odata
```

**Two-phase operation:**

| Phase | Trigger | What happens |
|-------|---------|--------------|
| LUT load | `act_valid = 1` | 192 INT8 activations + ZP latched; per-group LUT entries computed and stored in registers |
| Compute | `cim_ren = 1` | SRAM row read; 64 LUT lookups; SM dual adder tree; ZP compensation; result in `cim_odata` after 2 cycles |

### Key Design Innovations

#### 1. 5-Pack-3 Zero-Aware Encoding

Three ternary weights are packed into 5 bits: `{sign[4], flag[3], data[2:0]}`.

| Field | Meaning |
|-------|---------|
| `sign` | Group mirror — if 1, negate all three weights |
| `flag=0` | Each bit of `data` encodes 0 or +1 (8 patterns) |
| `flag=1` | Weight pattern contains −1 (6 valid patterns, `data` ∈ 0..5) |
| `{flag,data}=4'b1111` | Special all-zero group — output forced to 0 |

Flag=1 patterns (before sign negation):

| `data` | Weights `(w0, w1, w2)` |
|--------|----------------------|
| 000 | (0, +1, −1) |
| 001 | (+1, 0, −1) |
| 010 | (+1, −1, 0) |
| 011 | (+1, −1, +1) |
| 100 | (+1, +1, −1) |
| 101 | (+1, −1, −1) |

#### 2. Hierarchy Dynamic SM LUT

For each group, only 8 flag=0 entries are stored (indexed directly by `data[2:0]`).
Each flag=0 entry is a non-negative sum of L4 activation nibbles — sign is always 0.
Flag=1 entries are derived on-the-fly as the difference of two stored flag=0 entries,
avoiding extra SRAM storage for negative weight patterns.

#### 3. Sign-Magnitude Dual Adder Tree

LUT lookup results are in sign-magnitude (SM) format `{sign, mag[9:0]}`. Two parallel
adder trees accumulate positive and negative magnitudes separately:

```
result = POS_sum − NEG_sum
```

This avoids two's-complement conversion overhead and keeps the adder trees unsigned.

#### 4. Asymmetric Quantization Support (uint8 + ZP)

Activations are treated as `uint8` with a scalar zero point `ZP`.
The LUT always operates on the **L4 nibble** (`act[3:0]`); the H4 contribution is
restored by `ZpCompensate`:

```
comp_i = (popcount_i × ZP_H4 + Σ_j w_j × delta_j) × 16
       = Σ_j w_j × H4_j × 16

final = Σ_i w_i · L4_i  +  Σ_i comp_i  =  Σ_i w_i · act_i
```

where `delta_j = H4_j − ZP_H4` and `popcount_i = Σ_j w_{i,j}`.
This decomposition is exact and requires no approximation.

### Pipeline Timing

```
Cycle 0  │ assert cim_ren=1, cim_raddr=K
Cycle 1  │ SRAM reads row K → w_out; combinational: LutLookup, DualAdderTree, ZpCompensate
         │ cim_ren_reg latches 1
Cycle 2  │ OutReg captures final_result (gated by cim_ren_reg)
         │ cim_odata_valid = 1 → cim_odata is valid
```

Total read latency: **2 cycles** from `cim_ren` assertion to valid `cim_odata`.

For activation loading, assert `act_valid` for one cycle; allow at least 2 cycles before
asserting `cim_ren` (CimBlock adds one input register stage; CimMacro adds one LUT
register stage).

### Module Inventory

| Module | File | Description |
|--------|------|-------------|
| `CimBlock` | `CimBlock.sv` | Top-level wrapper; adds one input register stage for write/activation signals; read signals bypass the register for latency consistency |
| `CimMacro` | `CimMacro.sv` | Core compute pipeline: SRAM + LUT phase + compute phase + ZP compensation |
| `CellArray` | `CellArray.sv` | 128×320-bit SRAM array; instantiates 320 `CimRow` instances and two `CimDecoder`/`CimDecoderBuffer` pairs |
| `CimRow` | `CimRow.sv` | Single-bit SRAM column (128 cells); uses `S8T1` cells, `WD7T` write driver, `RA6T` read amplifier |
| `CimDecoder` | `CimDecoder.v` | Parametric 1-of-N address decoder; `DEPTH` configurable |
| `CimDecoderBuffer` | `CimDecoderBuffer.v` | Word-line buffer using `BUFFD8BWP30P140HVT` standard cells |
| `ClockGate` | `ClockGate.v` | Latch-based clock gate; ASIC path uses `CKLNQD16BWP30P140HVT`; behavioral fallback for simulation |
| `ZpSplitter` | `ZpSplitter.sv` | Splits 3 activations into H4/L4 nibbles; computes `delta = H4 − ZP_H4`; flags groups where all H4 == ZP_H4 |
| `LutBuilder` | `LutBuilder.sv` | Builds 8 flag=0 LUT entries from L4 nibbles; always uses L4 so ZpCompensate can correctly restore H4 |
| `LutLookup` | `LutLookup.sv` | Maps 5-bit weight code to SM output; derives flag=1 entries dynamically; applies group sign XOR |
| `WeightPopcount` | `WeightPopcount.sv` | Computes algebraic weight sum `Σ w_i ∈ {−1,0,+1}` from 5-bit code; range −3..+3 |
| `DualAdderTree` | `DualAdderTree.sv` | 64-input SM dual adder tree; routes magnitudes to POS/NEG trees; output = POS − NEG (32-bit signed) |
| `ZpCompensate` | `ZpCompensate.sv` | Accumulates `Σ_i (popcount_i × ZP_H4 + Σ_j w_j × delta_j) × 16` across 64 groups |
| `OutReg` | `OutReg.sv` | Output register; captures result and asserts `cim_odata_valid` one cycle after its `cim_ren` input |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_GROUPS` | 64 | Weight groups per SRAM row |
| `DEPTH` | 128 | SRAM depth (rows); must be a power of 2 |
| `ADDR_WIDTH` | `$clog2(DEPTH)` = 7 | Address bus width |
| `WIDTH` | `5 × N_GROUPS` = 320 | SRAM word width in bits |

---

## Simulation (`sim/`)

### Quick Start

```bash
cd sim/
make          # generate vectors → compile RTL → simulate → verify
```

Individual steps:

```bash
make gen      # generate sim/tests/*.hex via gen_test_vectors.py
make compile  # VCS RTL compilation → simv
make sim      # run simv → writes sim/tests/sim_output.hex + sim.log
make verify   # compare sim_output.hex vs golden.hex (Python)
make clean    # remove build artefacts (keeps tests/)
make realclean  # remove everything including tests/
```

Waveform capture:

```bash
make sim VCD=1    # dumps tb_CimBlock.vcd
make sim FSDB=1   # dumps tb_CimBlock.fsdb (requires Verdi)
```

### File Layout

```
sim/
├── Makefile                  VCS compilation and simulation flow
├── tb_CimBlock.sv            SystemVerilog testbench (DUT = CimBlock)
├── sim_cells.v               Behavioral model for BUFFD8BWP30P140HVT
├── gen_test_vectors.py       Test vector generator and golden reference model
├── verify_sim_output.py      Post-simulation result comparator
├── compile.log               VCS compile output (generated)
├── sim.log                   Simulation output (generated)
└── tests/                    Test data directory (generated by make gen)
    ├── weight_mem.hex         128 rows × 320-bit SRAM init  ($readmemh, 80 hex chars/line)
    ├── act_mem.hex            192 uint8 activation bytes     (2 hex chars/line)
    ├── zp.hex                 1-byte zero point
    ├── golden.hex             128 × 32-bit expected outputs  (8 hex chars/line)
    └── sim_output.hex         Written by testbench during simulation
```

### Test Vector Generation (`gen_test_vectors.py`)

Generates deterministic weight patterns covering the full encoding space, plus random rows:

| Row range | Pattern |
|-----------|---------|
| 0 | All-zero weights (`wcode=0x0F` for every group) |
| 1 | All (+1,+1,+1) |
| 2 | All (−1,−1,−1) |
| 3–5 | All single-active: (+1,0,0), (0,+1,0), (0,0,+1) |
| 6–11 | All flag=1 patterns (data 0..5, sign=0) |
| 12–14 | Sign-mirrored flag=1 patterns (sign=1) |
| 15–16 | Mixed alternating and one-hot per group |
| 17–127 | Random weight codes (all 27 ternary triples, uniform) |

**Activations** are generated in ZP mode: all 192 bytes have `H4 = ZP_H4 = 2`,
so every group's `all_zp` flag is asserted and the L4-path is fully exercised.
Default `ZP = 0x20`; activation range `[32, 47]`.

**Golden model**: `result = Σ_{i=0}^{63} (w0_i·act0_i + w1_i·act1_i + w2_i·act2_i)` (signed 32-bit).

### Testbench (`tb_CimBlock.sv`)

- **Clock**: 500 MHz (2 ns period)
- **Reset**: synchronous, 8-cycle hold
- **Write phase**: streams all 128 rows into SRAM (3 cycles per row for setup margin)
- **Activation load**: drives `act_in` + `zp_in`, pulses `act_valid` for one cycle, waits 4 settle cycles
- **Read phase**: asserts `cim_ren=1` for cycles 0..127 (`cim_raddr` advances each cycle);
  collects `cim_odata` whenever `cim_odata_valid=1` (first valid appears at cycle 1 of the read phase)
- **Output**: writes collected results to `tests/sim_output.hex`; prints inline PASS/FAIL per row
- **Watchdog**: simulation aborts after 10 ms

### Verification (`verify_sim_output.py`)

```bash
python3 sim/verify_sim_output.py               # uses default sim/tests/sim_output.hex
python3 sim/verify_sim_output.py path/to/out.hex
```

Reports per-row signed comparison, total pass/fail count, and exits with code 1 on any mismatch.

### Requirements

- **VCS** (Synopsys) with SystemVerilog support (`-sverilog +v2k`)
- **Python 3.7+** (standard library only)
- No external cell libraries required for simulation — ASIC cells are replaced by
  `sim/sim_cells.v` (behavioral `BUFFD8BWP30P140HVT`) and `ClockGate.v`'s built-in
  RTL fallback (`ifdef ASIC_CLOCK_GATING` not defined)
