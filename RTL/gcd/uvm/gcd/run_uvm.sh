#!/bin/sh
# Runs the array-reducing GCD UVM testbench (full config:
# AMOUNT_OF_NUMBERS=33, SIZE=32 -- same config gcd_tb.sv's dut_full and
# random trials use) with Xcelium.
#
#   ./run_uvm.sh                                    # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=gcd_full_random_test

cd "$(dirname "$0")/../../.." || exit 1

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top gcd_uvm_top \
     -incdir gcd/uvm/gcd \
     -f gcd/uvm/gcd/gcd_uvm.files \
     +UVM_TESTNAME=gcd_full_random_test \
     "$@"
