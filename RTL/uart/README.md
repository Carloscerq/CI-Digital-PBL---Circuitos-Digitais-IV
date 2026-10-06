# UART loopback — USB link bring-up

`uart_loopback_top` echoes every byte the host sends back to the host. It is
the smallest design that exercises the whole USB-serial path and nothing else,
so when it works the link is proven, and when it does not the fault is in the
cable, the pins, the baud rate or the adapter — never in the DSP or inference
chain, none of which is instantiated.

```
host /dev/ttyUSB0 ─▶ adapter TX ─▶ GPIO_1[4] ─▶ receiver ─▶ elastic_fifo
                                                                  │
host /dev/ttyUSB0 ◀─ adapter RX ◀─ GPIO_0[4] ◀─ transmitter ◀─────╯
```

```
RTL/uart/
  rtl/uart_loopback_top.sv        the design
  tb/tb_uart_loopback.sv          self-checking testbench
  tb/run_tb_uart_loopback.sh      build + run (Verilator or Questa)
RTL/quartus_uart_loopback/        its own Quartus project, with real pins
Scripts/fpga_host/uart_loopback_test.py    host-side test over pyserial
```

## Wiring

A 3.3 V USB-serial adapter, with the pair split across both GPIO headers:

| Adapter | FPGA port   | Pin       | Header      |
|---------|-------------|-----------|-------------|
| TX      | `GPIO_1[4]` | `PIN_A13` | JP2, pin 5  |
| RX      | `GPIO_0[4]` | `PIN_D17` | JP1, pin 5  |
| GND     | —           | —         | JP1, pin 12 |

TX goes to the FPGA's **RX** and vice versa; wiring TX to TX is the usual
reason a loopback stays silent. A common ground is required — either header's
GND will do, but with the pair split across JP1 and JP2 it is easy to ground
neither. The DE0-CV GPIO banks are 3.3-V LVTTL and are **not** 5 V tolerant.

The serial ports are declared as one-bit vectors indexed at 4, so the port
names are literally `GPIO_1[4]` and `GPIO_0[4]` and the location assignments
in `uart_loopback.qsf` are the board template's own lines, unchanged.

## Controls

| Control  | Meaning |
|----------|---------|
| `KEY[0]` | reset (active low). Not needed at power-up — see the power-on reset below. |
| `KEY[1]` | queue `UART OK\r\n`, with no receive traffic required |
| `SW[0]`  | `0` echo the byte, `1` echo its bitwise complement |
| `LEDR[7:0]` | last byte received |
| `LEDR[8]`   | FIFO overrun, sticky: bytes were genuinely lost |
| `LEDR[9]`   | blinks with receive traffic (~50 ms stretch) |
| `HEX1 HEX0` | last byte received, in hex |
| `HEX3 HEX2` | received-byte count, low byte, in hex |

Two details of the design are worth knowing before you trust a result:

**The complement mode is the test that counts.** A jumper across the adapter's
own TX and RX echoes bytes perfectly, so a byte-for-byte pass does not by
itself prove the FPGA is in the path. Only this design can return `~byte`.

**`KEY[1]` splits a dead link in half.** The banner needs nothing on the
receive side, so if it arrives, FPGA transmit + `GPIO_0[4]` + the cable + the
adapter's receiver all work, and the fault is in the other direction.

## Running the testbench

```bash
cd RTL/uart/tb
./run_tb_uart_loopback.sh                  # seconds, fast baud divisor
./run_tb_uart_loopback.sh --baud 115200    # the divisor the board uses
./run_tb_uart_loopback.sh --vsim --trace   # Questa, with waves
```

Both baud rates pass 98 checks: idle-line behaviour, edge-case bytes, the
complement mode, a 64-byte gapless burst echoed in order with no overrun, the
`KEY[1]` banner, and recovery from a reset landing mid-frame.

## Building and programming

```bash
export PATH=$HOME/altera_lite/25.1std/quartus/bin:$PATH
cd RTL/quartus_uart_loopback
quartus_sh --flow compile uart_loopback
quartus_pgm -m jtag -o "p;output_files/uart_loopback.sof"
```

