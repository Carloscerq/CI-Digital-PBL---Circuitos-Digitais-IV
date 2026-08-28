#!/bin/sh
# Runs the maxpool_2x2 UVM testbench (CNN 2x2 max-pooling unit, stride 2,
# AXI4-Stream pixel-in/pooled-pixel-out) with Xcelium.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=maxpool_2x2_directed_random_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top maxpool_2x2_uvm_top \
     -f maxpool_2x2_uvm.files \
     +UVM_TESTNAME=maxpool_2x2_directed_random_test \
     "$@"
