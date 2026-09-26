#!/usr/bin/env python3
"""
fpga_uart_link -- host side of the top_system UART sensor link.

Everything the two driver scripts share lives here: the frame format, the
capture reader, the host-side aux aggregation, the serial sink, pacing,
logging and the interactive command channel.

What the FPGA expects
---------------------
top_system has ONE input beyond clock and reset: `uart_rx`. Every sensor
value reaches it through uart_sensor_frame_rx.sv as a 24-byte frame:

    A5 5A | word0 .. word6, each 3 bytes MSB first | XOR of the 21 payload bytes

    word 0..3  vibration sensors 1..4      raw Q9.15 samples
    word 4     current, U-phase            mean(x*x) over a block, x 2^9
    word 5     temperature housing A       mean(x)   over a block, x 2^9
    word 6     temperature housing B       mean(x)   over a block, x 2^9

The three aux words are NOT raw samples. The MLP was trained on aggregates
the host had already scaled by 2^9, and fft_to_mlp_collector applies only
EXTRA_SHIFT on top. The arithmetic is derived in tb_top_system.sv
(AUX_SCALE_NOTE); AuxAggregator below reproduces it exactly.

The line is standard 8N1, idle high, LSB first. uart_sensor_frame_rx hunts
for the sync pair, so no preamble is needed, and its idle timeout
(IDLE_TIMEOUT_BYTES = 4 byte times, ~350 us at 115200) only counts INSIDE
a frame -- a pause between frames is harmless, a pause inside one resyncs.
Writes here are always whole frames, so the host can stop and start freely.

The FPGA sends nothing back. Its verdicts appear on status_leds,
sensor_fault_mask, alert_flag and error_status. This module therefore logs
what was sent and when the fabric should have produced each verdict, so the
log can be lined up against what the pins show.
"""
from __future__ import annotations

import logging
import queue
import re
import sys
import threading
import time
from collections import OrderedDict
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional, Sequence

import numpy as np

__all__ = [
    "LinkConfig", "Scenario", "ScenarioCache", "AuxAggregator", "encode_frame",
    "FrameStream", "SerialSink", "DryRunSink", "Pacer", "CommandReader",
    "StreamStats", "setup_logging", "list_scenarios", "describe_scenarios",
    "scenario_modalities", "find_repo_root",
    "run_stream", "log_link_summary", "log_first_frame", "hexdump",
    "DEFAULT_PORT", "DEFAULT_BAUD", "BUILTIN_COMMANDS",
]

log = logging.getLogger("fpga_uart")

DEFAULT_PORT = "/dev/ttyUSB0"
DEFAULT_BAUD = 115_200


# ============================================================================
# Repository layout
# ============================================================================
def find_repo_root(start: Optional[Path] = None) -> Optional[Path]:
    """Walks up from `start` (default: this file) looking for RTL/ and Scripts/."""
    here = (start or Path(__file__)).resolve()
    for candidate in (here, *here.parents):
        if (candidate / "RTL").is_dir() and (candidate / "Scripts").is_dir():
            return candidate
    return None


