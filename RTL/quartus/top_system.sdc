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
# uart_rx is a free-running serial line with no relationship to clk. It is
# re-timed through the three-flop synchroniser at the head of
# sensor_ingestion_subsystem, so constraining the pin would only produce
# meaningless failing paths.
#
# The four SPI pins that used to be constrained here were removed along with
# spi_sensor_frame_rx when the link moved to UART; the constraints outlived the
# ports and referenced signals that no longer exist.
set_false_path -from [get_ports {uart_rx}]

# ----------------------------------------------------------------------------
# Synchronous reset
# ----------------------------------------------------------------------------
# reset is a SYNCHRONOUS, active-high reset: every register samples it on
# posedge clk, so unlike uart_rx it is a real timed path and must NOT be
# false-pathed. The numbers below assume the pin is driven from a source
# already in the clk domain with a small board-level delay -- adjust to match
# whatever actually drives it (a free-running button needs a synchroniser in
# top_system instead).
set_input_delay -clock clk -max 2.000 [get_ports {reset}]
set_input_delay -clock clk -min 0.000 [get_ports {reset}]

# ----------------------------------------------------------------------------
# Asynchronous outputs
# ----------------------------------------------------------------------------
# LEDs and status pins are read by humans or resampled by whatever watches
# them; none of them is a synchronous interface.
set_false_path -to [get_ports {status_leds[*]}]
set_false_path -to [get_ports {sensor_fault_mask[*]}]
set_false_path -to [get_ports {alert_flag}]
set_false_path -to [get_ports {error_status[*]}]
