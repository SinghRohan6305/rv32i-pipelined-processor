#!/usr/bin/env bash
# =============================================================================
# run_all_nvc.sh  —  Compile and run every testbench with the free nvc
# simulator (brew install nvc / apt install nvc).
# Usage: sim/run_all_nvc.sh            (from anywhere)
# A test passes only if it prints its "=== <name> PASS ===" line and nvc
# exits cleanly; any FAIL report or failure severity counts as a failure.
# =============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

SRC=(pkg_riscv alu regfile branch_predictor hazard_unit imem dmem control_unit pipeline_top)
for f in "${SRC[@]}"; do
    nvc --std=2008 -a "$ROOT/src/$f.vhd" || { echo "COMPILE ERROR in src/$f.vhd"; exit 1; }
done
nvc --std=2008 -a "$ROOT/tb/tb_pkg.vhd" || { echo "COMPILE ERROR in tb/tb_pkg.vhd"; exit 1; }

pass=0; fail=0; failed=()
for tb in "$ROOT"/tb/tb_*.vhd; do
    name="$(basename "$tb" .vhd)"
    [ "$name" = tb_pkg ] && continue
    out="$(nvc --std=2008 -a "$tb" -e "$name" -r --stop-time=100us 2>&1)"
    if [ $? -eq 0 ] && grep -q "=== $name PASS ===" <<<"$out" && ! grep -q "FAIL" <<<"$out"; then
        printf "  PASS  %s\n" "$name"; pass=$((pass+1))
    else
        printf "  FAIL  %s\n" "$name"; fail=$((fail+1)); failed+=("$name")
        grep -E "FAIL|Error|Fatal" <<<"$out" | head -10 | sed 's/^/        /'
    fi
done

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
