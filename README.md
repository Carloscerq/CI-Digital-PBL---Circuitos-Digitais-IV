# SMMA — Smart Machine Monitoring Accelerator

FPGA accelerator for **real-time fault classification on rotating industrial
machines**. Nine sensors stream into a Cyclone V over a single SPI link; the
fabric filters, windows and transforms the vibration channels, then runs *two
independent neural networks* over the result and cross-checks their verdicts
before lighting a status output.

Developed as a Problem-Based Learning project for **TEC498 — Circuitos
Digitais IV**.

---

## What it does

| | |
|---|---|
| **Inputs** | 4 vibration + 3 current + 2 temperature sensors, 24-bit signed, over one SPI slave port |
| **Classes** | Normal · Unbalance · Misalignment · Bearing fault |
| **Networks** | An MLP on the raw spectrum, and a CNN on a 4-channel spectrogram image |
| **Output** | 3-state status (Normal / Warning / Critical), a per-sensor fault mask, and an alert flag |
| **Target** | Intel Cyclone V `5CEBA4F23C7`, 50 MHz, Quartus Prime 25.1std Lite |

The two networks are deliberately different in kind. The MLP sees one sensor's
spectrum at a time and is cheap and fast; the CNN sees all four sensors at once
as a 32×32 image and is slower but spatially aware. **Agreement means high
confidence; disagreement raises a warning rather than a verdict.**

## Architecture at a glance

```
                                   ┌───────────────────────────────┐
  9 sensors ──SPI──► frame RX ──┬─►│ shared 64-point FFT pipeline  │
                                │  │  4 front-ends, 1 FFT core     │
                                │  └───────────────┬───────────────┘
                                │                  │  bins, tagged with sensor id
                                │      ┌───────────┴───────────┐
                                │      ▼                       ▼
                                │   MLP  132→8→4→4       4 × spectrogram
                                │   (time-muxed over      (32 bins × 32 rows)
                                │    the 4 sensors)              │
                                │      │                         ▼
                                └──────┤ current + temperature   CNN
                                       │ as extra features    32×32×4
                                       ▼                         │
                                  ┌────┴─────────────────────────┴───┐
                                  │        inference arbiter         │
                                  └────────────────┬─────────────────┘
                                                   ▼
                                     status_leds · sensor_fault_mask · alert
```

Only the vibration channels need the FFT, and all four **share a single FFT
core** via a round-robin scheduler — that is what keeps the design inside the
device.

## Repository layout

```
.
├── RTL/            All hardware. See RTL/README.md for the technical guide.
│   ├── quartus/      Quartus project (open quartus.qpf here)
│   ├── top_system/   Top level + the glue that binds the subsystems
│   ├── FFT/          Signal-processing front-end (FIR → frame → Hann → FFT)
│   ├── cnn/          Convolutional network
│   ├── mlp_model/    Multilayer perceptron
│   ├── spectrogram/  FFT-bins → image buffer
│   ├── spi/          SPI slave (and a master, for benches)
│   ├── mem/          .mem weight images loaded by $readmemh
│   └── ...           gcd, mac, perceptron, LMS — standalone building blocks
├── Scripts/        Model training and weight export (Python / Jupyter)
│   ├── cnn/          SMMA_Pipeline.ipynb — CNN training + fixed-point golden model
│   ├── mlp_training.ipynb
│   └── export/       gen_mlp_weights_sv.py → RTL/mem/mlp/*.mem
├── Relatorios/     Session reports (PT-BR, LaTeX + PDF)
└── PBL.pdf         Problem statement
```

## Building

```bash
# GUI
quartus RTL/quartus/quartus.qpf

# Command line
cd RTL/quartus
quartus_sh --flow compile quartus
```

The top-level entity is `top_system`; constraints live in
`RTL/quartus/top_system.sdc`. Weight and coefficient files are read at
elaboration time by `$readmemh`/`$readmemb` with paths **relative to
`RTL/quartus/`** — run the flow from that directory or the ROMs will silently
initialise to zero.

No pin assignments are committed yet; add them for your board before
generating a `.sof` you intend to program.

## Retraining the models

Weights are not hand-written. Both networks train in Python and export
fixed-point images that the RTL reads directly:

```bash
cd Scripts
pip install -r requirements.txt
jupyter lab                       # mlp_training.ipynb / cnn/SMMA_Pipeline.ipynb

# then regenerate the MLP ROM images + dimension package
python3 export/gen_mlp_weights_sv.py mlp_lowband_weights.h
```

This rewrites `RTL/mem/mlp/*.mem` and `RTL/mlp_model/mlp_weights.sv`. Do not
edit either by hand.

## Status

Compiles and closes timing on the target device. From the most recent full
flow (Quartus 25.1std Lite, `5CEBA4F23C7`):

| Resource | Used | Available | |
|---|---:|---:|---:|
| Logic (ALMs) | 8,230 | 18,480 | 45 % |
| Registers | 10,812 | — | |
| Block memory | 580,552 bits | 3,153,920 | 18 % |
| M10K blocks | 119 | 308 | 39 % |
| DSP blocks | 42 | 66 | 64 % |
| Pins | 15 | 224 | 7 % |

**Fmax 55.17 MHz** at the worst modelled corner against a 50 MHz target
(setup slack +1.874 ns, hold +0.239 ns, no failing paths).

Not yet done: board pin assignments, and hardware validation against a live
sensor rig. See `RTL/README.md` for the open design questions.

## Authors

Felipe Freire · Carlos Cerqueira · Antonio M. M. Neto · Vitor Cavalcante