# ============================================================================
# Link configuration -- mirrors system_types_pkg.sv
# ============================================================================
@dataclass(frozen=True)
class LinkConfig:
    """Geometry of the frame and the aux aggregation span.

    The defaults are the values in system_types_pkg.sv at the time of
    writing. `from_package()` reads the live file so the host tracks the
    build; `--agg-span` on the scripts overrides it for a bench FPGA built
    from something else.
    """
    data_width: int = 24
    n_vib: int = 4
    n_cur: int = 1
    n_tmp: int = 2
    sync: tuple[int, int] = (0xA5, 0x5A)
    decim_rate: int = 32
    fft_hop: int = 64
    spec_frames: int = 32
    q_frac: int = 15              # mlp_weights_pkg::Q_FRAC
    aux_gain_log2: int = 9        # host-applied gain the MLP was trained on
    agg_span: Optional[int] = None   # explicit aux span; None = DECIM_RATE*FFT_HOP
    source: str = "defaults"

    @property
    def n_sensors(self) -> int:
        return self.n_vib + self.n_cur + self.n_tmp

    @property
    def bytes_per_word(self) -> int:
        return self.data_width // 8

    @property
    def frame_bytes(self) -> int:
        return 2 + self.n_sensors * self.bytes_per_word + 1

    @property
    def frames_per_round(self) -> int:
        """Sensor frames per FFT frame per channel -- one MLP verdict."""
        return self.agg_span if self.agg_span else self.decim_rate * self.fft_hop

    @property
    def frames_per_spec(self) -> int:
        """Sensor frames per 32-row spectrogram -- one CNN verdict."""
        return self.frames_per_round * self.spec_frames

    @property
    def temp_shift(self) -> int:
        return self.q_frac - self.aux_gain_log2          # 15 - 9 = 6

    @property
    def power_shift(self) -> int:
        return 2 * self.q_frac - self.aux_gain_log2      # 30 - 9 = 21

    @property
    def word_min(self) -> int:
        return -(1 << (self.data_width - 1))

    @property
    def word_max(self) -> int:
        return (1 << (self.data_width - 1)) - 1

    def frame_seconds(self, baud: int) -> float:
        """Wire time of one frame at 8N1: 10 bit-times per byte."""
        return self.frame_bytes * 10.0 / baud

    @classmethod
    def from_package(cls, package: Path, **overrides) -> "LinkConfig":
        """Reads the geometry out of system_types_pkg.sv."""
        text = package.read_text()

        def grab(name: str, default: int) -> int:
            match = re.search(
                rf"localparam\s+(?:bit|int)\s+{name}\s*=\s*(?:1'b)?(\d+)\s*;", text)
            return int(match.group(1)) if match else default

        values = dict(
            data_width=grab("DATA_WIDTH", cls.data_width),
            n_vib=grab("N_VIB", cls.n_vib),
            n_cur=grab("N_CUR", cls.n_cur),
            n_tmp=grab("N_TMP", cls.n_tmp),
            decim_rate=grab("DECIM_RATE", cls.decim_rate),
            fft_hop=grab("FFT_HOP", cls.fft_hop),
            spec_frames=grab("SPEC_FRAMES", cls.spec_frames),
            source=str(package),
        )
        values.update({k: v for k, v in overrides.items() if v is not None})
        return cls(**values)

    def with_span(self, span: Optional[int]) -> "LinkConfig":
        if not span:
            return self
        return LinkConfig(**{**self.__dict__, "agg_span": span,
                             "source": f"{self.source} (+--agg-span {span})"})

    def describe(self) -> str:
        span = (f"--agg-span {self.agg_span}" if self.agg_span
                else f"DECIM_RATE={self.decim_rate} x FFT_HOP={self.fft_hop}")
        return (f"{self.n_sensors} words x {self.bytes_per_word} B = {self.frame_bytes} B/frame; "
                f"{span} -> {self.frames_per_round} frames/MLP verdict, "
                f"{self.frames_per_spec} frames/CNN verdict  [{self.source}]")


# ============================================================================
# Capture files
# ============================================================================
# quantize.py writes one Q9.15 code per line as six uppercase hex digits plus
# a newline, so a record is exactly seven bytes and the parse vectorises.
_MEM_LINE_BYTES = 7
_HEX_DIGITS = 6
_HEX_WEIGHTS = 1 << (4 * np.arange(_HEX_DIGITS - 1, -1, -1, dtype=np.int64))


