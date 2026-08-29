#!/usr/bin/env bash
# Runs the mac_q8_16 (CNN saturating MAC, DATA_WIDTH=24, FRAC_BITS=16) UVM testbench with Questa/ModelSim (vsim).
# Same DUT config, top module (mac_q8_16_uvm_top) and default test as run_uvm.sh,
# which drives Xcelium instead.
#
#   ./run_uvm_vsim.sh                                # default test
#   ./run_uvm_vsim.sh +UVM_VERBOSITY=UVM_HIGH        # per-item logging
#   ./run_uvm_vsim.sh +UVM_TESTNAME=mac_q8_16_default_test
#   ./run_uvm_vsim.sh --gui                          # interactive, waves kept
#
# All work happens in RTL/sim_vsim/ (log: RTL/sim_vsim/cnn_mac_q8_16.log).
set -uo pipefail

# Walk up to RTL/ to find the shared runner, so this works from any cwd.
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
while [ "$dir" != "/" ] && [ ! -x "$dir/scripts/uvm_vsim.sh" ]; do dir=$(dirname -- "$dir"); done
[ -x "$dir/scripts/uvm_vsim.sh" ] || { echo "cannot find RTL/scripts/uvm_vsim.sh" >&2; exit 2; }

exec "$dir/scripts/uvm_vsim.sh" cnn_mac_q8_16 "$@"