167 ALMs, 238 registers, one M10K for the FIFO; 14.8 ns of setup slack against
the 20 ns period, fully constrained for setup and hold.

## Testing from the host

```bash
cd Scripts/fpga_host
python3 uart_loopback_test.py                      # liveness, edge vectors,
                                                   # all 256 values, throughput
python3 uart_loopback_test.py --invert             # with SW[0] raised
python3 uart_loopback_test.py --banner             # then press KEY[1]
python3 uart_loopback_test.py --bytes 65536        # longer sustained run
```

It exits non-zero on any failure, and when nothing at all comes back it prints
a checklist ordered by how often each cause is the real one.

## When the link is silent: `uart_pin_scout`

`RTL/quartus_uart_scout/` builds a diagnostic bitstream that replaces
guess-and-recompile with one measurement. Program it and open the port:

- **Transmit** — `GPIO_0[4]` (D17), `GPIO_0[10]` (N21) and `GPIO_0[1]` (B16)
  each beacon `TX=<name> RX=xx\r\n` continuously at 115200. Whichever beacon
  reaches the host names the pin wired to the adapter's RX.
- **Receive** — every other GPIO pin listens with a weak pull-up, so an
  unconnected pin reads high. Send bytes from the host; the pin carrying them
  is latched and shown as `xx` above, on `HEX1 HEX0`, and on `LEDR[6:0]`.
  `LEDR[9]` means a pin qualified; `LEDR[8]` means some pin was low at all.
  `KEY[0]` clears the latch.

Index encoding: `00`–`23` are `GPIO_0[0..35]`, `24`–`47` are `GPIO_1[0..35]`;
`--` means nothing detected.

A pin qualifies only after 15 falling edges, so a floating pin that glitches
once cannot latch first and mask the real one. The cost of that choice is that
a pin held *permanently* low — a ground wire in a signal hole — produces no
edges and reads `--`; `LEDR[8]` is what catches that case.

**Rule out the adapter first.** Bridge the module's own `TXD` and `RXD` pins
directly, with no jumper wires in the loop, and run
`uart_loopback_test.py`. If that fails, nothing on the FPGA side can help —
and if it passes while the same test through your jumper wires fails, a wire
is broken. That is a two-minute check that beats any amount of RTL work.

## Why this project is separate from `RTL/quartus`

`RTL/quartus/quartus.qsf` carries the DE0-CV board pin table but assigns none
of it to `top_system`'s actual ports. The fitter therefore placed them freely:
`output_files/quartus.pin` from the last build shows `uart_rx` on `H14`
(`GPIO_1[16]`) and `clk` on `M16` — `GPIO_0[2]`, not the 50 MHz oscillator on
`PIN_M9`. Keeping the loopback in its own project means it can be programmed
and trusted without disturbing that one, and the pin table in
`uart_loopback.qsf` is the reference for fixing it:

```tcl
set_location_assignment PIN_M9  -to clk        ;# 50 MHz oscillator
set_location_assignment PIN_A13 -to uart_rx    ;# GPIO_1[4], JP2 pin 5
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to uart_rx
```

## Notes on the design

**Power-on reset.** Cyclone V registers leave configuration cleared, which for
`transmitter.sv` means `tx = 0` — a held break on the line until something
asserts `rst`. A counter lifts reset ~20 µs after configuration so the board
works the moment it is programmed, with no button press. `KEY[0]` is a manual
reset on top of that.

**Throughput.** `transmitter.sv` leaves `TX_STATE_IDLE` on the clock edge after
`tx_en` goes low and only then waits for `tx_clk_en`, so holding `tx_en` low
while the FIFO is non-empty sustains one byte every 10 bit periods — the same
rate the receiver delivers them. The FIFO covers the one-byte handover latency
and host bursts, not a rate mismatch, and `LEDR[8]` means bytes were lost.

**`tx_en` and `rx_en` are active low** in this UART core. See the conversion
notes at the top of `transmitter.sv` and `receiver.sv`.