def read_mem_file(path: Path) -> np.ndarray:
    """Loads a .mem capture as sign-extended int32 Q9.15 codes."""
    raw = np.fromfile(path, dtype=np.uint8)
    usable = (raw.size // _MEM_LINE_BYTES) * _MEM_LINE_BYTES
    lines = raw[:usable].reshape(-1, _MEM_LINE_BYTES)
    if lines.size == 0:
        raise ValueError(f"{path}: empty capture")
    if not np.all(lines[:, -1] == 0x0A):
        raise ValueError(f"{path}: expected {_MEM_LINE_BYTES}-byte records ending in LF")

    digits = lines[:, :_HEX_DIGITS].astype(np.int64)
    digits = np.where(digits <= 0x39, digits - 0x30, (digits & ~0x20) - 0x37)
    codes = digits @ _HEX_WEIGHTS
    codes = np.where(codes >= (1 << 23), codes - (1 << 24), codes)
    return codes.astype(np.int32)


MODALITIES = ("vibration", "current", "temperature")


def scenario_modalities(data_root: Path, name: str) -> dict[str, bool]:
    """Which modality directories exist for a scenario."""
    return {m: (data_root / m / name).is_dir() for m in MODALITIES}


def list_scenarios(data_root: Path, complete_only: bool = False) -> list[str]:
    """Scenario names with a vibration capture; optionally only fully-equipped ones."""
    directory = data_root / "vibration"
    if not directory.is_dir():
        return []
    names = sorted(p.name for p in directory.iterdir() if p.is_dir())
    if complete_only:
        names = [n for n in names if all(scenario_modalities(data_root, n).values())]
    return names


def describe_scenarios(data_root: Path) -> list[str]:
    """One line per scenario, flagging the ones that will run on fallback aux."""
    lines = []
    for name in list_scenarios(data_root):
        have = scenario_modalities(data_root, name)
        missing = [m for m, ok in have.items() if not ok]
        lines.append(name if not missing else f"{name}   (no {'/'.join(missing)} capture: aux words use FALLBACK)")
    return lines


@dataclass
class Scenario:
    """One capture set, held as seven aligned channel arrays in frame order.

    Vibration captures are mandatory. A missing current or temperature
    capture is tolerated: the channel is marked absent and AuxAggregator
    transmits a fallback word for it, the way tb_top_system.sv does.
    """
    name: str
    channels: list[np.ndarray]                    # frame word order
    labels: list[str]
    present: list[bool]
    position: list[int] = field(default_factory=list)
    wraps: list[int] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.position = [0] * len(self.channels)
        self.wraps = [0] * len(self.channels)

    @classmethod
    def load(cls, data_root: Path, name: str, cfg: LinkConfig,
             allow_missing_aux: bool = True) -> "Scenario":
        """Reads vibration 1..N_VIB, current 1 (U-phase), temperature 1..N_TMP."""
        spec = ([("vibration", i + 1) for i in range(cfg.n_vib)]
                + [("current", i + 1) for i in range(cfg.n_cur)]
                + [("temperature", i + 1) for i in range(cfg.n_tmp)])
        paths = [data_root / modality / name / f"{name}_sensor{index}.mem"
                 for modality, index in spec]
        present = [p.is_file() for p in paths]

        missing_vib = [str(p.relative_to(data_root)) for p, ok in zip(paths[:cfg.n_vib], present) if not ok]
        if missing_vib:
            raise FileNotFoundError(
                f"scenario '{name}' has no vibration capture: missing " + ", ".join(missing_vib))
        missing_aux = [str(p.relative_to(data_root)) for p, ok in zip(paths, present) if not ok]
        if missing_aux and not allow_missing_aux:
            raise FileNotFoundError(
                f"scenario '{name}' is incomplete under {data_root}: missing " + ", ".join(missing_aux))

        started = time.perf_counter()
        channels = [read_mem_file(p) if ok else np.zeros(1, dtype=np.int32)
                    for p, ok in zip(paths, present)]
        labels = [f"{m}{i}" for m, i in spec]
        log.info("loaded scenario %-24s %s in %.2f s", name,
                 " ".join(f"{l}={c.size if ok else 'ABSENT'}"
                          for l, c, ok in zip(labels, channels, present)),
                 time.perf_counter() - started)
        if missing_aux:
            log.warning("scenario %s has no %s capture(s); those words will carry "
                        "FALLBACK constants, so the MLP verdict is not meaningful for it",
                        name, ", ".join(l for l, ok in zip(labels, present) if not ok))
        return cls(name, channels, labels, present)

    @property
    def aux_present(self) -> list[bool]:
        """Presence flags for the non-vibration channels, in frame order."""
        return [ok for label, ok in zip(self.labels, self.present)
                if not label.startswith("vibration")]

    @property
    def aux_complete(self) -> bool:
        return all(self.aux_present)

    def next_samples(self) -> list[int]:
        """One raw Q9.15 sample per channel; every channel wraps on its own.

        Absent channels yield 0 and neither advance nor wrap; the aggregator
        substitutes a fallback word for them anyway.
        """
        out = []
        for index, channel in enumerate(self.channels):
            if not self.present[index]:
                out.append(0)
                continue
            pos = self.position[index]
            out.append(int(channel[pos]))
            pos += 1
            if pos >= channel.size:
                pos = 0
                self.wraps[index] += 1
            self.position[index] = pos
        return out

    def rewind(self) -> None:
        self.position = [0] * len(self.channels)
        self.wraps = [0] * len(self.channels)

    @property
    def shortest(self) -> int:
        return min(c.size for c, ok in zip(self.channels, self.present) if ok)


class ScenarioCache:
    """Loads scenarios on demand, prefetches the next one, keeps a few around."""

    def __init__(self, data_root: Path, cfg: LinkConfig, keep: int = 3):
        self.data_root = data_root
        self.cfg = cfg
        self.keep = keep
        self._ready: OrderedDict[str, Scenario] = OrderedDict()
        self._pending: dict[str, Future] = {}
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="prefetch")

    def prefetch(self, name: str) -> None:
        if name in self._ready or name in self._pending:
            return
        self._pending[name] = self._pool.submit(Scenario.load, self.data_root, name, self.cfg)

    def get(self, name: str) -> Scenario:
        if name in self._ready:
            self._ready.move_to_end(name)
            return self._ready[name]
        future = self._pending.pop(name, None)
        scenario = future.result() if future else Scenario.load(self.data_root, name, self.cfg)
        self._ready[name] = scenario
        while len(self._ready) > self.keep:
            evicted, _ = self._ready.popitem(last=False)
            log.debug("evicted scenario %s from cache", evicted)
        return scenario

    def close(self) -> None:
        self._pool.shutdown(wait=False, cancel_futures=True)


# ============================================================================
# Host-side aux aggregation -- tb_top_system.sv, AUX_SCALE_NOTE
# ============================================================================
def _sv_div(numerator: int, denominator: int) -> int:
    """Integer division that truncates toward zero, as SystemVerilog does."""
    quotient = abs(numerator) // denominator
    return -quotient if numerator < 0 else quotient


