# RTL — technical guide

Everything synthesisable lives here. This document covers **how the tree is
organised, what `top_system` does, and how the subsystems are wired
together**. Individual subsystems are treated as black boxes with defined
interfaces; per-module READMEs can be added under each directory later.

---

## 1. Directory map

| Path | Contents | In the build? |
|---|---|---|
| `quartus/` | The Quartus project: `quartus.qpf`, `quartus.qsf`, `top_system.sdc` | — |
| `top_system/` | Top level and all inter-subsystem glue | yes |
| `FFT/model_sim_four_modes_quartus_shared_fft/` | **Active** front-end: FIR decimator → frame buffer → mean removal → Hann → shared FFT | yes |
| `FFT/model_sim_four_modes/`, `FFT/model_sim_four_modes_quartus/` | Older single-channel variants, kept for reference and simulation | no |
| `cnn/rtl/` | `smma_cnn_top` and its layers (line buffer, conv2d, maxpool, dense) | yes |
| `cnn/tb/`, `spectrogram/tb/` | Testbenches | no |
| `mlp_model/` | `mlp.sv` + `mlp_weights_pkg` (dimensions and ROM address map) | yes |
| `spectrogram/rtl/` | `spectrogram_generator` — ping-pong M10K buffer | yes |
| `spi/` | `spi_slave` and `spi_controller`. Both compile; only the slave is instantiated (the master is bench-side) | yes |
| `mem/cnn/`, `mem/mlp/` | `.mem` weight read by `$readmemh` | data |
| `mac/` | `mac` — the multiply-accumulate cell the MLP instantiates | yes |
| `gcd/`, `perceptron/`, `LMS/` | Standalone exercises. `perceptron` is superseded by the time-multiplexed `mlp`; `LMS` is not in the project file | not instantiated |
| `work/` | ModelSim/Questa library — build artefact, gitignored | — |

The `.qsf` is the authoritative file list. Compile order matters in one
place: **`mlp_weights.sv` must precede `mlp.sv` and
`fft_to_mlp_collector.sv`**, which both `import mlp_weights_pkg::*`.

## 2. Conventions

**Handshake.** Every streaming port uses the same plain contract: a beat
transfers when `valid` and `ready` are both high on a rising clock edge, and
`last` marks the final beat of a frame. Ports are named `s_*` on the
slave (consuming) side and `m_*` on the master (producing) side. There is no
sideband, no address phase, no bursts — this is **not** AXI, and the naming
was deliberately changed to stop implying otherwise.

**Clock and reset.** One 50 MHz domain, `clk`. `reset_n` is asynchronous and
active-low at the pins; `top_system` derives `reset = ~reset_n` for the
subsystems that want it active-high. The SPI pins cross into `clk` through
synchronisers inside `spi_slave` and are false-pathed in the SDC.

**Fixed point.** Two formats coexist, by subsystem:

| Subsystem | Format | Notes |
|---|---|---|
| FFT front-end, MLP | Q9.15, 24-bit | FIR/Hann coefficients are Q1.17, 18-bit |
| CNN | Q8.16, 24-bit | weights int8, biases 24-bit |

**Memory images.** `$readmemh`/`$readmemb` paths are resolved by Quartus
**relative to the project directory `RTL/quartus/`**, which is why every path
in the RTL starts with `../`. A wrong path does not error — the array
silently stays zero — so treat this as load-bearing.

## 3. Top level

15 pins total. All sensor data arrives over SPI — there are no parallel sensor
ports.

### SPI frame format

One chip-select assertion carries one acquisition epoch: **27 bytes**, nine
24-bit words, MSB byte first.

```
word  0  1  2  3 │  4  5  6 │  7  8
     └vibration┘ │ └current┘│ └temp┘
        → FFT    │   → MLP extra features
```

Releasing CS re-zeroes the word/byte counters, so a truncated or overlong
frame costs that one frame instead of permanently rotating the channel
mapping. Either case latches `sys_error`.

## 4. Interconnect

### Hop by hop

**`spi_slave` → `spi_sensor_frame_rx`.** Bytes in, a registered 9-word
snapshot out, one `frame_valid` pulse per frame.

**`spi_sensor_frame_rx` → FFT.** SPI cannot be back-pressured, so the four
vibration samples sit in a one-deep register in `top_system` until the
pipeline accepts them *atomically* (all four channels assert ready together).
The FIR front-end is decimate-by-32, so it drains far faster than SPI fills;
`vib_overrun` latches if that ever stops being true.

