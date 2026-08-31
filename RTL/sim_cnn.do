vlib work
vmap work work

# Compile RTL modules
vlog -sv cnn/rtl/mac_q8_16.sv
vlog -sv cnn/rtl/line_buffer_3x3.sv
vlog -sv cnn/rtl/conv2d_fsm.sv
vlog -sv cnn/rtl/maxpool_2x2.sv
vlog -sv cnn/rtl/dense_layer_fsm.sv
vlog -sv cnn/rtl/cnn_top.sv

# Compile Testbenches
vlog -sv cnn/tb/tb_mac_q8_16.sv
vlog -sv cnn/tb/tb_line_buffer_3x3.sv
vlog -sv cnn/tb/tb_conv2d_fsm.sv
vlog -sv cnn/tb/tb_maxpool_2x2.sv
vlog -sv cnn/tb/tb_dense_layer_fsm.sv
vlog -sv cnn/tb/tb_cnn_top.sv

echo "======================================================"
echo "Compilation Complete."
echo "To run MAC test:         vsim -c tb_mac_q8_16 -do \"run -all;\""
echo "To run Line Buffer test: vsim -c tb_line_buffer_3x3 -do \"run -all;\""
echo "To run Conv2D test:      vsim -c tb_conv2d_fsm -do \"run -all;\""
echo "To run MaxPool test:     vsim -c tb_maxpool_2x2 -do \"run -all;\""
echo "To run Dense test:       vsim -c tb_dense_layer_fsm -do \"run -all;\""
echo "To run Top CNN test:     vsim -c tb_cnn_top -do \"run -all;\""
echo "======================================================"

quit
