#!/usr/bin/env python3
"""
gen_test_vectors.py — Ternary CIM Block Test Vector Generator

Generates four files under sim/tests/:
  weight_mem.hex  — 32 rows × 80-bit weight SRAM ($readmemh, 20 hex chars/line)
  act_mem.hex     — 48 uint8 activation bytes (2 hex chars/line)
  zp.hex          — 1-byte zero point (2 hex chars)
  golden.hex      — 16 × 32-bit signed MAC results (8 hex chars/line)

Architecture parameters (must match tb_CimBlock.sv):
  N_GROUPS = 16     — weight groups per row
  DEPTH    = 32     — SRAM rows
  ZP       = 0x20   — unsigned zero point (ZP_H4 = 2, acts in [32, 47])

5-Pack-3 encoding: wcode[4:0] = {sign[4], flag[3], data[2:0]}
  sign=0/1 : group-level mirror (negate all weights if sign=1)
  flag=0   : each data bit → 0 or +1  (data used as index into 8-entry LUT)
  flag=1   : weight contains −1 (6 valid data values 0..5)
  {flag,data}=4'b1111 : special all-zero group → output 0

Activation bus layout (matches CimMacro.sv and testbench):
  act_bytes[3*i]   = act0 for group i  → act_in[24*i +: 8]
  act_bytes[3*i+1] = act1 for group i  → act_in[24*i+8 +: 8]
  act_bytes[3*i+2] = act2 for group i  → act_in[24*i+16 +: 8]

Weight memory layout (per 320-bit row):
  group i occupies bits [5*i+4 : 5*i]  (little-endian groups)

Golden model:
  result = Σ_{i=0}^{15} Σ_{j=0}^{2} w_{i,j} × act_{i,j}   (32-bit 2's complement)
  where w_{i,j} ∈ {-1, 0, +1} decoded from 5-bit wcode.
"""

import random
from pathlib import Path

# ── Architecture constants ─────────────────────────────────────────────────
N_GROUPS = 16
DEPTH    = 32
ZP       = 0x20          # ZP_H4 = 2 → all test acts are in [32, 47]

# flag=1 data → (w0, w1, w2) weight patterns
FLAG1_WEIGHTS = {
    0: ( 0,  1, -1),   # (0,+1,-1)
    1: ( 1,  0, -1),   # (+1,0,-1)
    2: ( 1, -1,  0),   # (+1,-1,0)
    3: ( 1, -1,  1),   # (+1,-1,+1)
    4: ( 1,  1, -1),   # (+1,+1,-1)
    5: ( 1, -1, -1),   # (+1,-1,-1)
}

# ── 5-Pack-3 codec ─────────────────────────────────────────────────────────

def encode_ternary(w0: int, w1: int, w2: int) -> int:
    """Encode (w0, w1, w2) ∈ {-1,0,+1} → 5-bit wcode. All 27 patterns are valid."""
    ws = (w0, w1, w2)
    if ws == (0, 0, 0):
        return 0x0F          # {sign=0, flag=1, data=111} → all-zero special

    if all(w >= 0 for w in ws):                 # flag=0, sign=0
        data = (1 if w0 else 0) | (2 if w1 else 0) | (4 if w2 else 0)
        return (0 << 4) | (0 << 3) | data

    if all(w <= 0 for w in ws):                 # flag=0, sign=1 (mirror of 0/+1)
        data = (1 if -w0 else 0) | (2 if -w1 else 0) | (4 if -w2 else 0)
        return (1 << 4) | (0 << 3) | data

    for d, (fw0, fw1, fw2) in FLAG1_WEIGHTS.items():   # flag=1, sign=0
        if (fw0, fw1, fw2) == ws:
            return (0 << 4) | (1 << 3) | d

    nws = (-w0, -w1, -w2)
    for d, (fw0, fw1, fw2) in FLAG1_WEIGHTS.items():   # flag=1, sign=1
        if (fw0, fw1, fw2) == nws:
            return (1 << 4) | (1 << 3) | d

    raise ValueError(f"Cannot encode ({w0},{w1},{w2})")


def decode_wcode(wcode: int) -> tuple:
    """Decode 5-bit wcode → (w0, w1, w2) ∈ {-1, 0, +1}."""
    sign = (wcode >> 4) & 1
    flag = (wcode >> 3) & 1
    data = wcode & 7

    if (wcode & 0xF) == 0xF:       # all-zero special (both 0x0F and 0x1F)
        return (0, 0, 0)

    if flag == 0:
        w0 = 1 if (data & 1) else 0
        w1 = 1 if (data & 2) else 0
        w2 = 1 if (data & 4) else 0
    else:
        w0, w1, w2 = FLAG1_WEIGHTS.get(data, (0, 0, 0))

    if sign:
        w0, w1, w2 = -w0, -w1, -w2
    return (w0, w1, w2)


