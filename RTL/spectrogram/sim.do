# Compile Spectrogram Module and Testbench
vlib work
vlog -sv rtl/spectrogram_generator.sv
vlog -sv tb/tb_spectrogram_generator.sv

echo "======================================================"
echo "Compilation Complete."
echo "To run Spectrogram test: vsim -c -do 'run -all; quit' tb_spectrogram_generator"
echo "======================================================"
