#!/bin/sh
# Runs the filtro_lms UVM testbench (MU left at its default, 24'sd1638)
# with Xcelium.
#
#   ./run_uvm.sh                                     # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH              # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=filtro_lms_regression_test

cd "$(dirname "$0")/../../.." || exit 1

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top filtro_lms_uvm_top \
     -incdir RTL/LMS/uvm \
     -f RTL/LMS/uvm/filtro_lms_uvm.files \
     +UVM_TESTNAME=filtro_lms_regression_test \
     "$@"