class AuxAggregator:
    """Turns raw current/temperature samples into the three aux words.

    A block is `span` frames. While the first block is filling the running
    prefix is published (so the words are never garbage); after that the
    value is held for a whole block and refreshed at its end -- one fresh
    aggregate per MLP verdict, the way a host with one accumulator per
    channel would behave.

        current word      = sat24( (sum(x*x) / n) >>> 21 )   -> physical A^2 x 2^9
        temperature words = sat24( (sum(x)   / n) >>> 6  )   -> physical degC x 2^9
    """

    # Ranges the MLP saw in training, in MLP-input units (word >> -EXTRA_SHIFT).
    # From Scripts/mlp_training.ipynb, cell 47. Used only to warn.
    TRAINED_MLP_INPUT = {
        "current":  (75.1, 124.1),   # U-phase_pow,            word >> 5
        "temp_a":   (199.7, 262.7),  # Temperature_housing_A,  word >> 6
        "temp_b":   (201.6, 269.3),  # Temperature_housing_B,  word >> 6
    }
    EXTRA_SHIFT = {"current": 5, "temp_a": 6, "temp_b": 6}

    # Used for a channel whose capture is missing: mid-range of what the MLP
    # was trained on, in the aggregate domain (physical x 2^9). Same values
    # as tb_top_system.sv's aux_*_dflt.
    FALLBACK_PHYSICAL = (6.0, 28.0, 29.0)        # A^2, degC, degC

    def __init__(self, cfg: LinkConfig, present: Optional[Sequence[bool]] = None):
        self.cfg = cfg
        self.span = cfg.frames_per_round
        self.reset(present)

    def reset(self, present: Optional[Sequence[bool]] = None) -> None:
        n_aux = self.cfg.n_cur + self.cfg.n_tmp
        self.present = list(present) if present is not None else [True] * n_aux
        self.acc_cur = 0
        self.acc_tmp = [0] * self.cfg.n_tmp
        self.count = 0
        self.blocks_closed = 0
        self.published = False
        gain = 1 << self.cfg.aux_gain_log2
        self.words = [int(round(v * gain)) for v in self.FALLBACK_PHYSICAL[:n_aux]]
        self.last_block: Optional[dict[str, float]] = None

    @property
    def complete(self) -> bool:
        return all(self.present)

    def _saturate(self, value: int) -> int:
        return max(self.cfg.word_min, min(self.cfg.word_max, value))

    def _publish(self, n: int) -> None:
        """Absent channels keep their fallback word, as the TB's publish_aux does."""
        if n <= 0:
            return
        if self.present[0]:
            self.words[0] = self._saturate(_sv_div(self.acc_cur, n) >> self.cfg.power_shift)
        for t in range(self.cfg.n_tmp):
            if self.present[1 + t]:
                self.words[1 + t] = self._saturate(
                    _sv_div(self.acc_tmp[t], n) >> self.cfg.temp_shift)

    def push(self, current_raw: int, temperature_raw: Sequence[int]) -> list[int]:
        """Feeds one frame's raw aux samples; returns the words to transmit."""
        self.acc_cur += current_raw * current_raw
        for t, raw in enumerate(temperature_raw):
            self.acc_tmp[t] += raw
        self.count += 1

        if self.count >= self.span:
            self._publish(self.count)
            self.published = True
            self.blocks_closed += 1
            self.last_block = self.physical()
            self.acc_cur = 0
            self.acc_tmp = [0] * self.cfg.n_tmp
            self.count = 0
        elif not self.published:
            self._publish(self.count)                # warm-up: prefix only
        return list(self.words)

    def physical(self) -> dict[str, float]:
        """The published words in physical units and in MLP-input units."""
        gain = float(1 << self.cfg.aux_gain_log2)
        out = {
            "current_A2": self.words[0] / gain,
            "current_mlp": self.words[0] >> self.EXTRA_SHIFT["current"],
        }
        keys = ("temp_a", "temp_b")
        for t in range(self.cfg.n_tmp):
            key = keys[t] if t < len(keys) else f"temp_{t}"
            out[f"{key}_degC"] = self.words[1 + t] / gain
            out[f"{key}_mlp"] = self.words[1 + t] >> self.EXTRA_SHIFT.get(key, 6)
        return out

    def out_of_range(self) -> list[str]:
        """Names of aux inputs outside the range the MLP was trained on."""
        phys = self.physical()
        bad = []
        for key, (lo, hi) in self.TRAINED_MLP_INPUT.items():
            value = phys.get(f"{key}_mlp")
            if value is not None and not (lo <= value <= hi):
                bad.append(f"{key}={value} (trained {lo}..{hi})")
        return bad


