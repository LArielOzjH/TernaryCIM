#!/usr/bin/env python3
"""
gen_test_vectors_sparse.py — Configurable-distribution test vector generator
for sparse power analysis of the Ternary CIM Block.

Generates four files under sim/tests_sparse/:
  weight_mem_sparse.hex  — 32 rows × 80-bit weight SRAM
  act_mem_sparse.hex     — 48 uint8 activation bytes
  zp_sparse.hex          — 1-byte zero point
  golden_sparse.hex      — 32 × 32-bit signed MAC results

Key configurable parameters (edit at top of file):
  ZP            — zero point byte (H4 = upper nibble, L4 = lower nibble)
  H4_MATCH_FRAC — fraction of individual activations with H4 == ZP_H4
  FLAG0_FRAC    — fraction of weight groups using flag=0 encoding
  SIGMA         — std dev for non-H4-match activations (Gaussian centred at ZP)
  SEED          — RNG seed for reproducibility
"""

import argparse
import random
import math
from pathlib import Path

# ── CLI (overrides the defaults below) ─────────────────────────────────────
def _parse_args():
    p = argparse.ArgumentParser(
        description='Sparse test vector generator for Ternary CIM Block.')
    p.add_argument('--zp',    type=lambda x: int(x, 0), default=0x39,
                   help='Zero point byte (hex OK, e.g. 0x39)')
    p.add_argument('--h4',    type=float, default=0.80,
                   metavar='H4_MATCH_FRAC',
                   help='Fraction of activations with H4 == ZP_H4 (default 0.80)')
    p.add_argument('--flag0', type=float, default=0.75,
                   metavar='FLAG0_FRAC',
                   help='Fraction of weight groups using flag=0 (default 0.75)')
    p.add_argument('--sigma', type=float, default=8.0,
                   help='Std dev for non-H4-match activations (default 8.0)')
    p.add_argument('--seed',  type=int,   default=42)
    p.add_argument('--tag',   type=str,   default=None,
                   help='Output subdirectory tag (default: auto from params)')
    return p.parse_args()

_args = _parse_args()

# ── Configurable parameters ─────────────────────────────────────────────────
ZP            = _args.zp
H4_MATCH_FRAC = _args.h4
FLAG0_FRAC    = _args.flag0
SIGMA         = _args.sigma
SEED          = _args.seed

# ── Architecture constants (must match tb_CimBlock_sparse.sv / CimMacro.sv) ─
N_GROUPS = 16
DEPTH    = 32

# ── 5-Pack-3 flag=1 weight table ────────────────────────────────────────────
FLAG1_WEIGHTS = {
    0: ( 0,  1, -1),
    1: ( 1,  0, -1),
    2: ( 1, -1,  0),
    3: ( 1, -1,  1),
    4: ( 1,  1, -1),
    5: ( 1, -1, -1),
}

# ── Precomputed wcode pools ──────────────────────────────────────────────────
# flag=0 pool: {sign ∈ {0,1}} × {data ∈ {0..7}}  →  16 wcodes
FLAG0_POOL = [(sign << 4) | (0 << 3) | data
              for sign in (0, 1) for data in range(8)]

# flag=1 pool: {sign ∈ {0,1}} × {data ∈ {0..5}}  →  12 wcodes
#              + 0x0F (all-zero special case)
FLAG1_POOL = [(sign << 4) | (1 << 3) | data
              for sign in (0, 1) for data in range(6)] + [0x0F]


# ── Codec ────────────────────────────────────────────────────────────────────

def decode_wcode(wcode: int) -> tuple:
    sign = (wcode >> 4) & 1
    flag = (wcode >> 3) & 1
    data = wcode & 7

    if (wcode & 0xF) == 0xF:        # all-zero special (0x0F or 0x1F)
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


# ── Activation generation ────────────────────────────────────────────────────

