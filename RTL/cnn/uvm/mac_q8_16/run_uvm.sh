#!/bin/sh
# Runs the mac_q8_16 UVM testbench (CNN pipelined saturating MAC,
# DATA_WIDTH=24, FRAC_BITS=16 -- the config every CNN block instantiates)
# with Xcelium.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH        # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=mac_q8_16_default_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top mac_q8_16_uvm_top \
     -f mac_q8_16_uvm.files \
     +UVM_TESTNAME=mac_q8_16_default_test \
     "$@"