# ============================================================================
# Frame encoding -- uart_sensor_frame_rx.sv
# ============================================================================
def encode_frame(words: Sequence[int], cfg: LinkConfig = LinkConfig(),
                 corrupt_checksum: bool = False) -> bytes:
    """Packs N_SENSORS signed words into one sync + payload + XOR frame."""
    if len(words) != cfg.n_sensors:
        raise ValueError(f"expected {cfg.n_sensors} words, got {len(words)}")
    mask = (1 << cfg.data_width) - 1
    payload = bytearray()
    for word in words:
        if not (cfg.word_min <= word <= cfg.word_max):
            raise ValueError(f"word {word} outside {cfg.data_width}-bit signed range")
        payload += (word & mask).to_bytes(cfg.bytes_per_word, "big")   # MSB first
    checksum = 0
    for byte in payload:
        checksum ^= byte
    if corrupt_checksum:
        checksum ^= 0xFF
    return bytes(cfg.sync) + bytes(payload) + bytes([checksum])


def hexdump(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)


# ============================================================================
# Frame stream: scenario + aggregator -> frames
# ============================================================================
class FrameStream:
    """Produces frames from the active scenario, switching on request."""

    def __init__(self, cfg: LinkConfig, cache: ScenarioCache, first: str,
                 align_switch: bool = True):
        self.cfg = cfg
        self.cache = cache
        self.align_switch = align_switch
        self.scenario = cache.get(first)
        self.aggregator = AuxAggregator(cfg, self.scenario.aux_present)
        self.frames_sent = 0
        self.frames_in_scenario = 0
        self.pending: Optional[str] = None
        self.switches = 0

    def request_switch(self, name: str) -> None:
        """Queues a scenario change; applied at the next block boundary."""
        if name == self.scenario.name and self.pending is None:
            log.info("switch to %s ignored: already active", name)
            return
        self.cache.prefetch(name)
        self.pending = name
        if self.align_switch:
            remaining = (-self.frames_sent) % self.cfg.frames_per_round
            log.info("switch to %s queued; applies at the next MLP round boundary (in %d frames)",
                     name, remaining)
        else:
            log.info("switch to %s queued; applies immediately", name)

    def _apply_switch(self) -> None:
        assert self.pending is not None
        name, self.pending = self.pending, None
        self.scenario = self.cache.get(name)
        self.scenario.rewind()
        # Fresh accumulators: the new scenario's aux words start from its own
        # prefix rather than blending one block across two machines.
        self.aggregator.reset(self.scenario.aux_present)
        self.frames_in_scenario = 0
        self.switches += 1
        log.info("=== now streaming %s (after %d frames total) ===", name, self.frames_sent)

    def _at_boundary(self) -> bool:
        return (self.frames_sent % self.cfg.frames_per_round) == 0

    def next_frame(self) -> bytes:
        if self.pending is not None and (not self.align_switch or self._at_boundary()):
            self._apply_switch()

        raw = self.scenario.next_samples()
        vib = raw[:self.cfg.n_vib]
        current = raw[self.cfg.n_vib]
        temps = raw[self.cfg.n_vib + self.cfg.n_cur:]
        aux = self.aggregator.push(current, temps)

        frame = encode_frame(vib + aux, self.cfg)
        self.frames_sent += 1
        self.frames_in_scenario += 1
        return frame

    def next_batch(self, count: int) -> bytes:
        return b"".join(self.next_frame() for _ in range(count))


# ============================================================================
# Sinks
# ============================================================================
# top_system_de0cv reports this on GPIO_0[4] every ~500 ms. top_system itself
# has no transmitter, so on a board built from top_system alone nothing arrives
# and `telemetry` simply stays None -- the status lines look exactly as before.
# See RTL/top_system/README.md for the field meanings.
TELEMETRY_RE = re.compile(rb"B=([0-9A-F]{4}) E=([0-9A-F]{2}) S=([0-9A-F]) "
                          rb"F=([0-9A-F]) A=([0-9A-F])"
                          # Verdict classes and counters -- absent on bitstreams
                          # built before they were added, hence optional.
                          rb"(?: M=([0-9A-F]) N=([0-9A-F]{2}) C=([0-9A-F]) K=([0-9A-F]{2}))?")

# Class indices as in inference_arbiter / mlp_weights.
CLASS_NAMES = ["Bearing", "Misalign", "Normal", "Unbalance"]


def expected_class(scenario: str) -> Optional[int]:
    """Scenario name -> the class a correct verdict should report.

    Mirrors expected_class() in tb_top_system.sv, plus "unbal" so the
    2Nm_Unbalalnce_* captures -- misspelled in the dataset -- still score.
    """
    low = scenario.lower()
    if "normal" in low:
        return 2
    if any(k in low for k in ("bpfo", "bpfi", "bsf", "bearing")):
        return 0
    if "misalign" in low:
        return 1
    if "unbal" in low or "imbalance" in low:
        return 3
    return None

ERR_BIT_NAMES = ["UART_FRAME", "VIB_OVERRUN", "MLP_DROP",
                 "SPEC_DESYNC", "MDC_OVERRUN", "CNN_STALL"]
VERDICT_NAMES = {0b001: "Normal", 0b010: "Warning", 0b100: "Critical"}


