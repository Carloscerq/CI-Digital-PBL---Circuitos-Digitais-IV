# ============================================================================
# uart_loopback timing constraints
# ============================================================================
# One 50 MHz clock straight off the board oscillator (PIN_M9). Nothing in this
# design is deep enough to be interesting to the fitter; the constraints exist
# so the STA report is trustworthy rather than empty.
# ============================================================================

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

derive_clock_uncertainty

# ----------------------------------------------------------------------------
# Asynchronous inputs
# ----------------------------------------------------------------------------
# GPIO_1[4] is a free-running serial line with no relationship to CLOCK_50: it
# is re-timed through the three-flop synchroniser in uart_loopback_top, so
# constraining the pin would only produce meaningless failing paths. The keys
# and switches are mechanical and go through the same treatment.
set_false_path -from [get_ports {GPIO_1[4]}]
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]

# ----------------------------------------------------------------------------
# Asynchronous outputs
# ----------------------------------------------------------------------------
# GPIO_0[4] is sampled by the adapter's own baud clock, not by CLOCK_50, so it
# is asynchronous at this boundary the same way GPIO_1[4] is. The LEDs and
# 7-segment displays are read by humans.
set_false_path -to [get_ports {GPIO_0[4]}]
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