def gen_activations_sparse(rng: random.Random) -> list:
    """
    Generate 3*N_GROUPS uint8 activations with a configurable H4-match fraction.

    H4_MATCH_FRAC fraction have H4 == ZP_H4 (L4 uniform [0,15]).
    The remainder are drawn from Gaussian(ZP, SIGMA) with H4 != ZP_H4
    (rejection-sampled; clamped to [0, 255]).

    Returned list is shuffled to avoid systematic group bias.
    """
    total      = 3 * N_GROUPS
    zp_h4      = (ZP >> 4) & 0xF
    h4_lo      = zp_h4 * 16          # inclusive lower bound for H4 == ZP_H4
    h4_hi      = zp_h4 * 16 + 15    # inclusive upper bound
    n_match    = round(total * H4_MATCH_FRAC)
    n_nonmatch = total - n_match

    # --- H4-match activations: H4 = ZP_H4, L4 uniform [0,15] ---
    match_acts = [h4_lo + rng.randint(0, 15) for _ in range(n_match)]

    # --- Non-H4-match activations: Gaussian(ZP, SIGMA) with H4 != ZP_H4 ---
    nonmatch_acts = []
    attempts = 0
    while len(nonmatch_acts) < n_nonmatch:
        v = round(rng.gauss(ZP, SIGMA))
        v = max(0, min(255, v))
        if not (h4_lo <= v <= h4_hi):   # reject if H4 would be ZP_H4
            nonmatch_acts.append(v)
        attempts += 1
        if attempts > 100 * n_nonmatch + 200:
            raise RuntimeError(
                f"Rejection sampling stuck: SIGMA={SIGMA} too narrow to generate "
                f"enough values outside [{h4_lo},{h4_hi}]. Try increasing SIGMA.")

    acts = match_acts + nonmatch_acts
    rng.shuffle(acts)
    return acts


# ── Weight generation ─────────────────────────────────────────────────────────

def gen_weight_rows_sparse(rng: random.Random) -> list:
    """
    Generate DEPTH rows.  For each of the N_GROUPS groups:
      - With probability FLAG0_FRAC: sample from FLAG0_POOL (direct LUT lookup)
      - Otherwise:                   sample from FLAG1_POOL (dynamic subtraction)

    Row 0 is always all-zero (0x0F) as a sanity anchor.
    """
    rows = []

    # Row 0: all-zero anchor
    rows.append([0x0F] * N_GROUPS)

    for _ in range(DEPTH - 1):
        row = []
        for _ in range(N_GROUPS):
            if rng.random() < FLAG0_FRAC:
                row.append(rng.choice(FLAG0_POOL))
            else:
                row.append(rng.choice(FLAG1_POOL))
        rows.append(row)

    return rows


# ── Golden reference model ───────────────────────────────────────────────────

def compute_row_golden(wcodes: list, acts: list) -> int:
    acc = 0
    for i in range(N_GROUPS):
        w0, w1, w2 = decode_wcode(wcodes[i])
        acc += w0 * acts[3*i] + w1 * acts[3*i+1] + w2 * acts[3*i+2]
    acc &= 0xFFFF_FFFF
    return acc - (1 << 32) if acc >= (1 << 31) else acc


# ── Hex file writers ──────────────────────────────────────────────────────────

def row_to_int(wcodes: list) -> int:
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


# ── Statistics helpers ────────────────────────────────────────────────────────

def activation_stats(acts: list) -> dict:
    zp_h4 = (ZP >> 4) & 0xF
    h4_lo = zp_h4 * 16
    h4_hi = zp_h4 * 16 + 15
    n_match = sum(1 for v in acts if h4_lo <= v <= h4_hi)
    # all_zp per group (group = 3 consecutive activations)
    n_groups = len(acts) // 3
    all_zp_count = sum(
        1 for g in range(n_groups)
        if all(h4_lo <= acts[3*g+j] <= h4_hi for j in range(3))
    )
    return {
        'n_total':     len(acts),
        'n_h4_match':  n_match,
        'frac_h4':     n_match / len(acts),
        'n_groups':    n_groups,
        'n_all_zp':    all_zp_count,
        'frac_all_zp': all_zp_count / n_groups,
        'min': min(acts), 'max': max(acts),
    }