def format_telemetry(t: dict) -> str:
    """One compact tag for the status line, e.g. fpga[rx=230784 Warning F=1111].

    `rx` is the unwrapped total (see poll_telemetry), which is what you want to
    compare against bytes= on the same line. It lags by up to one report period,
    so a small shortfall is bytes still in flight, not loss.
    """
    errs = [n for i, n in enumerate(ERR_BIT_NAMES) if t["err"] >> i & 1]
    parts = [f"rx={t['total']}", VERDICT_NAMES.get(t["status"], f"S=0b{t['status']:03b}")]
    if t["fault"]:
        parts.append(f"F={t['fault']:04b}")
    if t["alert"]:
        parts.append("ALERT")
    parts.append("E=" + (",".join(errs) if errs else "00"))
    return "fpga[" + " ".join(parts) + "]"


class SerialSink:
    """The real thing: a blocking 8N1 port. Whole frames per write.

    Also drains the receive direction, so a board running top_system_de0cv can
    report back while the stream is in flight. Reads are non-blocking
    (timeout=0) and bounded, so this cannot slow the stream down.
    """

    def __init__(self, port: str, baud: int, write_timeout: float = 5.0):
        import serial   # imported here so --dry-run works without pyserial
        self.port_name = port
        self.baud = baud
        self.port = serial.Serial(
            port=port, baudrate=baud, bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
            timeout=0, write_timeout=write_timeout,
            xonxoff=False, rtscts=False, dsrdtr=False,
        )
        time.sleep(0.2)                        # let the adapter settle
        self.port.reset_input_buffer()
        self.port.reset_output_buffer()
        self.bytes_written = 0
        self.telemetry: Optional[dict] = None
        self._rx = b""
        self._last_b: Optional[int] = None
        self._total_seen = 0

    def write(self, data: bytes) -> None:
        self.port.write(data)
        self.bytes_written += len(data)
        self.poll_telemetry()

    def poll_telemetry(self) -> Optional[dict]:
        """Keeps the most recent complete report the board has sent.

        Returns the freshest one, or None if the board has not reported since
        the last call. Nothing here blocks: the port was opened with timeout=0.

        The board's B field is a 16-bit counter, which at full rate wraps every
        ~5.7 s -- consecutive reports appear to go *backwards*. So the wrap is
        undone here with a modular difference and accumulated into `total`,
        counting bytes since this sink saw its first report. That is the figure
        worth comparing against bytes_written; raw B stays available as
        `bytes`.
        """
        try:
            chunk = self.port.read(4096)
        except Exception:                      # a closing port mid-shutdown
            return None
        if not chunk:
            return None
        # Bound the buffer: a board transmitting garbage must not grow it without
        # limit, and one report is only 25 bytes.
        self._rx = (self._rx + chunk)[-512:]
        found = None
        for m in TELEMETRY_RE.finditer(self._rx):
            found = m
        if found is None:
            return None
        raw_b = int(found.group(1), 16)
        if self._last_b is not None:
            self._total_seen += (raw_b - self._last_b) & 0xFFFF
        self._last_b = raw_b
        self.telemetry = {
            "bytes":  raw_b,
            "total":  self._total_seen,
            "err":    int(found.group(2), 16),
            "status": int(found.group(3), 16),
            "fault":  int(found.group(4), 16),
            "alert":  int(found.group(5), 16),
        }
        if found.group(6) is not None:
            self.telemetry.update({
                "mlp_class": int(found.group(6), 16),
                "mlp_count": int(found.group(7), 16),
                "cnn_class": int(found.group(8), 16),
                "cnn_count": int(found.group(9), 16),
            })
        self._rx = self._rx[found.end():]
        return self.telemetry

    def drain(self) -> None:
        self.port.flush()

    def close(self) -> None:
        try:
            self.port.flush()
        finally:
            self.port.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False


class DryRunSink:
    """No hardware: counts bytes, optionally records the stream to a file."""

    def __init__(self, record: Optional[Path] = None, baud: int = DEFAULT_BAUD):
        self.port_name = f"dry-run{'' if record is None else ' -> ' + str(record)}"
        self.baud = baud
        self.bytes_written = 0
        self._file = open(record, "wb") if record else None

    def write(self, data: bytes) -> None:
        self.bytes_written += len(data)
        if self._file:
            self._file.write(data)

    def drain(self) -> None:
        if self._file:
            self._file.flush()

    def close(self) -> None:
        if self._file:
            self._file.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False


# ============================================================================
# Pacing
# ============================================================================
class Pacer:
    """Holds the stream to a frame rate. rate <= 0 means "as fast as the port
    accepts", which for a blocking serial port is exactly the wire rate."""

    def __init__(self, frames_per_second: float, wire_frames_per_second: float):
        self.target = frames_per_second if frames_per_second > 0 else 0.0
        self.wire = wire_frames_per_second
        if self.target > self.wire:
            log.warning("frame rate %.1f/s exceeds what the wire carries (%.1f/s); "
                        "the port will cap it", self.target, self.wire)
        self._next = time.perf_counter()

    def wait(self, frames: int) -> None:
        if self.target <= 0:
            return
        self._next += frames / self.target
        delay = self._next - time.perf_counter()
        if delay > 0:
            time.sleep(delay)
        elif delay < -1.0:
            self._next = time.perf_counter()     # fell far behind; resync


