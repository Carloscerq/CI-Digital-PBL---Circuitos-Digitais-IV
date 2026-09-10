#!/bin/sh
# Runs the cnn_top UVM testbench (CNN top-level integration: the
# full line_buffer_3x3 -> conv2d_fsm -> maxpool_2x2 -> dense_layer_fsm
# chain) with Xcelium.
#
# Must run with CWD=RTL/: BOTH the conv2d/dense weight ROMs
# ($readmemh("mem/cnn/...")  inside conv2d_fsm.sv/dense_layer_fsm.sv)
# AND the directed sequence's real spectrogram frame
# ($readmemh("../Scripts/cnn/cnn_tb_input.mem") in cnn_top_sequences.sv)
# resolve their relative paths against that directory -- so this script
# cd's there first regardless of where it's invoked from.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=cnn_top_directed_random_test

cd "$(dirname "$0")/../../.."

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -incdir cnn/uvm/cnn_top \
     -top cnn_top_uvm_top \
     -f cnn/uvm/cnn_top/cnn_top_uvm.files \
     +UVM_TESTNAME=cnn_top_directed_random_test \
     "$@"
