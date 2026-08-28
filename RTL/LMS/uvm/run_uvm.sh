#!/bin/sh
# Runs the filtro_lms UVM testbench (MU left at its default, 24'sd1638)
# with Xcelium.
#
#   ./run_uvm.sh                                     # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH              # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=filtro_lms_regression_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top filtro_lms_uvm_top \
     -f filtro_lms_uvm.files \
     +UVM_TESTNAME=filtro_lms_regression_test \
     "$@"
