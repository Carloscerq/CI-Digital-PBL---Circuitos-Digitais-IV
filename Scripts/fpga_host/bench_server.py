#!/usr/bin/env python3
"""
bench_server.py -- local web dashboard for the FPGA bench.

    python3 bench_server.py                       # then open http://127.0.0.1:8050
    python3 bench_server.py --port /dev/ttyUSB1 --http-port 9000
    python3 bench_server.py --settle-rounds 3     # longer guard after a switch

It owns the serial port, so stop stream_scenario.py / run_schedule.py first.
One I/O thread does everything on the port: it streams the chosen scenarios
(the same FrameStream the CLI scripts use) and reads back the telemetry that
top_system_de0cv sends on GPIO_0[4]. Each new MLP or CNN verdict is scored
against the class the scenario name implies, and the page at / polls
/api/state once a second to draw it.

>>> SCORING_NOTE <<<
A verdict is only scored when the whole window that produced it lies inside
the scenario being streamed when it arrives:

    MLP  frames_in_scenario >= frames_per_round * (1 + settle_rounds)
    CNN  frames_in_scenario >= frames_per_spec + frames_per_round * settle_rounds

frames_per_round (2048) is one MLP window and frames_per_spec (65536) one CNN
spectrogram. settle_rounds of extra margin covers pipeline latency, the
telemetry's 500 ms cadence, and the decimator/LMS state that still carries the
previous scenario for a while after a switch. Verdicts outside that are logged
as "transição" and kept out of every accuracy figure. At full rate that makes
the first scored CNN verdict ~140 s after a start or switch -- inherent to a
32-row spectrogram, not a limitation of the page.

>>> SIMULATE_NOTE <<<
--simulate replaces the port with SimSink, a stand-in that answers with the
same telemetry the wrapper sends: byte count, verdicts at the real cadence
(one MLP verdict per frames_per_round frames, one CNN per frames_per_spec),
and status_leds derived the way inference_arbiter derives them. Each verdict
is the expected class with probability --sim-accuracy, otherwise another
class. --sim-speed multiplies the frame rate so a CNN verdict does not take
136 s. It exists to exercise the page with no board attached; nothing it
reports says anything about the hardware.

>>> LOSS_NOTE <<<
While streaming, the FPGA's byte count lags the host's by whatever is in
flight, so no loss figure is honest then. Once the port has been idle for
IDLE_SETTLE_S, every byte sent has either arrived or been lost, and
sent - received is exact. That is the only loss number the page shows.
"""
from __future__ import annotations

import argparse
import collections
import csv
import io
import json
import logging
import random
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fpga_uart_link as link                                   # noqa: E402

HERE = Path(__file__).resolve().parent
PAGE = HERE / "dashboard" / "index.html"
IDLE_SETTLE_S = 1.5          # see LOSS_NOTE
SERIES_KEEP = 900            # 1 s samples -> 15 min of throughput history
VERDICT_KEEP = 5000

log = logging.getLogger("bench")


def resolve_paths(data_root: Optional[Path], package: Optional[Path]):
    """Same search as stream_scenario.resolve_paths, without the argparse coupling."""
    root = link.find_repo_root()
    if data_root is None and root is not None:
        for candidate in (root / "Scripts" / "dataset_q915",
                          root / "Scripts" / "process_dataset" / "dataset_q915"):
            if candidate.is_dir():
                data_root = candidate
                break
    if data_root is None or not data_root.is_dir():
        sys.exit("cannot find the dataset_q915 directory; pass --data-root")
    if package is None and root is not None:
        package = root / "RTL" / "top_system" / "rtl" / "system_types_pkg.sv"
    return data_root, (package if package and package.is_file() else None)


