#!/bin/sh
# Runs the preprocess_lms_fft_four_modes UVM testbench (the FFT
# preprocessing pipeline's top-level module: fir_decimator_32_dualmode
# -> [lms_filter_8tap_dualmode, not instantiated at USE_LMS=0] ->
# sample_buffer_64_hop_dualmode -> mean_remover_64_dualmode ->
# hann_window_64_dualmode -> fft_64_dualmode), fixed at USE_LMS=0, with
# Xcelium.
#
# Must run with CWD=RTL/FFT: the FIR/Hann coefficient ROMs' $readmemh
# calls (inside fir_coeff_rom_dualmode.v / hann_window_64_dualmode.v)
# use the DUT's own default INIT_FILE parameter values, e.g.
# "model_sim_four_modes/coefficients/fir/stage1_decim4_q117.hex" --
# resolved relative to the simulator's CWD at runtime, not compile
# time. That is exactly the convention
# ../../verification/run_four_modes_xcelium.sh uses: it computes
# project_root=$(cd "$script_dir/../.." && pwd), which -- since that
# script lives in model_sim_four_modes/verification/ -- resolves to
# RTL/FFT, then `cd`s there before invoking xrun. This script does the
# same (cd's from model_sim_four_modes/uvm/ up two levels to RTL/FFT)
# regardless of where it's invoked from.
#
#   ./run_uvm.sh
#   ./run_uvm.sh +UVM_VERBOSITY=UVM_HIGH             # per-item logging
#   ./run_uvm.sh +UVM_TESTNAME=preprocess_lms_fft_directed_test

cd "$(dirname "$0")/../.."

xrun -64bit -sv -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc \
     -incdir model_sim_four_modes/uvm \
     -top preprocess_lms_fft_uvm_top \
     -f model_sim_four_modes/uvm/preprocess_lms_fft_uvm.files \
     +UVM_TESTNAME=preprocess_lms_fft_directed_test \
     "$@"
