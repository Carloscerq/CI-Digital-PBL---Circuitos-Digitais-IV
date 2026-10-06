#!/usr/bin/env python3
"""
stream_scenario.py -- feed the FPGA one capture scenario over UART, forever.

    ./stream_scenario.py --scenario 0Nm_BPFI_10
    ./stream_scenario.py --scenario 2Nm_Normal --port /dev/ttyUSB1
    ./stream_scenario.py --list

The chosen scenario supplies ALL seven words of every frame: its four
vibration captures, its U-phase current capture and its two temperature
captures. Each capture wraps around on its own when it runs out, so the
stream never ends. Type 'q' + Enter or press Ctrl+C to stop.

See fpga_uart_link.py for the frame format and the aux-word arithmetic.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fpga_uart_link as link                                   # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream one scenario to top_system over UART until told to stop.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("--scenario", "-s", default="0Nm_Normal",
                        help="capture set name, e.g. 0Nm_BPFI_10")
    parser.add_argument("--list", action="store_true",
                        help="list the scenarios available under --data-root and exit")
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
    # Two layouts exist in the wild: split_dataset.py writes under
    # Scripts/process_dataset/, but the captures currently sit directly under
    # Scripts/. Try both before giving up, so --data-root stays optional.
    data_root = args.data_root
    if data_root is None and root is not None:
        for candidate in (root / "Scripts" / "dataset_q915",
                          root / "Scripts" / "process_dataset" / "dataset_q915"):
            if candidate.is_dir():
                data_root = candidate
                break
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

    log_path = link.setup_logging(args.log, args.verbose)
    log = link.log

    cfg = (link.LinkConfig.from_package(package) if package else link.LinkConfig())
    cfg = cfg.with_span(args.agg_span)

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
        try:
            stream = link.FrameStream(cfg, cache, args.scenario)
        except FileNotFoundError as exc:
            log.error("%s", exc)
            log.info("available: %s", ", ".join(link.list_scenarios(data_root)))
            return 2

        log.info("scenario    : %s  (shortest capture %d samples = %.1f min at full rate)",
                 args.scenario, stream.scenario.shortest,
                 stream.scenario.shortest * cfg.frame_seconds(args.baud) / 60.0)

        pacer = link.Pacer(args.frame_rate, 1.0 / cfg.frame_seconds(args.baud))
        commands = link.CommandReader()
        link.run_stream(cfg, stream, sink, pacer, batch_frames=args.batch,
                        status_every=args.status_every, commands=commands,
                        max_frames=args.max_frames, max_seconds=args.max_seconds)
        cache.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
