#!/usr/bin/env python3
"""
run_schedule.py -- drive the FPGA through one scenario or a timed mix of them.

    # one scenario, forever (same as stream_scenario.py)
    ./run_schedule.py --scenario 0Nm_BPFI_10

    # a timed sequence, looped until told to stop
    ./run_schedule.py --schedule "0Nm_BPFI_10:120,2Nm_Normal:60,4Nm_Unbalance_1751mg:90"

    # the same from a file (one "name seconds" per line, '#' comments), order
    # shuffled on every pass so the fabric sees the scenarios mixed
    ./run_schedule.py --schedule-file bench.txt --shuffle

Scenario changes are applied at an MLP round boundary (every
FRAMES_PER_ROUND frames) so the fabric never sees an FFT frame straddling
two machines; --no-align switches immediately instead.

While running, type commands followed by Enter:

    switch <name> [s]   jump to <name> now (for s seconds, then resume the plan)
    next                advance to the next entry immediately
    hold / release      freeze / unfreeze the automatic advance
    list                show the scenarios on disk
    plan                show the schedule and where we are in it
    q, status, pause, resume, help   as in stream_scenario.py

Ctrl+C also stops cleanly. Every event goes to the console and the log file.
"""
from __future__ import annotations

import argparse
import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fpga_uart_link as link                                   # noqa: E402

log = link.log

EXTRA_HELP = """schedule commands:
  switch <name> [s]   jump to <name> now, for s seconds (default: this entry's)
  next                advance to the next entry immediately
  hold | release      freeze / unfreeze the automatic advance
  list                scenarios available on disk
  plan                the schedule and the current position"""


# ============================================================================
# Schedule parsing
# ============================================================================
def parse_schedule(text: str) -> list[tuple[str, float]]:
    """'A:120,B:60' -> [('A', 120.0), ('B', 60.0)]. Seconds default to 60."""
    entries = []
    for item in (piece.strip() for piece in text.split(",")):
        if not item:
            continue
        name, _, seconds = item.partition(":")
        entries.append((name.strip(), float(seconds) if seconds.strip() else 60.0))
    return entries


def parse_schedule_file(path: Path) -> list[tuple[str, float]]:
    entries = []
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.replace(":", " ").split()
        entries.append((parts[0], float(parts[1]) if len(parts) > 1 else 60.0))
    return entries


