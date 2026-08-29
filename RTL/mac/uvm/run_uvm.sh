#!/bin/sh
# Runs the mac UVM testbench (wide config: DATA_WIDTH=24, WEIGHT_WIDTH=8,
# SUM_WIDTH=40 -- the config mlp.sv instantiates) with Xcelium.
#
#   ./run_uvm.sh                                  # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH           # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=mac_protocol_test   # HOLD / ASYNC_RESET checks

cd "$(dirname "$0")/../../.." || exit 1

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top mac_uvm_top \
     -incdir RTL/mac/uvm \
     -f RTL/mac/uvm/mac_uvm_wide.files \
     +UVM_TESTNAME=mac_wide_random_test \
     "$@"