# ============================================================================
# Interactive command channel
# ============================================================================
class CommandReader:
    """Reads stdin lines on a thread. Silent when stdin is not a terminal."""

    def __init__(self) -> None:
        self.queue: "queue.Queue[str]" = queue.Queue()
        self.enabled = sys.stdin is not None and sys.stdin.isatty()
        if self.enabled:
            thread = threading.Thread(target=self._pump, name="stdin", daemon=True)
            thread.start()

    def _pump(self) -> None:
        for line in sys.stdin:
            self.queue.put(line.strip())

    def poll(self) -> Optional[str]:
        try:
            return self.queue.get_nowait()
        except queue.Empty:
            return None


# ============================================================================
# Statistics and logging
# ============================================================================
@dataclass
class StreamStats:
    started: float = field(default_factory=time.perf_counter)
    last_report: float = field(default_factory=time.perf_counter)
    last_report_frames: int = 0

    def elapsed(self) -> float:
        return time.perf_counter() - self.started


def status_line(stream: FrameStream, sink, cfg: LinkConfig, stats: StreamStats) -> str:
    now = time.perf_counter()
    elapsed = now - stats.started
    window = now - stats.last_report
    recent = (stream.frames_sent - stats.last_report_frames) / window if window > 0 else 0.0
    stats.last_report = now
    stats.last_report_frames = stream.frames_sent

    mlp_due = stream.frames_sent // cfg.frames_per_round
    cnn_due = stream.frames_sent // cfg.frames_per_spec
    wraps = sum(stream.scenario.wraps)
    aux = stream.aggregator.physical()
    aux_tag = "" if stream.aggregator.complete else " FALLBACK"
    return (f"{stream.scenario.name:<24s} frames={stream.frames_sent:>9d} "
            f"({recent:6.1f}/s, avg {stream.frames_sent / elapsed if elapsed else 0:6.1f}/s) "
            f"bytes={sink.bytes_written:>11d} up={elapsed:8.1f}s "
            f"MLP~{mlp_due} CNN~{cnn_due} wraps={wraps} "
            f"aux[T_A={aux.get('temp_a_degC', 0):.2f}C T_B={aux.get('temp_b_degC', 0):.2f}C "
            f"I2={aux.get('current_A2', 0):.3f}A2{aux_tag}]"
            + (" " + format_telemetry(telem) if (telem := getattr(sink, "telemetry", None))
               else ""))


def setup_logging(log_path: Optional[Path], verbose: bool = False) -> Path:
    """Console at INFO (or DEBUG), file at DEBUG. Returns the log file path."""
    if log_path is None:
        log_dir = Path(__file__).resolve().parent / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / time.strftime("fpga_uart_%Y%m%d_%H%M%S.log")
    log_path.parent.mkdir(parents=True, exist_ok=True)

    root = logging.getLogger("fpga_uart")
    root.setLevel(logging.DEBUG)
    root.handlers.clear()

    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%H:%M:%S")
    console = logging.StreamHandler(sys.stdout)
    console.setLevel(logging.DEBUG if verbose else logging.INFO)
    console.setFormatter(fmt)
    root.addHandler(console)

    file_fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s")
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setLevel(logging.DEBUG)
    handler.setFormatter(file_fmt)
    root.addHandler(handler)
    return log_path


def log_link_summary(cfg: LinkConfig, baud: int, sink_name: str) -> None:
    per_frame = cfg.frame_seconds(baud)
    wire_fps = 1.0 / per_frame
    log.info("port        : %s @ %d baud, 8N1", sink_name, baud)
    log.info("frame       : %s", cfg.describe())
    log.info("wire rate   : %.3f ms/frame -> %.1f frames/s max", per_frame * 1e3, wire_fps)
    log.info("cadence     : one MLP verdict every %.1f s, one CNN verdict every %.1f s at full rate",
             cfg.frames_per_round * per_frame, cfg.frames_per_spec * per_frame)
    log.info("aux scaling : temperature mean >> %d, current mean-square >> %d, span %d frames",
             cfg.temp_shift, cfg.power_shift, cfg.frames_per_round)


def log_first_frame(frame: bytes, cfg: LinkConfig) -> None:
    """One-time dump of a frame the way the loopback script showed bytes."""
    n = cfg.bytes_per_word
    words = [int.from_bytes(frame[2 + i * n:2 + (i + 1) * n], "big", signed=True)
             for i in range(cfg.n_sensors)]
    log.info("first frame : %s", hexdump(frame))
    log.info("   sync=%02X %02X  words=%s  cksum=%02X",
             frame[0], frame[1], words, frame[-1])


