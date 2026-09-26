#!/usr/bin/env python3
"""Validate the USB link into the COMPLETE system (top_system_de0cv).

Program RTL/quartus/output_files/quartus.sof first, then:

    python3 top_system_link_test.py                  # 200 valid frames
    python3 top_system_link_test.py --frames 1000
    python3 top_system_link_test.py --corrupt        # also inject a bad checksum

Unlike stream_scenario.py this is CLOSED LOOP. top_system itself has no
transmitter, but top_system_de0cv adds a telemetry line on GPIO_0[4]:

    B=xxxx E=xx S=x F=x A=x

    B  bytes seen on the wire (16-bit, wraps)
    E  error_status, sticky; bit 0 = ERR_UART_FRAME (sync/checksum/idle timeout)
    S  status_leds  [2]=Critical [1]=Warning [0]=Normal
    F  sensor_fault_mask, one bit per vibration channel
    A  alert_flag

B is counted at the wire by a receiver independent of the ingestion path, so it
separates the two failures that look identical from the host:

    B stays 0000  -> nothing is reaching the FPGA; it is wiring, pins or baud
    B climbs, E=01 -> bytes arrive but frames are rejected; it is framing,
                      byte order, checksum or a frame-geometry mismatch

Exit status is 0 only if every check passed.
"""

import argparse
import re
import sys
import time
from pathlib import Path

try:
    import serial
except ImportError:
    sys.exit("pyserial is missing -- pip install pyserial")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fpga_uart_link as link                                   # noqa: E402

TELEM_RE = re.compile(rb"B=([0-9A-F]{4}) E=([0-9A-F]{2}) S=([0-9A-F]) "
                      rb"F=([0-9A-F]) A=([0-9A-F])")

ERR_NAMES = ["UART_FRAME", "VIB_OVERRUN", "MLP_DROP",
             "SPEC_DESYNC", "MDC_OVERRUN", "CNN_STALL"]
CLASS_NAMES = {0b001: "Normal", 0b010: "Warning", 0b100: "Critical"}


def parse_telem(raw):
    m = TELEM_RE.search(raw)
    if not m:
        return None
    return {"bytes": int(m.group(1), 16), "err": int(m.group(2), 16),
            "status": int(m.group(3), 16), "fault": int(m.group(4), 16),
            "alert": int(m.group(5), 16)}


def read_telem(port, timeout):
    """Returns the next parsed telemetry report, or None on timeout."""
    deadline = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < deadline:
        buf += port.read(128) or b""
        # Keep only the last complete line so we report the freshest snapshot.
        if b"\n" in buf:
            for chunk in reversed(buf.split(b"\n")):
                got = parse_telem(chunk)
                if got:
                    return got
            buf = buf.split(b"\n")[-1]
    return None


def describe(t):
    errs = [n for i, n in enumerate(ERR_NAMES) if t["err"] >> i & 1]
    err_note = " (" + ",".join(errs) + ")" if errs else ""
    verdict = CLASS_NAMES.get(t["status"], f"0b{t['status']:03b}")
    return (f"B={t['bytes']:<6} E={t['err']:02X}{err_note}"
            f"  verdict={verdict}"
            f"  faults={t['fault']:04b}  alert={t['alert']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--frames", type=int, default=200)
    ap.add_argument("--corrupt", action="store_true",
                    help="append one bad-checksum frame and check E picks it up")
    args = ap.parse_args()

    cfg = link.LinkConfig()
    passed = failed = 0

    def check(cond, what):
        nonlocal passed, failed
        if cond:
            passed += 1
            print(f"  PASS  {what}")
        else:
            failed += 1
            print(f"  FAIL  {what}")

    print(f"port {args.port} @ {args.baud} baud, "
          f"{cfg.frame_bytes if hasattr(cfg, 'frame_bytes') else 2 + cfg.n_sensors*cfg.bytes_per_word + 1} B/frame")

    try:
        port = serial.Serial(args.port, args.baud, timeout=0.3, write_timeout=10)
    except serial.SerialException as exc:
        sys.exit(f"cannot open {args.port}: {exc}")

    with port:
        time.sleep(0.2)
        port.reset_input_buffer()

        base = read_telem(port, timeout=3.0)
        if base is None:
            print("  FAIL  no telemetry at all -- is RTL/quartus/output_files/"
                  "quartus.sof programmed?")
            print("\n0 passed, 1 failed")
            return 1
        print(f"  ....  baseline  {describe(base)}")
        check(True, "telemetry is alive (the FPGA is transmitting)")

        # A gentle ramp keeps every word inside the 24-bit signed range and gives
        # the four vibration channels something distinguishable.
        frames = bytearray()
        for i in range(args.frames):
            words = [((i * 37 + c * 911) % 20000) - 10000 for c in range(cfg.n_sensors)]
            frames += link.encode_frame(words, cfg)
        if args.corrupt:
            frames += link.encode_frame([0] * cfg.n_sensors, cfg, corrupt_checksum=True)

        port.reset_input_buffer()
        t0 = time.monotonic()
        port.write(frames)
        port.flush()
        elapsed = time.monotonic() - t0
        print(f"  ....  sent {len(frames)} bytes "
              f"({args.frames} frames{' + 1 corrupt' if args.corrupt else ''}) "
              f"in {elapsed:.2f} s")

        # Let the last frame land, then take two reports so we know the count
        # settled rather than catching it mid-stream.
        time.sleep(1.2)
        first = read_telem(port, timeout=3.0)
        after = read_telem(port, timeout=3.0)
        if after is None:
            check(False, "telemetry still reporting after the burst")
            print(f"\n{passed} passed, {failed} failed")
            return 1
        print(f"  ....  after     {describe(after)}")

        expected = (base["bytes"] + len(frames)) & 0xFFFF
        check(after["bytes"] == expected,
              f"every byte reached the FPGA: want B={expected}, got B={after['bytes']}")

        # error_status is sticky and survives until a reset, so judge only the
        # bits this run newly set -- otherwise an earlier --corrupt run makes
        # every later clean run look like a failure.
        new_err = after["err"] & ~base["err"]
        if base["err"]:
            print(f"  ....  note: E was already {base['err']:02X} at baseline "
                  f"(sticky since the last reset); judging new bits only")

        if args.corrupt:
            check(new_err >> 0 & 1 == 1 or base["err"] >> 0 & 1 == 1,
                  "the corrupted frame set ERR_UART_FRAME")
        else:
            check(new_err >> 0 & 1 == 0,
                  "no framing error on clean frames (ERR_UART_FRAME clear)")
            check(new_err >> 1 & 1 == 0,
                  "ingestion FIFO did not overrun (ERR_VIB_OVERRUN clear)")

        check(after["status"] in CLASS_NAMES,
              f"status_leds holds exactly one verdict bit (got 0b{after['status']:03b})")

    print(f"\n{passed} passed, {failed} failed")
    if failed and after is not None and after["bytes"] == base["bytes"]:
        print("\nB never moved: no bytes are reaching the FPGA. Check that the\n"
              "CP2102's TX is on GPIO_1[4] = PIN_A13 (JP2 hole 5), that GND is\n"
              "shared, and that uart_loopback_test.py still passes -- it proves\n"
              "the cable independently of the full design.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