# ============================================================================
# Scheduler
# ============================================================================
class Scheduler:
    """Walks the schedule, asking the FrameStream to switch when time is up."""

    def __init__(self, stream: link.FrameStream, cache: link.ScenarioCache,
                 entries: list[tuple[str, float]], loop: bool, shuffle: bool):
        self.stream = stream
        self.cache = cache
        self.entries = list(entries)
        self.loop = loop
        self.shuffle = shuffle
        self.index = 0
        self.passes = 0
        self.held = False
        self.finished = False
        self.requested = False
        self.started = time.perf_counter()
        self.override: tuple[str, float] | None = None     # a manual 'switch'
        self._prefetch_following()
        log.info("plan        : %s%s", self.describe(),
                 "  (looping)" if loop else "  (one pass)")

    # ---- helpers -----------------------------------------------------------
    def describe(self) -> str:
        return " -> ".join(f"{n}:{s:g}s" for n, s in self.entries)

    def current(self) -> tuple[str, float]:
        return self.override if self.override is not None else self.entries[self.index]

    def _following_index(self) -> int | None:
        nxt = self.index + 1
        if nxt < len(self.entries):
            return nxt
        return 0 if self.loop else None

    def _prefetch_following(self) -> None:
        nxt = self._following_index()
        if nxt is not None:
            self.cache.prefetch(self.entries[nxt][0])

    def remaining(self) -> float:
        _, seconds = self.current()
        return max(0.0, seconds - (time.perf_counter() - self.started))

    def position(self) -> str:
        name, seconds = self.current()
        return (f"pass {self.passes + 1}, entry {self.index + 1}/{len(self.entries)} "
                f"{name} ({self.remaining():.0f}/{seconds:g} s left)"
                + (" [held]" if self.held else "") + (" [switch pending]" if self.requested else ""))

    # ---- transitions -------------------------------------------------------
    def advance(self, reason: str = "time up") -> None:
        nxt = self._following_index()
        if nxt is None:
            log.info("schedule complete (%s); stopping", reason)
            self.finished = True
            return
        if nxt == 0:
            self.passes += 1
            if self.shuffle:
                random.shuffle(self.entries)
                log.info("pass %d: shuffled order -> %s", self.passes + 1, self.describe())
        self.index = nxt
        self.override = None
        self._request(self.entries[nxt][0], reason)

    def jump(self, name: str, seconds: float | None) -> None:
        """Manual switch, played in place of the current entry; the schedule
        itself is untouched and resumes with the following entry."""
        _, default_seconds = self.entries[self.index]
        self.override = (name, seconds if seconds is not None else default_seconds)
        self._request(name, "manual switch")

    def _request(self, name: str, reason: str) -> None:
        log.info("scheduler   : %s -> %s", reason, name)
        self.stream.request_switch(name)
        self.requested = True

    def tick(self) -> bool:
        """Called once per batch. Returns True when the run should end."""
        if self.finished:
            return True
        if self.requested and self.stream.pending is None:
            # The FrameStream applied the switch on a boundary; the clock
            # for this entry starts now.
            self.requested = False
            self.started = time.perf_counter()
            self._prefetch_following()
        if self.held or self.requested:
            return False
        if self.remaining() <= 0.0:
            self.advance()
        return self.finished

    # ---- commands ----------------------------------------------------------
    def handle(self, text: str, data_root: Path) -> bool:
        parts = text.split()
        word = parts[0].lower()
        if word == "switch" and len(parts) >= 2:
            seconds = float(parts[2]) if len(parts) >= 3 else None
            self.jump(parts[1], seconds)
            return True
        if word in ("next", "skip"):
            self.advance("manual next")
            return True
        if word == "hold":
            self.held = True
            log.info("scheduler held on %s (use 'release' or 'next')", self.current()[0])
            return True
        if word == "release":
            self.held = False
            self.started = time.perf_counter()
            log.info("scheduler released")
            return True
        if word == "list":
            log.info("scenarios   : %s", ", ".join(link.list_scenarios(data_root)))
            return True
        if word == "plan":
            log.info("plan        : %s", self.describe())
            log.info("position    : %s", self.position())
            return True
        return False


# ============================================================================
# CLI
# ============================================================================
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream one scenario or a timed mix of scenarios to top_system over UART.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    what = parser.add_mutually_exclusive_group()
    what.add_argument("--scenario", "-s", help="single scenario, streamed forever")
    what.add_argument("--schedule", help='"name:seconds,name:seconds,..."')
    what.add_argument("--schedule-file", type=Path, help="file with one 'name seconds' per line")
    parser.add_argument("--shuffle", action="store_true", help="shuffle the order on every pass")
    parser.add_argument("--once", action="store_true", help="one pass through the schedule, then stop")
    parser.add_argument("--no-align", action="store_true",
                        help="switch scenarios immediately instead of at an MLP round boundary")
    parser.add_argument("--list", action="store_true", help="list available scenarios and exit")
    parser.add_argument("--port", "-p", default=link.DEFAULT_PORT)
    parser.add_argument("--baud", "-b", type=int, default=link.DEFAULT_BAUD,
                        help="must match top_system's BAUD_RATE")
    parser.add_argument("--data-root", type=Path, default=None,
                        help="dataset_q915 directory (default: found from the repo)")
    parser.add_argument("--package", type=Path, default=None,
                        help="system_types_pkg.sv to read the frame geometry from")
    parser.add_argument("--agg-span", type=int, default=None,
                        help="aux aggregation span in frames; overrides DECIM_RATE*FFT_HOP")
    parser.add_argument("--frame-rate", type=float, default=0.0,
                        help="frames per second; 0 = as fast as the port carries")
    parser.add_argument("--batch", type=int, default=16, help="frames per write()")
    parser.add_argument("--status-every", type=float, default=5.0,
                        help="seconds between status lines; 0 disables")
    parser.add_argument("--max-frames", type=int, default=0, help="stop after N frames; 0 = never")
    parser.add_argument("--max-seconds", type=float, default=0.0, help="stop after N s; 0 = never")
    parser.add_argument("--dry-run", action="store_true",
                        help="build and count frames without opening a port")
    parser.add_argument("--record", type=Path, default=None,
                        help="with --dry-run, also write the byte stream to this file")
    parser.add_argument("--log", type=Path, default=None, help="log file (default: logs/...)")
    parser.add_argument("--verbose", "-v", action="store_true", help="debug lines on the console")
    return parser.parse_args()


