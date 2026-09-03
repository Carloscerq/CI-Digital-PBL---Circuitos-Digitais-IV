# `top_system` testbench

Full-chain testbench for the integrated design. It drives the DUT's only input
— the UART pin — with synthetic sensor frames built from recorded captures, and
scores the decision outputs and the sticky error bus.

```
RTL/top_system/
  rtl/                     design under test
  tb/
    tb_top_system.sv       the testbench
    run_tb_top_system.sh   build + run (Verilator or Questa)
```

Capture data lives outside this tree, in
`Scripts/process_dataset/dataset_q915/`, written by `split_dataset.py` +
`quantize.py`.

## Running

```bash
cd RTL/top_system/tb

./run_tb_top_system.sh uart                        # seconds  — framing only
./run_tb_top_system.sh stream                      # minutes  — full chain
./run_tb_top_system.sh stream +SCENARIO=0Nm_BPFO_10
./run_tb_top_system.sh uart --baud 115200          # production baud divisor
./run_tb_top_system.sh stream --vsim --trace
```

Both flows define **`RTL_SIM`**. `dual_port_ram.v` instantiates an Altera
`altsyncram` megafunction for Quartus and a behavioural array for simulation,
chosen by that define; without it, elaboration fails with `Module 'altsyncram'
is not defined`. The FFT project's own `run_*_modelsim.do` and
`run_*_xcelium.sh` pass it for the same reason. The two other `RTL_SIM` guards
only select default coefficient paths, which `top_system.sv` overrides
explicitly, so the define cannot change which coefficients load.

The RTL file list is parsed out of `RTL/quartus/quartus.qsf`, so a file added to
the Quartus project is automatically in the simulation and the two lists cannot
drift apart. The simulation runs from `RTL/sim_verilator/` because the design's
`$readmemh` paths (`../mem/cnn/…`, `../FFT/…/coefficients/…`) are relative to
the Quartus project directory.

### Modes

| Mode | Cost | What it proves |
|---|---|---|
| `uart` | ~seconds | Sync hunting, checksum rejection, mid-frame idle-timeout resync, and that the framer recovers afterwards. Runs at whatever baud the DUT was built with. |
| `stream` | ~minutes | The whole chain: UART → FIR/FFT → MLP and CNN → arbiter, scored for pipeline health and classification. |

Run `uart` first. It exercises all the plumbing in seconds, so a broken build
never costs a full soak run.

### Plusargs

| Plusarg | Default | Meaning |
|---|---|---|
| `+SCENARIO=<name>` | `0Nm_Normal` | Which capture set to stream |
| `+DATA_ROOT=<path>` | `../../Scripts/process_dataset/dataset_q915` | Capture root, relative to the sim CWD |
| `+CNN_TARGET=<n>` | `1` | Stop after N CNN verdicts |
| `+MAX_FRAMES=<n>` | derived | Override the frame budget |
| `+FRAME_GAP=<clocks>` | `0` | Idle clocks between frames (see below) |
| `+STRICT_CLASS` | off | Make a classification mismatch fail the run |
| `+NO_LOOP` | off | Stop at end-of-capture instead of rewinding |
| `+PROGRESS=<n>` | `2048` | Progress line every N frames |

## Capture data layout

Written by `Scripts/process_dataset/`, rooted at `dataset_q915/`:

```
vibration/<scenario>/<scenario>_sensor{1,2,3,4}.mem     # 4 accelerometers
current/<scenario>/<scenario>_sensor{1,2,3}.mem         # U, V, W phase
temperature/<scenario>/<scenario>_sensor{1,2}.mem       # housing A, housing B
```

`<type>/<scenario>/<scenario>_sensor<N>.mem`, with `N` starting at 1 within each
type. Index order is TDMS column order, set in `split_dataset.py`, so
`current_sensor1` is **U-phase** and `temperature_sensor{1,2}` are housings
**A** and **B**.

A frame has seven words — `N_VIB=4`, `N_CUR=1`, `N_TMP=2` from
`system_types_pkg` — so the testbench reads six of the nine files per scenario.
V- and W-phase have no slot: the model uses U-phase, the only phase recorded in
every run.

**Format.** One sample per line, 6 hex digits, 24-bit two's complement, **Q9.15**
(15 fractional bits, range ±256.0) — the same format `$readmemh` takes, but the
testbench streams it line by line rather than loading it, so a capture of any
length costs no memory.

The files must be time-aligned: sample *k* of each is the same instant. The
testbench reads one line from each of the six files per UART frame, so they stay
aligned for the whole run.

### The three non-vibration words are aggregates, not samples

Vibration goes on the wire raw. The other three words do not, and passing raw
samples through would be wrong in two different ways.

`mlp_weights` was trained on **frame aggregates already scaled by 2^9**, and
`fft_to_mlp_collector` applies only `EXTRA_SHIFT = {-6,-6,-5}` on the way in.
So the host — here, the testbench — owes the DUT:

