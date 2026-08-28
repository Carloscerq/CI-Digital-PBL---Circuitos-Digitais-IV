#!/bin/sh
# Runs the conv2d_fsm UVM testbench (CNN convolution FSM: CHANNELS=8
# parallel MAC-based convolutions + bias + ReLU per 3x3xIN_CHANNELS
# window) with Xcelium.
#
# conv2d_fsm.sv (and conv2d_fsm_scoreboard.sv, which loads the same
# files independently to build its golden model) load weights/biases
# via $readmemh with paths relative to the simulator's CWD, not the
# source file's location -- "mem/cnn/conv2d_weights.mem" only resolves
# when the simulator is invoked from RTL/, exactly how RTL/sim_cnn.do
# already invokes this same module. So this script cd's to RTL/ first.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=conv2d_fsm_directed_random_test

cd "$(dirname "$0")/../../.." || exit 1

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top conv2d_fsm_uvm_top \
     -incdir cnn/uvm/conv2d_fsm \
     -f cnn/uvm/conv2d_fsm/conv2d_fsm_uvm.files \
     +UVM_TESTNAME=conv2d_fsm_directed_random_test \
     "$@"