def random_wcode(rng: random.Random) -> int:
    """Random valid 5-bit weight code drawn uniformly over all 27 ternary triples."""
    all_triples = [(w0, w1, w2)
                   for w0 in (-1, 0, 1) for w1 in (-1, 0, 1) for w2 in (-1, 0, 1)]
    return encode_ternary(*rng.choice(all_triples))


# ── Golden reference model ─────────────────────────────────────────────────

def compute_row_golden(wcodes: list, acts: list) -> int:
    """
    Compute the expected 32-bit signed output for one SRAM row.

    wcodes : list of N_GROUPS 5-bit weight codes
    acts   : list of 192 uint8 bytes
               act0 of group i = acts[3*i], act1 = acts[3*i+1], act2 = acts[3*i+2]

    Returns signed 32-bit Python int (no overflow for valid inputs).
    """
    acc = 0
    for i in range(N_GROUPS):
        w0, w1, w2 = decode_wcode(wcodes[i])
        a0 = acts[3 * i]
        a1 = acts[3 * i + 1]
        a2 = acts[3 * i + 2]
        acc += w0 * a0 + w1 * a1 + w2 * a2
    # 32-bit 2's complement representation
    acc &= 0xFFFF_FFFF
    return acc - (1 << 32) if acc >= (1 << 31) else acc


# ── Structured test weight patterns ───────────────────────────────────────

def gen_weight_rows(rng: random.Random) -> list:
    """
    Return DEPTH rows, each a list of N_GROUPS 5-bit weight codes.
    First several rows are structured; the rest are random.
    """
    rows = []

    def row_of(wcode: int):
        return [wcode] * N_GROUPS

    def row_flag0(d: int, sign: int = 0):
        """All groups with flag=0, given data and sign."""
        return [(sign << 4) | (0 << 3) | d] * N_GROUPS

    def row_flag1(d: int, sign: int = 0):
        """All groups with flag=1, given data and sign."""
        return [(sign << 4) | (1 << 3) | d] * N_GROUPS

    # Row 0: all-zero weights (wcode=0x0F for every group)
    rows.append(row_of(0x0F))

    # Row 1: all (+1,+1,+1)  → flag=0, data=7, sign=0 → 0x07
    rows.append(row_flag0(7, sign=0))

    # Row 2: all (−1,−1,−1)  → flag=0, data=7, sign=1 → 0x17
    rows.append(row_flag0(7, sign=1))

    # Row 3: all (+1, 0, 0)  → flag=0, data=1, sign=0 → 0x01
    rows.append(row_flag0(1, sign=0))

    # Row 4: all (0, +1, 0)  → flag=0, data=2, sign=0 → 0x02
    rows.append(row_flag0(2, sign=0))

    # Row 5: all (0, 0, +1)  → flag=0, data=4, sign=0 → 0x04
    rows.append(row_flag0(4, sign=0))

    # Row 6: all (0, +1, −1) → flag=1, data=0, sign=0 → 0x08
    rows.append(row_flag1(0, sign=0))

    # Row 7: all (+1, 0, −1) → flag=1, data=1, sign=0 → 0x09
    rows.append(row_flag1(1, sign=0))

    # Row 8: all (+1, −1, 0) → flag=1, data=2, sign=0 → 0x0A
    rows.append(row_flag1(2, sign=0))

    # Row 9: all (+1, −1, +1) → flag=1, data=3, sign=0 → 0x0B
    rows.append(row_flag1(3, sign=0))

    # Row 10: all (+1, +1, −1) → flag=1, data=4, sign=0 → 0x0C
    rows.append(row_flag1(4, sign=0))

    # Row 11: all (+1, −1, −1) → flag=1, data=5, sign=0 → 0x0D
    rows.append(row_flag1(5, sign=0))

    # Row 12: sign-mirrored (+1,−1,+1) → sign=1, flag=1, data=3 → 0x1B
    rows.append(row_flag1(3, sign=1))

    # Row 13: sign-mirrored (+1,+1,−1) → sign=1, flag=1, data=4 → 0x1C
    rows.append(row_flag1(4, sign=1))

    # Row 14: sign-mirrored (+1,−1,−1) → sign=1, flag=1, data=5 → 0x1D
    rows.append(row_flag1(5, sign=1))

    # Row 15: random (fills to DEPTH=16)
    while len(rows) < DEPTH:
        rows.append([random_wcode(rng) for _ in range(N_GROUPS)])

    return rows[:DEPTH]


# ── Activation generation ──────────────────────────────────────────────────

