#!/bin/sh
# Runs the MLP UVM testbench (time-multiplexed 132->8->4->4 inference
# engine) against the bit-exact C++ reference (mlp_ref.cpp) via DPI-C,
# with Xcelium. mlp_ref.cpp is passed directly on the command line
# rather than through -f mlp_uvm.files since it's a C++ source, not
# SystemVerilog -- same as run_tests.sh does for the non-UVM tb.
#
#   ./run_uvm.sh                                    # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=mlp_directed_random_test
#   ./run_uvm.sh -elaborate                          # build only, no sim
#
# Two-step (elaborate, then -R) on purpose -- the compile and the run
# need different working directories and there is no single one that
# satisfies both:
#
#   * elaborate must run from this uvm/ directory: xrun resolves the
#     paths in mlp_uvm.files ("../mlp.sv", "tb/mlp_uvm_top.sv", ...)
#     relative to the CWD, not to the .files file.
#
#   * the run must happen one level up, in mlp_model/: mlp.sv loads its
#     weight/bias/scale ROMs with $readmemh("../mem/mlp/mlp_weights.mem")
#     etc. (parameter defaults), and "../mem/mlp/" only resolves to
#     RTL/mem/mlp/ from a directory exactly one level below RTL/. Run the
#     sim anywhere else and $readmemh silently loads zeros -- every logit
#     comes out 0 and the scoreboard reports a mismatch on every vector.
#
# Extra arguments are forwarded to both xrun invocations, so +plusargs,
# -xmlibdirname, a later +UVM_TESTNAME override etc. all work.
set -e

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)   # RTL/mlp_model/uvm
model=$(CDPATH= cd -- "$here/.." && pwd)            # RTL/mlp_model
test=mlp_directed_random_test

# Stop after elaboration if the caller asked for a build-only run.
build_only=0
for a in "$@"; do
    case "$a" in
        -elaborate|-elab|-compile|-c|--elaborate|--compile-only) build_only=1 ;;
    esac
done

# --- elaborate (from uvm/) -------------------------------------------------
cd "$here"
xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -elaborate \
     -top mlp_uvm_top \
     -f mlp_uvm.files \
     ../mlp_ref.cpp \
     +UVM_TESTNAME=$test \
     "$@"

[ "$build_only" -eq 1 ] && exit 0

# --- simulate (from mlp_model/, so ../mem/mlp/*.mem resolves) -------------
cd "$model"
exec xrun -R +UVM_TESTNAME=$test "$@"
