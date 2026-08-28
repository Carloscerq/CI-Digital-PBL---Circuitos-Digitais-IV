#!/bin/sh
# Runs the perceptron UVM testbench (layer-0 config: 40 inputs, 24-bit,
# ReLU on, uniform weight=127, SCALE=883) with Xcelium.
#
#   ./run_uvm.sh                                    # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=perceptron_wide_random_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top perceptron_uvm_top \
     -f perceptron_uvm_wide.files \
     +UVM_TESTNAME=perceptron_wide_random_test \
     "$@"