| word | contents | from Q9.15 captures | trained MLP range |
|---|---|---|---|
| 4 — current | `mean(x²)` over the block, ×2^9 | `mean(x·x) >> 21` | 75.1 … 124.1 |
| 5 — temp A | `mean(x)` over the block, ×2^9 | `mean(x) >> 6` | 199.7 … 262.7 |
| 6 — temp B | `mean(x)` over the block, ×2^9 | `mean(x) >> 6` | 201.6 … 269.3 |

Passing a raw Q9.15 sample instead lands temperature **64× high** (12776 where
the model wants ~199), and for current hands the MLP one arbitrary point of a
50 Hz sinusoid that swings ±4 A where the model wants its mean square.

The block is `AGG_SPAN` = one FFT round = 2048 frames, so exactly one fresh
aggregate is published per MLP inference and held for the whole block — one
accumulator per channel, which is what the notebook costs out for the RTL. The
notebook aggregates over 4096 raw samples with a 1024 hop; the RTL's
decimate-by-32 and `HOP_SIZE=64` give 2048. Both aggregates are near-constant
within a run (temperature moves ~0.2 °C, current power is stationary), so the
span difference does not move the MLP inputs.

If a capture is missing the testbench holds a constant in the *aggregate*
domain (`aux_current_dflt`, `aux_temp0_dflt`, `aux_temp1_dflt`, all ×2^9) and
says so on stdout.

### Scenario naming

`<load>Nm_<condition>[_<severity>]` — e.g. `0Nm_Normal`, `0Nm_BPFO_10`.

The testbench maps the condition to the expected class by substring, so new
captures are picked up without editing code:

| Condition token | Class | Index |
|---|---|---|
| `Normal` | Normal | 2 |
| `BPFO`, `BPFI`, `BSF`, `Bearing` | Bearing | 0 |
| `Misalign` | Misalign | 1 |
| `Unbalance`, `Imbalance` | Unbalance | 3 |

Anything unrecognised is scored as `SKIP` rather than a failure. The mapping
lives in `expected_class()`; the index order matches `inference_arbiter` and
`mlp_weights.sv`.

### Aux captures are not there yet

Only `vibration/` exists today. The testbench opens the `current/` and
`temperature/` files if present and otherwise substitutes documented constants
(45.0 °C / 42.0 °C / 0.0), saying so loudly at startup.

This matters for how you read the result: **the CNN verdict is trustworthy
today** — it reads only the spectrogram, which is built entirely from real
vibration data. **The MLP verdict is not**, because 3 of its 132 inputs are
fabricated. So the testbench reports an MLP mismatch as `INFO` until all three
aux captures are present, and only then promotes it to `FAIL`.

## Timing

The design's rates set the cost of a test, and they are steep:

| Milestone | Frames | Why |
|---|---|---|
| 1 decimated sample | 32 | FIR decimate 4 × 4 × 2 |
| 1 FFT round (1 MLP verdict, 1 spectrogram row) | 2,048 | `HOP_SIZE` = 64 |
| 1 spectrogram (1 CNN verdict) | **65,536** | `SPEC_FRAMES` = 32 |

At the production 115200 baud a 24-byte frame is 104,167 clocks, so one CNN
verdict would be **6.8 × 10⁹ clocks** — not simulatable. The testbench therefore
builds the DUT with `BAUD_RATE = 1_562_500`, the fastest divisor
`baudrate.sv` supports (`RX_ACC_MAX = CLK/(BAUD×16)` must stay ≥ 2, or
`$clog2` yields a zero-width accumulator). That gives 32 clocks/bit, 7,680
clocks/frame, and **~5.0 × 10⁸ clocks ≈ 10 s of simulated time** per verdict.

Only the divisor changes. The receiver FSM, its 16× oversampling and mid-bit
sampling point, and the whole framing layer run identically. Use
`./run_tb_top_system.sh uart --baud 115200` to prove the production divisor
itself.

### If `ERR_VIB_OVERRUN` fires

Frames are sent back to back, which is **13.5× the production arrival rate** of
480 frames/s. The pipeline should absorb it — an FFT round happens once per
2,048 frames and the vibration FIFO holds 64 — but an overrun at 13.5× says
nothing about behaviour at 1×. Re-run with `+FRAME_GAP=96000` (roughly the
production spacing) before concluding the RTL is at fault.

## Error bus

`error_status` is checked bit by bit. Bits 0–2 mean data was lost; bits 3–5 mean
the pipeline misbehaved but kept its data. See `system_types_pkg.sv` for the
index map.

`ERR_CNN_STALL` is **reported, not failed**: it means the CNN back-pressured the
FFT, which is legal and expected once the pipeline saturates.

## Observability

`top_system` exposes no result-valid strobe, so the per-inference monitors read
`dut.mlp_done`, `dut.cnn_valid` and `dut.u_ingestion.sensor_frame_valid` through
cross-module references. Those are simulation-only conveniences — every pass/fail
criterion is evaluated on real top-level ports.

## Note on repository size

`dataset_q915/` is **6.8 GB**. It is already covered by `.gitignore`
(`**/*/dataset_q915/*`), so it cannot be committed by accident. Keep it that
way: point `+DATA_ROOT` elsewhere rather than moving captures into the tree.
