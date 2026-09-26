# Diagnostic project: one 50 MHz clock, every I/O asynchronous by nature.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

set_false_path -from [get_ports *]
set_false_path -to   [get_ports *]
