#!/bin/sh
# Runs the line_buffer_3x3 UVM testbench (CNN sliding-window / line-buffer
# generator, a genuine dual AXI4-Stream pixel-in/window-out pair) with
# Xcelium.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=line_buffer_3x3_directed_random_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top line_buffer_3x3_uvm_top \
     -f line_buffer_3x3_uvm.files \
     +UVM_TESTNAME=line_buffer_3x3_directed_random_test \
     "$@"
