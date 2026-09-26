# FPGA host drivers

Host-side scripts that feed `top_system` its sensor stream over the UART pin,
built from the quantised captures in `Scripts/process_dataset/dataset_q915`.

| file | what it does |
| --- | --- |
| `stream_scenario.py` | one scenario, looped forever |
| `run_schedule.py` | one scenario, or a timed sequence of them, looped or shuffled, with live commands |
| `fpga_uart_link.py` | everything they share: frame format, aux aggregation, serial sink, pacing, logging |
| `bench_example.txt` | a sample schedule file |

Both scripts run until you type `q` + Enter, press Ctrl+C, or close the
terminal. Every event goes to the console and to `logs/fpga_uart_<timestamp>.log`.

```
pip install pyserial numpy          # or use Scripts/.env, which already has both
./stream_scenario.py --list
./stream_scenario.py --scenario 0Nm_BPFI_10 --port /dev/ttyUSB0
./run_schedule.py --schedule "0Nm_BPFI_10:300,2Nm_Normal:300,4Nm_Unbalance_1751mg:300"
./run_schedule.py --schedule-file bench_example.txt --shuffle
./run_schedule.py --scenario 0Nm_Normal --dry-run --max-seconds 10      # no hardware
```

## What goes down the wire

`uart_sensor_frame_rx.sv` wants 24-byte frames at 8N1, LSB first, idle high:

```
A5 5A | w0 w1 w2 w3 w4 w5 w6 (3 bytes each, MSB first) | XOR of the 21 payload bytes

w0..w3  vibration sensors 1..4          raw Q9.15 samples, one per frame
w4      current, U-phase                mean(x*x) over a block, x 2^9
w5      temperature, housing A          mean(x)   over a block, x 2^9
w6      temperature, housing B          mean(x)   over a block, x 2^9
```

The chosen scenario supplies **all seven** words -- its four vibration
captures, its U-phase current capture and its two temperature captures --
and each capture wraps around on its own when it runs out, so the stream is
endless.

The three aux words are not raw samples. The MLP was trained on block
aggregates the host had already scaled by 2^9 (derivation in
`tb_top_system.sv`, `AUX_SCALE_NOTE`); `AuxAggregator` reproduces that
arithmetic exactly, including the warm-up prefix and the per-block hold. A
block is `DECIM_RATE x FFT_HOP` frames, read from `system_types_pkg.sv` so
the host tracks the build (`--agg-span` overrides it for a bench FPGA built
from something else).

Five scenarios (`2Nm_Unbalalnce_*`) have vibration captures only. They still
stream, with the aux words held at fallback constants (6.0 A^2, 28 C, 29 C --
the same values the testbench uses); the log says so and their MLP verdict
is not meaningful.

## Rate and cadence

At 115200 baud a frame takes 2.083 ms, so the wire carries **480 frames/s**.
With `DECIM_RATE = 32` and `FFT_HOP = 64` the fabric consumes 2048 frames per
MLP verdict and 65,536 per CNN verdict:

| | frames | at 115200 baud |
| --- | --- | --- |
| one MLP verdict | 2,048 | every 4.3 s |
| one CNN verdict | 65,536 | every 136.5 s |

Give a scheduled scenario at least ~140 s if you want a CNN verdict from it
rather than only the MLP's. `--frame-rate` slows the stream below the wire
rate; there is no way to go faster than the baud allows.

Scenario changes are applied on an MLP round boundary so no FFT frame
straddles two machines (`--no-align` switches immediately). Between frames
the fabric simply waits -- the receiver's idle timeout only counts inside a
frame, and the host never splits one -- so `pause` is safe for as long as you
like.

## What you can and cannot see

`top_system` has no UART transmitter. Its verdicts are on `status_leds`,
`sensor_fault_mask`, `alert_flag` and the sticky `error_status` bits, so the
script cannot read a result back. What it logs instead is enough to line the
pins up against: the running frame count, the number of MLP and CNN
verdicts that count implies (`MLP~n CNN~n` in every status line), the exact
moment each scenario switch was applied, and the aux words in physical
units with a warning when they leave the range the MLP was trained on.

If a result channel is ever wanted, `RTL/uart/rtl/transmitter.sv` already
exists; wiring the arbiter's verdict into it would let this script log
verdicts against frames.

## Live commands

```
q | quit | exit        stop
s | status             status line now
p | pause              stop sending; r | resume continues
switch <name> [s]      jump to a scenario (run_schedule: for s seconds, then resume the plan)
next                   advance the schedule now
hold | release         freeze / unfreeze the automatic advance
list                   scenarios on disk
plan                   the schedule and where we are in it
help                   this list
```

## Checks before a bench run

- `--baud` must equal `top_system`'s `BAUD_RATE` (115200 in `top_system.sv`).
- The FPGA must be built from the same `DECIM_RATE`/`FFT_HOP` the script
  reads from `system_types_pkg.sv`, or pass `--agg-span`. Getting this wrong
  only changes how often the aux words refresh, not their values.
- `error_status[0]` (`ERR_UART_FRAME`) staying clear on the board is the
  end-to-end proof that framing, byte order and checksum are right.