def weight_stats(rows: list) -> dict:
    total = flag0 = flag1 = all_zero = 0
    for row in rows:
        for wc in row:
            total += 1
            if (wc & 0xF) == 0xF:   # special all-zero
                all_zero += 1
                flag1 += 1           # encoded as flag=1
            elif (wc >> 3) & 1:
                flag1 += 1
            else:
                flag0 += 1
    return {
        'total':       total,
        'flag0':       flag0,
        'flag1':       flag1,
        'all_zero':    all_zero,
        'frac_flag0':  flag0 / total,
        'frac_flag1':  flag1 / total,
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    rng = random.Random(SEED)

    # Auto-generate tag from params if not supplied on CLI
    tag = _args.tag or f"h{int(H4_MATCH_FRAC*100):03d}_f{int(FLAG0_FRAC*100):03d}_s{int(SIGMA)}"
    out_dir = Path(__file__).resolve().parent / 'tests_sparse' / tag
    out_dir.mkdir(parents=True, exist_ok=True)

    zp_h4 = (ZP >> 4) & 0xF
    zp_l4 = ZP & 0xF

    print('=== Sparse Ternary CIM Test Vector Generator ===')
    print(f'  N_GROUPS={N_GROUPS}  DEPTH={DEPTH}')
    print(f'  ZP=0x{ZP:02x}  (H4={zp_h4}, L4={zp_l4})')
    print(f'  H4_MATCH_FRAC={H4_MATCH_FRAC:.2f}  FLAG0_FRAC={FLAG0_FRAC:.2f}')
    print(f'  SIGMA={SIGMA}  SEED={SEED}')
    print(f'  Tag:        {tag}')
    print(f'  Output dir: {out_dir}')

    # 1. Activations
    acts = gen_activations_sparse(rng)
    astats = activation_stats(acts)
    print(f'\n[1/4] Activations: {astats["n_total"]} bytes')
    print(f'  H4-match: {astats["n_h4_match"]}/{astats["n_total"]} '
          f'= {astats["frac_h4"]*100:.1f}%  (target {H4_MATCH_FRAC*100:.0f}%)')
    print(f'  all_zp groups: {astats["n_all_zp"]}/{astats["n_groups"]} '
          f'= {astats["frac_all_zp"]*100:.1f}%  '
          f'(expected {H4_MATCH_FRAC**3 * 100:.1f}% from H4_MATCH_FRAC^3)')
    print(f'  Range: [{astats["min"]}, {astats["max"]}]')

    # 2. Weights
    rows = gen_weight_rows_sparse(rng)
    wstats = weight_stats(rows)
    print(f'\n[2/4] Weights: {wstats["total"]} group-codes across {DEPTH} rows')
    print(f'  flag=0: {wstats["flag0"]}  ({wstats["frac_flag0"]*100:.1f}%)  '
          f'(target {FLAG0_FRAC*100:.0f}%)')
    print(f'  flag=1: {wstats["flag1"]}  ({wstats["frac_flag1"]*100:.1f}%)  '
          f'(incl. {wstats["all_zero"]} all-zero special)')

    # 3. Golden outputs
    print(f'\n[3/4] Computing golden outputs...')
    goldens = [compute_row_golden(rows[r], acts) for r in range(DEPTH)]
    assert goldens[0] == 0, f'Row 0 all-zero anchor failed: got {goldens[0]}'
    print(f'  Row 0 all-zero check: OK')
    print(f'  Result range: [{min(goldens)}, {max(goldens)}]')
    for r in range(DEPTH):
        print(f'    row[{r:3d}]: {goldens[r]:12d}  (0x{goldens[r] & 0xFFFF_FFFF:08x})')

    # 4. Write files
    print(f'\n[4/4] Writing files:')
    files = [
        ('weight_mem_sparse.hex', lambda p: write_weight_mem_hex(rows, p)),
        ('act_mem_sparse.hex',    lambda p: write_act_mem_hex(acts, p)),
        ('zp_sparse.hex',         lambda p: write_zp_hex(ZP, p)),
        ('golden_sparse.hex',     lambda p: write_golden_hex(goldens, p)),
    ]
    for name, writer in files:
        p = out_dir / name
        writer(p)
        print(f'  {name:<28s}  {p.stat().st_size:>8,} bytes')

    print(f'\nDone.  Run  make fsdb_sparse SPARSE_TAG={tag}  (from sim/) to simulate.')


if __name__ == '__main__':
    main()
