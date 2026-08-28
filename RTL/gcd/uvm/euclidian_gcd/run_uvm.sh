#!/bin/sh
# Runs the euclidian_gcd UVM testbench (SIZE=32, the pairwise subtraction-
# based GCD block gcd.sv's array reducer instantiates) with Xcelium.
#
#   ./run_uvm.sh                                    # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=euclidian_gcd_random_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top euclidian_gcd_uvm_top \
     -f euclidian_gcd_uvm.files \
     +UVM_TESTNAME=euclidian_gcd_random_test \
     "$@"