# ============================================================================
# The main loop, shared by both drivers
# ============================================================================
BUILTIN_COMMANDS = """commands:
  q | quit | exit     stop streaming and exit
  s | status          print a status line now
  p | pause           stop sending (the FPGA waits; nothing times out between frames)
  r | resume          continue sending
  ? | help            this text"""


def run_stream(cfg: LinkConfig, stream: FrameStream, sink, pacer: Pacer, *,
               batch_frames: int = 16, status_every: float = 5.0,
               commands: Optional[CommandReader] = None,
               handle_command=None, on_tick=None,
               max_frames: int = 0, max_seconds: float = 0.0,
               extra_help: str = "") -> StreamStats:
    """Streams until 'quit', Ctrl+C, or a frame/time limit.

    `handle_command(text) -> bool` lets a driver add its own commands;
    `on_tick() -> bool` runs once per batch and is where a scheduler lives --
    returning True ends the run.
    """
    stats = StreamStats()
    paused = False
    stop = False
    first = True

    log.info("streaming; type 'help' for commands, Ctrl+C to stop")
    try:
        while not stop:
            # ---- commands -------------------------------------------------
            if commands is not None:
                while (text := commands.poll()) is not None:
                    word = text.split()[0].lower() if text else ""
                    if word in ("q", "quit", "exit"):
                        log.info("quit requested")
                        stop = True
                    elif word in ("s", "status"):
                        log.info("status      : %s", status_line(stream, sink, cfg, stats))
                    elif word in ("p", "pause"):
                        if not paused:
                            paused = True
                            sink.drain()
                            log.info("paused at %d frames (between frames, so the framer just waits)",
                                     stream.frames_sent)
                    elif word in ("r", "resume"):
                        if paused:
                            paused = False
                            pacer._next = time.perf_counter()
                            log.info("resumed")
                    elif word in ("?", "help"):
                        log.info("%s%s", BUILTIN_COMMANDS, ("\n" + extra_help) if extra_help else "")
                    elif text and handle_command is not None and handle_command(text):
                        pass
                    elif text:
                        log.warning("unknown command %r (try 'help')", text)
            if stop:
                break

            if paused:
                time.sleep(0.05)
                continue

            if on_tick is not None and on_tick():
                stop = True
                break

            # ---- one batch of whole frames --------------------------------
            batch = stream.next_batch(batch_frames)
            if first:
                log_first_frame(batch[:cfg.frame_bytes], cfg)
                first = False
            sink.write(batch)
            pacer.wait(batch_frames)

            # ---- aux block bookkeeping ------------------------------------
            agg = stream.aggregator
            if agg.last_block is not None:
                block = agg.last_block
                agg.last_block = None
                warn = agg.out_of_range()
                log.debug("aux block %d closed after %d frames: %s%s",
                          agg.blocks_closed, stream.frames_sent,
                          " ".join(f"{k}={v:.3f}" if isinstance(v, float) else f"{k}={v}"
                                   for k, v in block.items()),
                          ("  OUT OF TRAINED RANGE: " + "; ".join(warn)) if warn else "")
                if warn and agg.blocks_closed == 1:
                    log.warning("aux inputs outside the MLP's trained range: %s", "; ".join(warn))

            # ---- periodic status ------------------------------------------
            if status_every > 0 and (time.perf_counter() - stats.last_report) >= status_every:
                log.info("status      : %s", status_line(stream, sink, cfg, stats))

            # ---- limits ---------------------------------------------------
            if max_frames > 0 and stream.frames_sent >= max_frames:
                log.info("frame limit %d reached", max_frames)
                stop = True
            if max_seconds > 0 and stats.elapsed() >= max_seconds:
                log.info("time limit %.0f s reached", max_seconds)
                stop = True
    except KeyboardInterrupt:
        log.info("Ctrl+C -- stopping after the current frame")

    try:
        sink.drain()
    except Exception as exc:                                     # noqa: BLE001
        log.warning("drain failed: %s", exc)

    elapsed = stats.elapsed()
    log.info("=" * 70)
    log.info("frames sent   : %d  (%d scenario switch(es))", stream.frames_sent, stream.switches)
    log.info("bytes sent    : %d", sink.bytes_written)
    log.info("elapsed       : %.1f s  -> %.1f frames/s average",
             elapsed, stream.frames_sent / elapsed if elapsed > 0 else 0.0)
    log.info("verdicts due  : MLP %d, CNN %d (by frame count; check the LEDs)",
             stream.frames_sent // cfg.frames_per_round,
             stream.frames_sent // cfg.frames_per_spec)
    log.info("last scenario : %s (%d frames, wraps %s)", stream.scenario.name,
             stream.frames_in_scenario, stream.scenario.wraps)
    log.info("=" * 70)
    return stats
