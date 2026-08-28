#!/bin/sh
# Runs the SPI UVM testbench (SIZE=8, N_SLAVES=2: slave 0 mode 0
# CLK_DIV=4, slave 1 mode 3 CLK_DIV=6, same as spi_controller_tb.sv) with
# Xcelium.
#
#   ./run_uvm.sh                                  # default test
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH           # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=spi_directed_test

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top spi_uvm_top \
     -f spi_uvm.files \
     +UVM_TESTNAME=spi_directed_test \
     "$@"