def resolve_paths(args: argparse.Namespace) -> tuple[Path, Path | None]:
    root = link.find_repo_root()
    data_root = args.data_root or (root / "Scripts" / "process_dataset" / "dataset_q915" if root else None)
    if data_root is None or not data_root.is_dir():
        sys.exit("cannot find the dataset_q915 directory; pass --data-root")
    package = args.package or (root / "RTL" / "top_system" / "rtl" / "system_types_pkg.sv" if root else None)
    return data_root, (package if package and package.is_file() else None)


def main() -> int:
    args = parse_args()
    data_root, package = resolve_paths(args)

    if args.list:
        for line in link.describe_scenarios(data_root):
            print(line)
        return 0

    # ---- what to play -------------------------------------------------------
    if args.schedule:
        entries = parse_schedule(args.schedule)
    elif args.schedule_file:
        entries = parse_schedule_file(args.schedule_file)
    else:
        entries = [(args.scenario or "0Nm_Normal", float("inf"))]
    if not entries:
        sys.exit("empty schedule")

    available = set(link.list_scenarios(data_root))
    unknown = [n for n, _ in entries if n not in available]
    if unknown:
        sys.exit(f"unknown scenario(s): {', '.join(unknown)}\navailable: {', '.join(sorted(available))}")

    log_path = link.setup_logging(args.log, args.verbose)
    cfg = (link.LinkConfig.from_package(package) if package else link.LinkConfig()).with_span(args.agg_span)

    log.info("log file    : %s", log_path)
    log.info("data root   : %s", data_root)
    if package is None:
        log.warning("system_types_pkg.sv not found; using built-in defaults (%s)", cfg.describe())

    try:
        sink = (link.DryRunSink(args.record, args.baud) if args.dry_run
                else link.SerialSink(args.port, args.baud))
    except Exception as exc:                                       # noqa: BLE001
        log.error("cannot open %s: %s", args.port, exc)
        return 2

    with sink:
        link.log_link_summary(cfg, args.baud, sink.port_name)
        cache = link.ScenarioCache(data_root, cfg)
        stream = link.FrameStream(cfg, cache, entries[0][0], align_switch=not args.no_align)

        single = len(entries) == 1 and entries[0][1] == float("inf")
        scheduler = None if single else Scheduler(stream, cache, entries,
                                                  loop=not args.once, shuffle=args.shuffle)
        if single:
            log.info("scenario    : %s, forever", entries[0][0])

        def handle(text: str) -> bool:
            if scheduler is not None:
                return scheduler.handle(text, data_root)
            word = text.split()[0].lower()
            if word == "switch" and len(text.split()) >= 2:
                stream.request_switch(text.split()[1])
                return True
            if word == "list":
                log.info("scenarios   : %s", ", ".join(sorted(available)))
                return True
            return False

        pacer = link.Pacer(args.frame_rate, 1.0 / cfg.frame_seconds(args.baud))
        commands = link.CommandReader()
        link.run_stream(cfg, stream, sink, pacer, batch_frames=args.batch,
                        status_every=args.status_every, commands=commands,
                        handle_command=handle,
                        on_tick=(scheduler.tick if scheduler else None),
                        max_frames=args.max_frames, max_seconds=args.max_seconds,
                        extra_help=EXTRA_HELP if scheduler else "switch <name>   jump to another scenario\n  list            scenarios on disk")
        cache.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
