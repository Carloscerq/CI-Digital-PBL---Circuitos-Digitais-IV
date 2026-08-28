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

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top mlp_uvm_top \
     -f mlp_uvm.files \
     ../mlp_ref.cpp \
     +UVM_TESTNAME=mlp_directed_random_test \
     "$@"
