#!/bin/sh

xrun -64bit -sv -timescale 1ns/1ps -access +rwc -top mlp_tb_dpi mlp_weights.sv ../perceptron/perceptron.sv mlp.sv mlp_tb_dpi.sv mlp_ref.cpp +n_vectors=2000
