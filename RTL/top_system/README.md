# `top_system` on the DE0-CV

`top_system` is board-agnostic: it talks in logical port names (`clk`, `reset`,
`uart_rx`, `status_leds`, `sensor_fault_mask`, `alert_flag`, `error_status`) so
that `tb_top_system` can drive it directly. Everything specific to this board
lives one level up, in `top_system_de0cv.sv`, which is the synthesis top level.

```
RTL/top_system/
  rtl/top_system.sv            the design      -- logical port names
  rtl/top_system_de0cv.sv      board wrapper   -- pins, reset, LEDs, telemetry
  tb/tb_top_system.sv          full-chain TB   -- framing, DSP, inference
  tb/tb_top_system_de0cv.sv    wrapper TB      -- telemetry path only
RTL/quartus/                   the Quartus project (top = top_system_de0cv)
Scripts/fpga_host/top_system_link_test.py      closed-loop link validation
```

## Wiring

Same two pins the loopback proved (`RTL/uart/README.md`), a 3.3 V CP2102:

| Adapter | FPGA port   | Pin       | Header      |
|---------|-------------|-----------|-------------|
| TX      | `GPIO_1[4]` | `PIN_A13` | JP2, hole 5 |
| RX      | `GPIO_0[4]` | `PIN_D17` | JP1, hole 5 |
| GND     | —           | —         | JP1, hole 12 |

## Controls and indicators

| Control | Meaning |
|---------|---------|
| `KEY[0]` | momentary reset (active low). Not needed at power-up. |
| `SW[0]`  | hold reset (active high) |
| `LEDR[2:0]` | `status_leds`: [2] Critical, [1] Warning, [0] Normal |
| `LEDR[6:3]` | `sensor_fault_mask`, one bit per vibration channel |
| `LEDR[7]`   | `alert_flag` |
| `LEDR[8]`   | blinks while bytes arrive |
| `LEDR[9]`   | any sticky bit set in `error_status` |
| `HEX1 HEX0` | `error_status` in hex |
| `HEX3 HEX2` | byte count, low byte, in hex |

## Telemetry — why the wrapper transmits

`top_system` has no UART transmitter, and nothing in `Scripts/fpga_host` ever
reads from the port, so streaming is **open loop**: the host cannot tell whether
the board received a single byte. The wrapper closes that loop. Every ~500 ms it
sends one line on `GPIO_0[4]`:

```
B=xxxx E=xx S=x F=x A=x M=c N=xx C=c K=xx
```

| Field | Meaning |
|---|---|
| `B` | bytes seen on the wire, 16-bit, **wraps at 65536** |
| `E` | `error_status`, sticky; bit 0 = `ERR_UART_FRAME` |
| `S` | `status_leds` |
| `F` | `sensor_fault_mask` |
| `A` | `alert_flag` |
| `M` | class of the latest MLP verdict: 0 Bearing, 1 Misalign, 2 Normal, 3 Unbalance |
| `N` | MLP verdicts so far, 8-bit, wraps — a change means a new verdict |
| `C` | class of the latest CNN verdict |
| `K` | CNN verdicts so far, 8-bit, wraps |

`M`/`C` exist because `status_leds` cannot be scored: it only says whether the
two models agree on *fault vs normal*, so a Misalign machine called Bearing
looks identical to a correct call. `top_system` exposes the classes as
`mlp_class`/`cnn_class` plus their strobes (CLASS_OBSERVE_NOTE); the wrapper
counts strobe **rising edges**, so a strobe held high for a handshake still
counts once — `tb_top_system_de0cv` holds one for five cycles to prove it.

Before the first CNN verdict the arbiter's CNN register sits at its reset value,
Normal, so for the first ~136 s at full rate a fault scenario shows **Warning**
(MLP says fault, "CNN" says normal) rather than Critical. That is the reset
default, not a disagreement between the models.

`B` is counted by a **second receiver** listening to the same line, independent
of the ingestion path. That is what makes it useful: it separates the two
failures that look identical from the host.

| Symptom | Meaning |
|---|---|
| `B` stays `0000` | nothing reaches the FPGA — wiring, pins, or baud |
| `B` climbs, `E=01` | bytes arrive but frames are rejected — framing, byte order, checksum, or a frame-geometry mismatch |
| `B` climbs, `E=00` | the link and the framer are both healthy |

Counting falling edges instead would have been cheaper and wrong: the line idles
high but data bits toggle freely, so `0x55` gives four falling edges and `0xFF`
gives one. Only a receiver knows where frames begin. `tb_top_system_de0cv`
checks exactly that, by sending equal counts of `0x55`, `0xFF` and `0x00` and
asserting `B` equals the byte count.

Because `B` wraps every ~5.7 s at full rate, treat it as exact for bounded
bursts (what `top_system_link_test.py` does) and as a liveness dial for long
streams.

## Building and running

```bash
export PATH=$HOME/altera_lite/25.1std/quartus/bin:$PATH
cd RTL/quartus
quartus_sh --flow compile quartus
quartus_pgm -m jtag -o "p;output_files/quartus.sof"
```

11,586 ALMs (63%), 18,008 registers, 144 M10K (47%), 46 DSP (70%); +1.78 ns
worst-case setup slack against the 20 ns period, fully constrained.

```bash
cd RTL/top_system/tb
./run_tb_top_system.sh uart          # framing + error injection, seconds
./run_tb_top_system.sh stream        # full chain, minutes
./run_tb_wrapper.sh                  # telemetry path

cd Scripts/fpga_host
python3 top_system_link_test.py               # 200 frames, closed loop
python3 top_system_link_test.py --frames 2000 # sustained burst
python3 top_system_link_test.py --corrupt     # checks E picks up a bad checksum
```

