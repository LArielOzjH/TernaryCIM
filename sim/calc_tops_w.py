#!/usr/bin/env python3
"""
calc_tops_w.py — Effective TOPs/W calculator for CIM power analysis.

Reads a single DC SAIF-annotated power report covering one complete inference
(LUT build phase + compute phase together):
  ../backend/syn/reports_power_saif/power.rpt          (default)
  ../backend/syn/reports_power_saif_sparse/power.rpt   (--sparse)

Computes effective TOPs/W:
  E_total = P_avg × N_TOTAL_CYC × T_CLK
  TOPs/W  = (DEPTH × N_GROUPS × 3 × 2 ops) / E_total
"""

import argparse
import re
import sys
from pathlib import Path

# ── Architecture constants (must match tb_CimBlock.sv / CimMacro.sv) ───────
N_GROUPS   = 16
DEPTH      = 32
T_CLK_NS   = 2.5        # clock period (ns), matches DC constraint

# Cycle counts matching the testbench tasks:
#   load_activations: 1 (act_valid) + ACT_SETTLE(4) + 1 latency = 6 cycles
ACT_SETTLE  = 4
N_LUT_CYC   = 1 + ACT_SETTLE + 1   # = 6

#   read_all_rows: DEPTH+2 cycles (2-cycle pipeline drain)
N_COMP_CYC  = DEPTH + 2             # = 34

# Total cycles for one inference (LUT build + compute)
N_TOTAL_CYC = N_LUT_CYC + N_COMP_CYC   # = 40

# Ops per inference: DEPTH rows × N_GROUPS groups × 3 weights × 2 ops/MAC
OPS_PER_INF = DEPTH * N_GROUPS * 3 * 2   # = 3072


# ── DC report parser ────────────────────────────────────────────────────────

def parse_total_power_mw(report_path: Path) -> float:
    """
    Extract the scalar total power (Dynamic + Leakage) from a DC report_power output.
    Looks for lines of the form:
        Total Dynamic Power    =   X.XXXX mW  (100%)
        Cell Leakage Power     =   X.XXXX uW
    Returns total power in mW.
    """
    text = report_path.read_text()

    # Dynamic power line
    m = re.search(r'Total Dynamic Power\s+=\s+([\d.]+)\s+mW', text)
    if not m:
        raise ValueError(f"Cannot find 'Total Dynamic Power' in {report_path}")
    dyn_mw = float(m.group(1))

    # Leakage power line (may be in uW or mW)
    m = re.search(r'Cell Leakage Power\s+=\s+([\d.e+\-]+)\s+(mW|uW|nW)', text)
    if not m:
        raise ValueError(f"Cannot find 'Cell Leakage Power' in {report_path}")
    leak_val  = float(m.group(1))
    leak_unit = m.group(2)
    if leak_unit == 'mW':
        leak_mw = leak_val
    elif leak_unit == 'uW':
        leak_mw = leak_val * 1e-3
    else:  # nW
        leak_mw = leak_val * 1e-6

    return dyn_mw + leak_mw


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description='Compute effective TOPs/W from DC SAIF-annotated power report.')
    parser.add_argument('--sparse', action='store_true',
                        help='Use sparse reports (reports_power_saif_sparse/) '
                             'instead of default (reports_power_saif/)')
    args = parser.parse_args()

    base = Path(__file__).resolve().parent
    rpt_subdir = 'reports_power_saif_sparse' if args.sparse else 'reports_power_saif'
    rpt_dir = base / '..' / 'backend' / 'syn' / rpt_subdir

    rpt = rpt_dir / 'power.rpt'

    if not rpt.exists():
        print(f"ERROR: missing report file: {rpt}")
        print("\nRun the flow first:")
        if args.sparse:
            print("  cd sim && make saif_sparse")
            print("  cd backend/syn && dc_shell -f dc_power_saif_sparse.tcl")
        else:
            print("  cd sim && make saif")
            print("  cd backend/syn && dc_shell -f dc_power_saif.tcl")
        sys.exit(1)

    P_mw = parse_total_power_mw(rpt)

    # Energy per inference (pJ): P_mw × N_TOTAL_CYC × T_CLK_NS
    E_total_pj = P_mw * 1e-3 * N_TOTAL_CYC * T_CLK_NS * 1e3   # mW × cycles × ns → pJ

    # Effective TOPs/W
    tops_w = OPS_PER_INF / (E_total_pj * 1e-12) / 1e12

    label = "Sparse" if args.sparse else "Default"
    print("=" * 56)
    print(f"  CimBlock Power Analysis [{label}]")
    print(f"  N_GROUPS={N_GROUPS}  DEPTH={DEPTH}  f={1/T_CLK_NS*1000:.0f} MHz")
    print("=" * 56)

    print(f"\n  Power (SAIF-annotated) : {P_mw*1e3:.2f} uW  ({P_mw:.4f} mW)")
    print(f"  Total cycles           : {N_TOTAL_CYC}  "
          f"({N_LUT_CYC} LUT build + {N_COMP_CYC} compute)")
    print(f"  Energy per inference   : {E_total_pj:.2f} pJ")
    print(f"  OPs per inference      : {OPS_PER_INF}")
    print(f"\n  Effective TOPs/W       : {tops_w:.2f}")
    print("=" * 56)


if __name__ == '__main__':
    main()