def gen_activations(rng: random.Random) -> list:
    """
    Return 192 uint8 bytes in ZP-mode:
      all activations are in [ZP_H4*16, ZP_H4*16+15] (H4 == ZP_H4 for all).
    This ensures all groups use ZP mode in LutBuilder (all_zp=1).
    """
    zp_h4 = (ZP >> 4) & 0xF
    base = zp_h4 * 16              # = 32 for ZP=0x20
    return [base + rng.randint(0, 15) for _ in range(3 * N_GROUPS)]


# ── Hex file writers ───────────────────────────────────────────────────────

def row_to_int(wcodes: list) -> int:
    """Pack N_GROUPS 5-bit codes into one 320-bit integer (group i at bits [5i+4:5i])."""
    val = 0
    for i, wc in enumerate(wcodes):
        val |= (wc & 0x1F) << (5 * i)
    return val


def write_weight_mem_hex(rows: list, path: Path):
    with open(path, 'w') as f:
        for row in rows:
            f.write(f'{row_to_int(row):020x}\n')


def write_act_mem_hex(acts: list, path: Path):
    with open(path, 'w') as f:
        for b in acts:
            f.write(f'{b:02x}\n')


def write_zp_hex(zp: int, path: Path):
    with open(path, 'w') as f:
        f.write(f'{zp:02x}\n')


def write_golden_hex(goldens: list, path: Path):
    with open(path, 'w') as f:
        for g in goldens:
            f.write(f'{g & 0xFFFF_FFFF:08x}\n')


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    rng = random.Random(42)

    out_dir = Path(__file__).resolve().parent / 'tests'
    out_dir.mkdir(exist_ok=True)

    print('=== Ternary CIM Test Vector Generator ===')
    print(f'  N_GROUPS={N_GROUPS}  DEPTH={DEPTH}  ZP=0x{ZP:02x} (ZP_H4={ZP>>4})')
    print(f'  Acts range: [{(ZP>>4)*16}, {(ZP>>4)*16+15}]  (H4 = ZP_H4 = {ZP>>4}, ZP mode)')
    print(f'  Output dir: {out_dir}')

    # 1. Weight patterns
    rows = gen_weight_rows(rng)
    print(f'\n[1/4] Weight patterns: {DEPTH} rows × {N_GROUPS} groups')
    # Roundtrip sanity: encode → decode → re-encode
    for r, row in enumerate(rows):
        for g, wc in enumerate(row):
            ws = decode_wcode(wc)
            rc = encode_ternary(*ws)
            assert decode_wcode(rc) == ws, f'roundtrip fail row={r} grp={g} wc=0x{wc:02x}'
    print(f'  Encode/decode roundtrip: OK')

    # 2. Activations (ZP mode)
    acts = gen_activations(rng)
    print(f'\n[2/4] Activations: {3*N_GROUPS} bytes in [{min(acts)}, {max(acts)}]')

    # 3. Golden outputs
    print(f'\n[3/4] Computing golden outputs...')
    goldens = [compute_row_golden(rows[r], acts) for r in range(DEPTH)]
    print(f'  Result range: [{min(goldens)}, {max(goldens)}]')

    # Spot-check deterministic rows
    assert goldens[0] == 0, f'Row 0 (all-zero) expected 0, got {goldens[0]}'
    sum_all = sum(acts[3*i]+acts[3*i+1]+acts[3*i+2] for i in range(N_GROUPS))
    assert goldens[1] == sum_all, f'Row 1 (+1+1+1) expected {sum_all}, got {goldens[1]}'
    assert goldens[2] == -sum_all, f'Row 2 (-1-1-1) expected {-sum_all}, got {goldens[2]}'
    sum_act0 = sum(acts[3*i] for i in range(N_GROUPS))
    assert goldens[3] == sum_act0, f'Row 3 (+1,0,0) expected {sum_act0}, got {goldens[3]}'
    print('  Spot checks (rows 0-3): OK')

    print(f'\n  All {DEPTH} rows:')
    for r in range(DEPTH):
        print(f'    row[{r:3d}]: {goldens[r]:12d}  (0x{goldens[r] & 0xFFFF_FFFF:08x})')

    # 4. Write files
    print(f'\n[4/4] Writing files:')
    files = [
        ('weight_mem.hex', lambda p: write_weight_mem_hex(rows, p)),
        ('act_mem.hex',    lambda p: write_act_mem_hex(acts, p)),
        ('zp.hex',         lambda p: write_zp_hex(ZP, p)),
        ('golden.hex',     lambda p: write_golden_hex(goldens, p)),
    ]
    for name, writer in files:
        p = out_dir / name
        writer(p)
        print(f'  {name:<20s}  {p.stat().st_size:>8,} bytes')

    print('\nDone.  Run  make sim  (from sim/) to compile and simulate.')


if __name__ == '__main__':
    main()
