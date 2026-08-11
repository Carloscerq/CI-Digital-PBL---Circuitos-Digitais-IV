#!/bin/sh
# mlp_weights.h e uma copia de Scripts/export/mlp_lowband_weights.h e mlp_weights.sv sai
# dele; depois de retreinar, copie o .h de novo e rode:
#   python3 ../../Scripts/export/gen_mlp_weights_sv.py \
#           ../../Scripts/export/mlp_lowband_weights.h mlp_weights.sv

xrun -64bit -sv -timescale 1ns/1ps -access +rwc -top mlp_tb_dpi mlp_weights.sv ../perceptron/perceptron.sv mlp.sv mlp_tb_dpi.sv mlp_ref.cpp +n_vectors=2000
