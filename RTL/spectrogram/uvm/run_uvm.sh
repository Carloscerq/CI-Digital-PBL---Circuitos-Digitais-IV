#!/bin/sh
# Runs the spectrogram_generator UVM testbench (ping-pong double buffer,
# DATA_WIDTH=24/BINS_PER_FRAME=32/FRAMES_PER_SPECTROGRAM=32,
# MEM_DEPTH=1024) with Xcelium.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH   # per-word logging

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -top spectrogram_generator_uvm_top \
     -f spectrogram_generator_uvm.files \
     +UVM_TESTNAME=spectrogram_generator_directed_random_test \
     "$@"
