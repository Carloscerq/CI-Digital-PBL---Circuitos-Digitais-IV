#!/usr/bin/env bash
# Builds and runs the self-checking matrix_inv_tb with Verilator (no UVM,
# no licence). The bench exits non-zero on any mismatch.
#
#   ./run_tests.sh             # build + run
#   ./run_tests.sh +seed=...   # extra args go to the simulation binary
#
# With a commercial simulator the same file list works as is, e.g.
#   xrun -sv -timescale 1ns/1ps -top matrix_inv_tb -f matrix_inv_test.files
#
# Build output goes to RTL/sim_verilator/obj_matrix_inv_tb/.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
obj=$here/../sim_verilator/obj_matrix_inv_tb
mkdir -p "$obj"

cd "$here"
verilator --binary -j "$(nproc 2>/dev/null || echo 4)" --timing --assert -sv \
    --timescale 1ns/1ps -Wno-fatal -Wno-WIDTH -Wno-UNUSED \
    --Mdir "$obj" -o Vmatrix_inv_tb --top-module matrix_inv_tb \
    -f matrix_inv_test.files > "$obj/build.log" 2>&1 \
    || { grep -E '^%Error' "$obj/build.log" | head -20; exit 1; }

"$obj/Vmatrix_inv_tb" "$@"