**Inside the shared FFT.** Four independent FIR → frame → mean → Hann chains
feed a round-robin scheduler that owns a **single** `fft_64_dualmode` core.
Once selected, a sensor keeps the core for its whole 64-sample load, transform
and 64-bin readout. Every output bin carries `fft_sensor_id`, so downstream
consumers know whose spectrum they are looking at.

**FFT → MLP.** One 132-word feature buffer, time-multiplexed across the four
sensors — the shared FFT serialises them anyway, so a second buffer would buy
nothing. A frame is accepted or refused *at its first bin*, never half-way;
that is what keeps the buffer from being rewritten under an inference still
reading it (the MLP samples `features` combinationally for ~165 cycles).
Refused frames latch `sys_error`.

Feature map: `[0..63]` real bins, `[64..127]` imaginary bins, `[128..131]` the
aux sensors, right-shifted by `mlp_weights_pkg::EXTRA_SHIFT` before entry.

**FFT → CNN.** The CNN's four input channels *are* the four vibration sensors.
Each gets a private `fft_to_stream_adapter` (which keeps only its own sensor's
bins 0..31) and a private `spectrogram_generator`. `spectrogram_4ch_join` then
walks all four in lockstep so one CNN beat is one pixel of all four sensors.
`desync_error` latches if they ever fall out of step — the only way a lockstep
join can deadlock.

**Backpressure.** `fft_ready` is driven from the ready of whichever
spectrogram owns the bin currently on the bus (bins ≥ 32 feed only the MLP
collector, which never stalls). Bins are therefore stalled, never dropped.

**Arbiter.** The MLP produces one verdict per sensor, the CNN one verdict for
the machine. A fault on *any* sensor counts as an MLP fault; `sensor_fault_mask`
says which. Both models faulted → Critical; exactly one → Warning;
neither → Normal.

> **Class index gotcha.** The two networks do not agree on ordering. The MLP's
> argmax space is `0:Bearing 1:Misalign 2:Normal 3:Unbalance`, while the CNN
> exposes named ports in the order `normal, unbalance, misalign, bearing`.
> `inference_arbiter` re-maps the CNN outputs into the MLP's space when it
> computes its argmax. Preserve that mapping if you touch either model.

## 5. Rates

`HOP_SIZE = 64` (non-overlapping frames) after decimate-by-32, so **one FFT
frame per channel costs 2048 SPI frames**. All four channels fill together;
the shared FFT then processes their four frames back to back.

| Event | Period |
|---|---|
| MLP inference | 4 per 2048 SPI frames (one per sensor) |
| Spectrogram row | 1 per FFT frame per sensor |
| **CNN inference** | 32 rows → **65,536 SPI frames** |

If the CNN rate is too slow for your application, lower `HOP_SIZE` in the
`preprocess_fft_shared_4sensor_q915_no_lms` instantiation to get overlapping
windows.

## 6. Status and error flags

`sys_error` is the sticky OR of four independent conditions, all of which mean
"a frame was lost, but the pipeline is still running":

| Source | Meaning |
|---|---|
| `spi_sensor_frame_rx.frame_error` | CS released mid-frame, or an overlong frame |
| `vib_overrun` | a new SPI frame arrived before the FFT took the previous one |
| `fft_to_mlp_collector.frame_dropped` | an FFT frame skipped because the MLP was still busy |
| `spectrogram_4ch_join.desync_error` | the four spectrograms lost lockstep |

They are latched, not pulsed — clear them with a reset.

## 7. Open items

- **No pin assignments.** The `.qsf` has none; add them before programming.
- **MLP extra features.** There are five non-vibration sensors but the trained
  MLP has exactly four extra slots (`N_EXTRA = 4`; widening it means
  retraining). `fft_to_mlp_collector`'s `EXTRA_SEL` parameter currently maps
  `{current 0,1,2, temperature 0}`, leaving temperature 1 wired but unused.
  **Confirm this against the training script** — it is the one assumption in
  the datapath that the RTL cannot verify for itself.
- **MLP feature semantics.** `mlp_weights_pkg` documents inputs `0..127` as
  low-band `|rFFT|` magnitude, but the collector fills them with raw real and
  imaginary parts. Worth reconciling against how the model was trained.
- **`features[132]`** is the largest remaining ALM consumer in the MLP (a
  132:1 × 24-bit mux). Moving it into a RAM would need `mlp.sv` to switch to a
  registered read.
- **No formal verification of the integrated top.** Subsystem testbenches exist
  under `cnn/tb/` and `spectrogram/tb/`; there is no `top_system` bench yet.
