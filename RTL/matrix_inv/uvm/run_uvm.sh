#!/bin/sh
# Runs the matrix_inv UVM testbench (Gauss-Jordan inverter, N_MAX=4,
# Q9.15) with Xcelium.
#
#   ./run_uvm.sh                                    # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-matrix logging
#   ./run_uvm.sh +UVM_TESTNAME=matrix_inv_directed_test

cd "$(dirname "$0")/../.." || exit 1

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top matrix_inv_uvm_top \
     -incdir matrix_inv/uvm \
     -f matrix_inv/uvm/matrix_inv_uvm.files \
     +UVM_TESTNAME=matrix_inv_random_test \
     "$@"