class SimSink:
    """Stand-in for SerialSink when no board is attached. See SIMULATE_NOTE."""

    def __init__(self, cfg: link.LinkConfig, scenario_of, accuracy: dict,
                 speed: float = 1.0, seed: int = 1):
        self.cfg = cfg
        # Compress the report period with the frame rate. Left at the board's
        # 500 ms, a sped-up MLP would vote several times per report and the
        # page would (correctly) flag the collapsed verdicts as missed.
        self.period = 0.5 / max(1.0, speed)
        self.port_name = "simulado"
        self.scenario_of = scenario_of              # () -> current scenario name
        self.accuracy = accuracy
        self.rng = random.Random(seed)
        self.bytes_written = 0
        self.telemetry: Optional[dict] = None
        self._frames = 0
        self._next_report = time.monotonic() + self.period
        self._mlp = [2, 0]                          # [class, count]
        self._cnn = [2, 0]
        self._mlp_fault = self._cnn_fault = False
        self.poll_telemetry()

    def _verdict(self, model: str) -> int:
        exp = link.expected_class(self.scenario_of() or "")
        if exp is not None and self.rng.random() < self.accuracy[model]:
            return exp
        return self.rng.choice([c for c in range(4) if c != exp])

    def write(self, data: bytes) -> None:
        self.bytes_written += len(data)
        before = self._frames
        self._frames += len(data) // self.cfg.frame_bytes
        for model, period, slot in (("MLP", self.cfg.frames_per_round, self._mlp),
                                    ("CNN", self.cfg.frames_per_spec, self._cnn)):
            for _ in range(self._frames // period - before // period):
                slot[0] = self._verdict(model)
                slot[1] = (slot[1] + 1) & 0xFF
                if model == "MLP":
                    self._mlp_fault = slot[0] != 2
                else:
                    self._cnn_fault = slot[0] != 2
        self.poll_telemetry()

    def poll_telemetry(self) -> Optional[dict]:
        if time.monotonic() < self._next_report:
            return None
        self._next_report = time.monotonic() + self.period
        both, either = self._mlp_fault and self._cnn_fault, self._mlp_fault or self._cnn_fault
        self.telemetry = {
            "bytes": self.bytes_written & 0xFFFF, "total": self.bytes_written, "err": 0,
            "status": 0b100 if both else 0b010 if either else 0b001,
            "fault": 0xF if self._mlp_fault else 0, "alert": int(either),
            "mlp_class": self._mlp[0], "mlp_count": self._mlp[1],
            "cnn_class": self._cnn[0], "cnn_count": self._cnn[1],
        }
        return self.telemetry

    def drain(self) -> None:
        pass

    def close(self) -> None:
        pass


class Bench:
    """Everything that touches the port, plus the scoring. Thread-safe via `lock`."""

    def __init__(self, port: str, baud: int, data_root: Path, package: Optional[Path],
                 batch: int, settle_rounds: int, log_dir: Path,
                 simulate: bool = False, sim_speed: float = 1.0,
                 sim_accuracy: Optional[dict] = None):
        self.cfg = link.LinkConfig.from_package(package) if package else link.LinkConfig()
        self.baud = baud
        self.port_name = port
        self.data_root = data_root
        self.batch = batch
        self.settle_rounds = settle_rounds
        self.simulate = simulate
        self.fps = (1.0 / self.cfg.frame_seconds(baud)) * (sim_speed if simulate else 1.0)
        if simulate:
            self.sink = SimSink(self.cfg, lambda: self.stream.scenario.name if self.stream else None,
                                sim_accuracy or {"MLP": 0.8, "CNN": 0.9}, speed=sim_speed)
            self.port_name = f"simulado ×{sim_speed:g}"
        else:
            self.sink = link.SerialSink(port, baud)
        self.cache = link.ScenarioCache(data_root, self.cfg)
        self.lock = threading.Lock()
        self.quit = False

        self.scenarios = []
        for name in link.list_scenarios(data_root):
            have = link.scenario_modalities(data_root, name)
            exp = link.expected_class(name)
            self.scenarios.append({
                "name": name,
                "complete": all(have.values()),
                "expected": exp,
                "expected_name": link.CLASS_NAMES[exp] if exp is not None else None,
            })

        log_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = log_dir / f"bench_{datetime.now():%Y%m%d_%H%M%S}.jsonl"
        self._reset_stats_locked()

        # stream state (declared before the I/O thread starts)
        self.stream: Optional[link.FrameStream] = None
        self.pacer: Optional[link.Pacer] = None
        self.running = False
        self.plan: list[tuple[str, float]] = []
        self.plan_idx = 0
        self.plan_loop = False
        self.plan_switched_at = 0.0
        self.last_write = 0.0

        self.thread = threading.Thread(target=self._io_loop, name="bench-io", daemon=True)
        self.thread.start()

    # ------------------------------------------------------------ bookkeeping
    def _reset_stats_locked(self) -> None:
        self.t0 = time.monotonic()
        self.verdicts: collections.deque = collections.deque(maxlen=VERDICT_KEEP)
        self.series: collections.deque = collections.deque(maxlen=SERIES_KEEP)
        self.last_n: Optional[int] = None
        self.last_k: Optional[int] = None
        self.missed = {"MLP": 0, "CNN": 0}
        self._telem_seen = None
        self._last_sample = 0.0
        # Loss accounting: both counters restart from the next report.
        self.rx_base: Optional[int] = None
        self.sent_base = 0

    def _now(self) -> float:
        return time.monotonic() - self.t0

    # ---------------------------------------------------------------- control
    def start(self, plan: list[tuple[str, float]], loop: bool) -> None:
        names = {s["name"] for s in self.scenarios}
        for name, _ in plan:
            if name not in names:
                raise ValueError(f"unknown scenario {name!r}")
        # Loading a scenario takes a second or more; do it here, off the I/O
        # thread, so the telemetry keeps flowing while the page waits.
        stream = link.FrameStream(self.cfg, self.cache, plan[0][0])
        # A real port blocks at the wire rate, so no pacing is needed there;
        # the simulated one accepts instantly and must be held to self.fps.
        pacer = (link.Pacer(self.fps, self.fps) if self.simulate
                 else link.Pacer(0.0, self.fps))
        for name, _ in plan[1:2]:
            self.cache.prefetch(name)
        with self.lock:
            self.stream, self.pacer = stream, pacer
            self.plan, self.plan_idx, self.plan_loop = plan, 0, loop
            self.plan_switched_at = time.monotonic()
            self.running = True
        log.info("start: %s%s", ", ".join(f"{n}:{s:g}s" if s else n for n, s in plan),
                 " (loop)" if loop else "")

    def stop(self) -> None:
        with self.lock:
            self.running = False
        log.info("stop")

    def reset_stats(self) -> None:
        with self.lock:
            self._reset_stats_locked()

    def _schedule_tick_locked(self) -> None:
        """Advances a multi-scenario plan; 0 s means 'until stopped'."""
        name, seconds = self.plan[self.plan_idx]
        if seconds <= 0 or time.monotonic() - self.plan_switched_at < seconds:
            return
        nxt = self.plan_idx + 1
        if nxt >= len(self.plan):
            if not self.plan_loop:
                self.running = False
                log.info("plan finished")
                return
            nxt = 0
        self.plan_idx = nxt
        self.plan_switched_at = time.monotonic()
        # FrameStream applies it at the next MLP round boundary (align_switch).
        self.stream.request_switch(self.plan[nxt][0])
        if nxt + 1 < len(self.plan):
            self.cache.prefetch(self.plan[nxt + 1][0])

    # -------------------------------------------------------------- I/O loop
    def _io_loop(self) -> None:
        while not self.quit:
            try:
                with self.lock:
                    running = self.running
                    if running:
                        self._schedule_tick_locked()
                        running = self.running
                    stream, pacer = self.stream, self.pacer
                if running and stream is not None:
                    batch = stream.next_batch(self.batch)
                    self.sink.write(batch)           # also polls telemetry
                    self.last_write = time.monotonic()
                    pacer.wait(self.batch)
                else:
                    time.sleep(0.05)
                    self.sink.poll_telemetry()
                with self.lock:
                    self._ingest_locked()
            except Exception:                        # noqa: BLE001 -- keep serving
                log.exception("I/O loop error; stopping the stream")
                with self.lock:
                    self.running = False
                time.sleep(0.5)

    def _ingest_locked(self) -> None:
        now = self._now()
        t = self.sink.telemetry
        if t is not None and t is not self._telem_seen:
            self._telem_seen = t
            if self.rx_base is None:
                self.rx_base = t["total"]
                self.sent_base = self.sink.bytes_written
            if "mlp_count" in t:
                self._verdicts_from(t, "MLP", "mlp_count", "mlp_class")
                self._verdicts_from(t, "CNN", "cnn_count", "cnn_class")
        if now - self._last_sample >= 1.0:
            self._last_sample = now
            tt = self.sink.telemetry
            self.series.append({
                "t": round(now, 2),
                "sent": self.sink.bytes_written - self.sent_base,
                "rx": (tt["total"] - self.rx_base) if (tt and self.rx_base is not None) else None,
            })

    def _verdicts_from(self, t: dict, model: str, count_key: str, class_key: str) -> None:
        count = t[count_key]
        last = self.last_n if model == "MLP" else self.last_k
        if last is None:                              # first report: baseline only
            self._set_last(model, count)
            return
        delta = (count - last) & 0xFF
        if delta == 0:
            return
        self._set_last(model, count)
        if delta > 1:                                 # impossible at 500 ms / 4.3 s,
            self.missed[model] += delta - 1           # but say so rather than hide it
        self._record(model, t[class_key])

    def _set_last(self, model: str, count: int) -> None:
        if model == "MLP":
            self.last_n = count
        else:
            self.last_k = count

    def _clean_threshold(self, model: str) -> int:
        """Frames the current scenario needs before a verdict counts. See SCORING_NOTE."""
        rnd = self.cfg.frames_per_round
        if model == "MLP":
            return rnd * (1 + self.settle_rounds)
        return self.cfg.frames_per_spec + rnd * self.settle_rounds

    def _record(self, model: str, cls: int) -> None:
        stream = self.stream
        scen = stream.scenario.name if stream is not None else None
        fis = stream.frames_in_scenario if stream is not None else 0
        exp = link.expected_class(scen) if scen else None
        clean = bool(self.running and scen and fis >= self._clean_threshold(model))
        entry = {
            "t": round(self._now(), 2),
            "wall": datetime.now().strftime("%H:%M:%S"),
            "model": model,
            "cls": cls,
            "cls_name": link.CLASS_NAMES[cls],
            "scenario": scen,
            "expected": exp,
            "expected_name": link.CLASS_NAMES[exp] if exp is not None else None,
            "complete": bool(stream.scenario.aux_complete) if stream is not None else None,
            "frames_in_scenario": fis,
            "clean": clean,
            "correct": (cls == exp) if (clean and exp is not None) else None,
        }
        self.verdicts.append(entry)
        with self.log_path.open("a") as fh:
            fh.write(json.dumps(entry) + "\n")

    # ------------------------------------------------------------ reporting
    def state(self) -> dict:
        with self.lock:
            t = self.sink.telemetry
            stream = self.stream
            now_m = time.monotonic()
            idle = (not self.running) and (now_m - self.last_write >= IDLE_SETTLE_S)
            sent = self.sink.bytes_written - self.sent_base
            rx = (t["total"] - self.rx_base) if (t and self.rx_base is not None) else None
            verdicts = list(self.verdicts)

            cur = None
            if stream is not None:
                scen = stream.scenario.name
                exp = link.expected_class(scen)
                fis = stream.frames_in_scenario
                cur = {
                    "scenario": scen,
                    "expected": exp,
                    "expected_name": link.CLASS_NAMES[exp] if exp is not None else None,
                    "complete": bool(stream.scenario.aux_complete),
                    "frames_in_scenario": fis,
                    "frames_sent": stream.frames_sent,
                    "pending": stream.pending,
                    "mlp_ready_in": max(0, self._clean_threshold("MLP") - fis),
                    "cnn_ready_in": max(0, self._clean_threshold("CNN") - fis),
                    "cnn_threshold": self._clean_threshold("CNN"),
                    "plan_idx": self.plan_idx,
                    "plan": [{"name": n, "seconds": s} for n, s in self.plan],
                }

            return {
                "port": self.port_name,
                "baud": self.baud,
                "running": self.running,
                "uptime": round(self._now(), 1),
                "frame_bytes": self.cfg.frame_bytes,
                "frames_per_second": self.fps,
                "simulated": self.simulate,
                "frames_per_round": self.cfg.frames_per_round,
                "frames_per_spec": self.cfg.frames_per_spec,
                "settle_rounds": self.settle_rounds,
                "telemetry": t,
                "has_classes": bool(t and "mlp_count" in t),
                "link": {
                    "sent": sent,
                    "rx": rx,
                    "idle": idle,
                    "loss": (sent - rx) if (idle and rx is not None) else None,
                },
                "current": cur,
                "missed": dict(self.missed),
                "series": list(self.series),
                "verdicts": verdicts[-300:],
                "summary": summarize(verdicts),
                "log_file": str(self.log_path),
            }

    def verdicts_csv(self) -> str:
        with self.lock:
            rows = list(self.verdicts)
        out = io.StringIO()
        cols = ["wall", "t", "model", "scenario", "expected_name", "cls_name",
                "clean", "correct", "complete", "frames_in_scenario"]
        w = csv.DictWriter(out, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
        return out.getvalue()

    def close(self) -> None:
        self.quit = True
        self.thread.join(timeout=2)
        self.cache.close()
        self.sink.close()


def summarize(verdicts: list[dict]) -> dict:
    """Accuracy, confusion matrices and per-scenario rows over scored verdicts."""
    out = {}
    for model in ("MLP", "CNN"):
        scored = [v for v in verdicts if v["model"] == model and v["correct"] is not None]
        conf = [[0] * 4 for _ in range(4)]            # [expected][predicted]
        for v in scored:
            conf[v["expected"]][v["cls"]] += 1
        # Fault-vs-normal is what status_leds actually reports, so score it too:
        # a Misalign called Bearing is still a caught fault.
        detect = sum(1 for v in scored if (v["cls"] == 2) == (v["expected"] == 2))
        out[model] = {
            "total": sum(1 for v in verdicts if v["model"] == model),
            "scored": len(scored),
            "correct": sum(1 for v in scored if v["correct"]),
            "detect_correct": detect,
            "confusion": conf,
        }

    per = collections.OrderedDict()
    for v in verdicts:
        if v["correct"] is None:
            continue
        row = per.setdefault(v["scenario"], {
            "scenario": v["scenario"], "expected_name": v["expected_name"],
            "complete": v["complete"],
            "MLP": {"n": 0, "correct": 0}, "CNN": {"n": 0, "correct": 0}})
        row[v["model"]]["n"] += 1
        row[v["model"]]["correct"] += int(v["correct"])
    out["per_scenario"] = list(per.values())
    return out


def make_handler(bench: Bench):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):            # keep the console readable
            log.debug("http: " + fmt, *args)

        def _send(self, code: int, body: bytes, ctype: str, extra: Optional[dict] = None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, obj, code: int = 200):
            self._send(code, json.dumps(obj).encode(), "application/json")

        def do_GET(self):
            path = self.path.split("?")[0]
            if path in ("/", "/index.html"):
                self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            elif path == "/api/state":
                self._json(bench.state())
            elif path == "/api/scenarios":
                self._json(bench.scenarios)
            elif path == "/api/verdicts.csv":
                self._send(200, bench.verdicts_csv().encode(), "text/csv; charset=utf-8",
                           {"Content-Disposition": 'attachment; filename="vereditos.csv"'})
            else:
                self._json({"error": "not found"}, 404)

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                return self._json({"error": "bad json"}, 400)
            path = self.path.split("?")[0]
            try:
                if path == "/api/start":
                    plan = [(p["name"], float(p.get("seconds") or 0)) for p in body["plan"]]
                    if not plan:
                        raise ValueError("empty plan")
                    bench.start(plan, bool(body.get("loop")))
                elif path == "/api/stop":
                    bench.stop()
                elif path == "/api/reset":
                    bench.reset_stats()
                else:
                    return self._json({"error": "not found"}, 404)
            except (KeyError, ValueError, FileNotFoundError) as exc:
                return self._json({"error": str(exc)}, 400)
            self._json({"ok": True})

    return Handler


def main() -> int:
    ap = argparse.ArgumentParser(description="Local web dashboard for the FPGA bench.")
    ap.add_argument("--port", "-p", default="/dev/ttyUSB0")
    ap.add_argument("--baud", "-b", type=int, default=115200)
    ap.add_argument("--data-root", type=Path, default=None)
    ap.add_argument("--package", type=Path, default=None)
    ap.add_argument("--batch", type=int, default=16, help="frames per write()")
    ap.add_argument("--settle-rounds", type=int, default=1,
                    help="extra MLP rounds of margin before a verdict is scored")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--http-port", type=int, default=8050)
    ap.add_argument("--simulate", action="store_true",
                    help="no board: answer with SimSink instead of the port (see SIMULATE_NOTE)")
    ap.add_argument("--sim-speed", type=float, default=20.0,
                    help="with --simulate, frame-rate multiplier (default 20: a CNN verdict every ~7 s)")
    ap.add_argument("--sim-accuracy", type=float, nargs=2, default=[0.8, 0.9],
                    metavar=("MLP", "CNN"), help="with --simulate, P(verdict == expected)")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")
    data_root, package = resolve_paths(args.data_root, args.package)
    try:
        bench = Bench(args.port, args.baud, data_root, package, args.batch,
                      args.settle_rounds, HERE / "logs",
                      simulate=args.simulate, sim_speed=args.sim_speed,
                      sim_accuracy={"MLP": args.sim_accuracy[0], "CNN": args.sim_accuracy[1]})
    except Exception as exc:                          # noqa: BLE001
        log.error("cannot open %s: %s", args.port, exc)
        return 2

    server = ThreadingHTTPServer((args.host, args.http_port), make_handler(bench))
    log.info("dados       : %s", data_root)
    log.info("porta       : %s @ %d", bench.port_name, args.baud)
    log.info("vereditos   : %s", bench.log_path)
    log.info("abra        : http://%s:%d", args.host, args.http_port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        bench.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
