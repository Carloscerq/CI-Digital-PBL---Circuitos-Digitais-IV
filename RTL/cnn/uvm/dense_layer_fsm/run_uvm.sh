#!/bin/sh
# Runs the dense_layer_fsm UVM testbench (CNN dense/fully-connected
# output layer FSM: OUT_CLASSES=4 parallel MAC-based dot products + bias
# per 256x8 pixel frame) with Xcelium.
#
# dense_layer_fsm.sv (and dense_layer_fsm_scoreboard.sv, which loads the
# same files independently to build its golden model) load weights/
# biases via $readmemh with paths relative to the simulator's CWD, not
# the source file's location -- "mem/cnn/dense_weights.mem" only
# resolves when the simulator is invoked from RTL/. So this script cd's
# to RTL/ first.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=dense_layer_fsm_directed_random_test

cd "$(dirname "$0")/../../.." || exit 1

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top dense_layer_fsm_uvm_top \
     -incdir cnn/uvm/dense_layer_fsm \
     -f cnn/uvm/dense_layer_fsm/dense_layer_fsm_uvm.files \
     +UVM_TESTNAME=dense_layer_fsm_directed_random_test \
     "$@"