Measured on hardware: 48,000 bytes at essentially 100% of the 115200 line with
zero loss, `E=00`, and no `ERR_VIB_OVERRUN` — the DSP chain keeps up with the
wire.

## Enviando dados para a placa

Escolher e listar cenários:

```bash
cd Scripts/fpga_host
python3 stream_scenario.py --list          # 43 cenários; 16 sem "FALLBACK"
                                           # têm captura de corrente/temperatura
```

Um cenário só, com duração limitada:

```bash
python3 stream_scenario.py -s 0Nm_BPFI_03 --max-seconds 20
python3 stream_scenario.py -s 4Nm_Normal  --max-frames 5000
python3 stream_scenario.py -s 2Nm_Misalign_01 --frame-rate 100   # 0 = taxa máxima
```

Uma mistura cronometrada de cenários:

```bash
python3 run_schedule.py --schedule "0Nm_Normal:30,0Nm_BPFI_03:30,4Nm_BPFO_03:30" --once
python3 run_schedule.py --schedule-file bench_example.txt --shuffle
```

Sem placa, para conferir a geometria do quadro:

```bash
python3 stream_scenario.py -s 0Nm_Normal --dry-run --max-seconds 3
```

Validação em malha fechada de um disparo limitado (é esta que mede perda com
exatidão, porque espera o fluxo assentar):

```bash
python3 top_system_link_test.py --frames 2000
python3 top_system_link_test.py --corrupt
```

### Lendo a resposta da placa

As linhas de status agora carregam a própria visão do FPGA, porque `SerialSink`
drena a direção de recepção enquanto transmite:

```
... bytes=     231168 up=    20.0s aux[...] fpga[rx=227483 Warning F=1111 ALERT E=00]
```

`rx` é o total **desdobrado**: o campo `B` da placa é um contador de 16 bits que
a taxa plena dá a volta a cada ~5,7 s, então reports consecutivos pareciam
*diminuir*; `poll_telemetry` desfaz isso com diferença modular. Compare `rx`
com `bytes=` na mesma linha.

A defasagem entre eles é dado em trânsito mais a idade do snapshot (até um
período de report), e sua fase deriva em relação às linhas de status — então uma
defasagem que oscila em algumas centenas de bytes é ruído de medição, não perda.
Para medir perda, use `top_system_link_test.py`, que espera o fluxo assentar e
compara exatamente (medido: 48 000 enviados, `B=48000`).

Se a placa roda `top_system` puro em vez do wrapper, nada chega na recepção,
`telemetry` fica `None` e as linhas de status ficam idênticas às de antes.

## Web dashboard

`Scripts/fpga_host/bench_server.py` owns the port, streams scenarios, reads the
telemetry back and scores every verdict against the class the scenario name
implies. Stop `stream_scenario.py` / `run_schedule.py` first — only one process
can hold `/dev/ttyUSB0`.

```bash
cd Scripts/fpga_host
python3 bench_server.py              # open http://127.0.0.1:8050
python3 bench_server.py --simulate   # no board: SimSink answers instead
```

The page shows the board's LEDs against the expected state, MLP and CNN class
accuracy with confusion matrices, a per-scenario accuracy table, throughput sent
vs counted by the FPGA, and a verdict log. Every verdict is also appended to
`Scripts/fpga_host/logs/bench_*.jsonl`, and "Exportar CSV" downloads the log.

**What gets scored.** A verdict counts only when the whole window that produced
it lies inside the scenario being streamed (SCORING_NOTE in the server): after a
start or a switch the MLP needs 2 rounds (~8.5 s) and the CNN a full spectrogram
plus a round (~141 s). Anything earlier is logged as *transição* and excluded.
`--settle-rounds` widens that guard if the LMS takes longer to reconverge.
Scenarios marked FALLBACK have no current/temperature capture, so their MLP
verdicts are scored but provisional, exactly as `tb_top_system` treats them.

**Loss** is only reported when the port has been idle for 1.5 s: while
streaming, the FPGA's count lags by whatever is in flight.

**`--simulate`** exists to exercise the page with no board attached. Its
verdicts are drawn at `--sim-accuracy` and the page says so in a banner; nothing
it shows describes the hardware.

## Two things to know

**`quartus.qsf` had no I/O standards.** It carried the board pin *locations* but
no `IO_STANDARD` assignments, so every pin fell back to the 2.5 V default —
visible as `2.5 V` in `output_files/quartus.pin` — while the DE0-CV's banks are
3.3 V and the CP2102 drives 3.3 V into `GPIO_1[4]`. The standard is now declared
for each port the design uses.

**Streaming real data can produce a `Warning` verdict on a `Normal` scenario.**
Observed with `0Nm_Normal`: `E=00` (the link is clean) but
`verdict=Warning faults=1111 alert=1`. `fpga_uart_link.py` itself warns that the
aux words land outside the range the MLP was trained on
(`temp_a=199, trained 199.7..262.7`), so this looks like aux scaling rather than
anything to do with the link. Worth chasing separately.

## Why a wrapper and not renamed ports

Renaming `top_system`'s ports to board signal names makes the pin table in
`quartus.qsf` apply with no new location assignments, which is tempting and does
work. The cost is that `tb_top_system` instantiates `.clk`, `.reset`, `.uart_rx`,
`.status_leds` and `.alert_flag` — so the rename breaks the full-chain testbench
outright, and the project's main verification asset stops elaborating. The
wrapper gets the same pin-table benefit (its own ports are named after board
signals, including `GPIO_1[4]` declared as a one-bit vector indexed at 4) while
`top_system` keeps the names the testbench drives.
