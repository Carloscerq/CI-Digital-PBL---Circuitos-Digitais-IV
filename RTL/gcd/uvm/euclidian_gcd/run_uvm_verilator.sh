#!/usr/bin/env bash
# Runs the euclidian_gcd UVM testbench with Verilator (open source, no licence needed).
# Same DUT config, top module and default test as run_uvm.sh (Xcelium) and
# run_uvm_vsim.sh (Questa), so the bench behaves identically under all three.
#
#   ./run_uvm_verilator.sh                            # default test
#   ./run_uvm_verilator.sh +UVM_VERBOSITY=UVM_HIGH    # per-item logging
#   ./run_uvm_verilator.sh +UVM_TESTNAME=euclidian_gcd_random_test
#   ./run_uvm_verilator.sh --trace                    # FST waves for gtkwave
#   ./run_uvm_verilator.sh --build-only               # verilate + compile only
#
# All work happens in RTL/sim_verilator/ (log: RTL/sim_verilator/euclidian_gcd.log).
# The first build compiles all of UVM (~2 min); with ccache the rest is quick.
set -uo pipefail

# Walk up to RTL/ to find the shared runner, so this works from any cwd.
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
while [ "$dir" != "/" ] && [ ! -x "$dir/scripts/uvm_verilator.sh" ]; do dir=$(dirname -- "$dir"); done
[ -x "$dir/scripts/uvm_verilator.sh" ] || { echo "cannot find RTL/scripts/uvm_verilator.sh" >&2; exit 2; }

exec "$dir/scripts/uvm_verilator.sh" euclidian_gcd "$@"
