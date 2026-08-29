# ============================================================================
# top_system timing constraints
# ============================================================================
# Single 50 MHz core clock. Matches the 20 ns period the shared-FFT project
# closes on (RTL/FFT/model_sim_four_modes_quartus_shared_fft/quartus/
# pbl_fft_q915_no_lms_4sensor_shared.sdc).
# ============================================================================

create_clock -name clk -period 20.000 [get_ports {clk}]

derive_clock_uncertainty

# ----------------------------------------------------------------------------
# Asynchronous inputs
# ----------------------------------------------------------------------------
# spi_slave re-times serial_clock, slave_select_n and the MOSI line through
# two/three flop synchronisers, so these pins have no timing relationship to
# clk. Constraining them would only produce meaningless failing paths.
set_false_path -from [get_ports {spi_serial_clock}]
set_false_path -from [get_ports {spi_slave_select_n}]
set_false_path -from [get_ports {spi_mosi}]

# ----------------------------------------------------------------------------
# Synchronous reset
# ----------------------------------------------------------------------------
# reset is a SYNCHRONOUS, active-high reset: every register samples it on
# posedge clk, so unlike the SPI pins it is a real timed path and must NOT be
# false-pathed. The numbers below assume the pin is driven from a source
# already in the clk domain with a small board-level delay -- adjust to match
# whatever actually drives it (a free-running button needs a synchroniser in
# top_system instead).
set_input_delay -clock clk -max 2.000 [get_ports {reset}]
set_input_delay -clock clk -min 0.000 [get_ports {reset}]

# ----------------------------------------------------------------------------
# Asynchronous outputs
# ----------------------------------------------------------------------------
# LEDs / status pins and the SPI return line are read by humans or by a master
# that resamples them; none of them is a synchronous interface.
set_false_path -to [get_ports {spi_miso}]
set_false_path -to [get_ports {status_leds[*]}]
set_false_path -to [get_ports {sensor_fault_mask[*]}]
set_false_path -to [get_ports {alert_flag}]
set_false_path -to [get_ports {sys_error}]
