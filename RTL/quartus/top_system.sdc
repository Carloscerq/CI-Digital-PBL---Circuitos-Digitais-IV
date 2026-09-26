# ============================================================================
# top_system_de0cv timing constraints
# ============================================================================
# Single 50 MHz core clock off the board oscillator. Matches the 20 ns period
# the shared-FFT project closes on (RTL/FFT/model_sim_four_modes_quartus_
# shared_fft/quartus/pbl_fft_q915_no_lms_4sensor_shared.sdc).
#
# >>> PORT_NAMES_NOTE <<<
# These are the wrapper's ports, not top_system's. clk, reset, uart_rx,
# status_leds, sensor_fault_mask, alert_flag and error_status are all internal
# now; constraining them by those names would silently match nothing.
# ============================================================================

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

derive_clock_uncertainty

# ----------------------------------------------------------------------------
# Asynchronous inputs
# ----------------------------------------------------------------------------
# GPIO_1[4] is the free-running sensor stream, with no relationship to
# CLOCK_50. It is re-timed through the three-flop synchroniser in the wrapper
# and again at the head of sensor_ingestion_subsystem, so constraining the pin
# would only produce meaningless failing paths.
set_false_path -from [get_ports {GPIO_1[4]}]

# KEY[0] and SW[0] feed the reset. Unlike the old constraints -- which timed
# top_system's `reset` port as a real synchronous input -- both now pass
# through a two-flop synchroniser in the wrapper before they reach anything,
# so they are genuinely asynchronous at the pin and must not be timed.
set_false_path -from [get_ports {KEY[0]}]
set_false_path -from [get_ports {SW[0]}]

# ----------------------------------------------------------------------------
# Asynchronous outputs
# ----------------------------------------------------------------------------
# GPIO_0[4] is the telemetry line, sampled by the CP2102's own baud clock and
# not by CLOCK_50, so it is asynchronous at this boundary exactly as GPIO_1[4]
# is on the way in. Everything else is read by a human off an LED or a digit.
set_false_path -to [get_ports {GPIO_0[4]}]
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
