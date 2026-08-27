create_clock -name clk -period 20.000 [get_ports {clk}]

set core_inputs [get_ports {
    reset
    sensor1_sample[*]
    sensor2_sample[*]
    sensor3_sample[*]
    sensor4_sample[*]
    sample_valid
    fft_ready
}]

set_input_delay \
    -clock [get_clocks {clk}] \
    -max 0.000 \
    $core_inputs

set_input_delay \
    -clock [get_clocks {clk}] \
    -min 0.000 \
    $core_inputs

set_output_delay \
    -clock [get_clocks {clk}] \
    -max 0.000 \
    [all_outputs]

set_output_delay \
    -clock [get_clocks {clk}] \
    -min 0.000 \
    [all_outputs]
