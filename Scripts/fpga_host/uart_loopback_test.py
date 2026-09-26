#!/usr/bin/env python3
"""Validate the USB-serial link to the FPGA against RTL/uart/rtl/uart_loopback_top.sv.

Program RTL/quartus_uart_loopback/output_files/uart_loopback.sof first, then:

    python3 uart_loopback_test.py                 # every test, default port
    python3 uart_loopback_test.py --port /dev/ttyUSB0 --baud 115200
    python3 uart_loopback_test.py --bytes 65536   # longer throughput run
    python3 uart_loopback_test.py --banner        # wait for a KEY[1] press

Exit status is 0 only if every test passed, so this is usable from a script.

WHY THE COMPLEMENT TEST MATTERS
    A jumper across the adapter's own TX and RX pins echoes bytes perfectly,
    so a byte-for-byte pass does not prove the FPGA is in the path. With
    SW[0] high the design returns ~byte instead, which a wire cannot do. The
    run prompts for the switch rather than assuming it, and reports the two
    results separately.
"""

import argparse
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is missing -- pip install pyserial")


# The design's reply to a KEY[1] press; see the banner injector in the RTL.
BANNER = b"UART OK\r\n"

# Bytes worth trying one at a time: all-zeros and all-ones stress the framing,
# the alternating patterns stress bit ordering, and 0x00 is the one value that
# looks like a start bit held long.
EDGE_VECTORS = bytes([0x00, 0xFF, 0x55, 0xAA, 0x01, 0x80, 0x5A, 0xA5, 0x7F, 0xFE])


class Results:
    def __init__(self):
        self.passed = 0
        self.failed = 0

    def ok(self, name, detail=""):
        self.passed += 1
        print(f"  PASS  {name}{'  -- ' + detail if detail else ''}")

    def fail(self, name, detail=""):
        self.failed += 1
        print(f"  FAIL  {name}{'  -- ' + detail if detail else ''}")


def drain(port):
    """Discard anything already in flight so a test starts from a known state."""
    port.reset_input_buffer()
    old = port.timeout
    port.timeout = 0.05
    while port.read(4096):
        pass
    port.timeout = old


def read_exactly(port, n, timeout):
    """Read n bytes or return what arrived before the deadline."""
    deadline = time.monotonic() + timeout
    buf = bytearray()
    while len(buf) < n and time.monotonic() < deadline:
        chunk = port.read(n - len(buf))
        if chunk:
            buf += chunk
    return bytes(buf)


def first_difference(sent, got):
    for i, (a, b) in enumerate(zip(sent, got)):
        if a != b:
            return f"first difference at byte {i}: sent {a:#04x}, got {b:#04x}"
    if len(got) < len(sent):
        return f"stopped after {len(got)} of {len(sent)} bytes"
    return "lengths differ"


def test_liveness(port, res):
    """One byte, and a verdict on whether anything is listening at all."""
    drain(port)
    port.write(b"\x5A")
    port.flush()
    got = read_exactly(port, 1, timeout=1.0)
    if got == b"\x5A":
        res.ok("liveness", "0x5a echoed")
        return True
    if not got:
        res.fail("liveness", "nothing came back -- see the checklist below")
    else:
        res.fail("liveness", f"expected 0x5a, got {got.hex()} (baud mismatch?)")
    return False


def test_edge_vectors(port, res, invert=False):
    drain(port)
    want = bytes(b ^ 0xFF for b in EDGE_VECTORS) if invert else EDGE_VECTORS
    label = "complement of edge vectors" if invert else "edge vectors"
    bad = []
    for sent, expect in zip(EDGE_VECTORS, want):
        port.write(bytes([sent]))
        port.flush()
        got = read_exactly(port, 1, timeout=0.5)
        if got != bytes([expect]):
            bad.append(f"{sent:#04x}->{got.hex() or 'nothing'} (want {expect:#04x})")
    if bad:
        res.fail(label, "; ".join(bad))
    else:
        res.ok(label, f"{len(EDGE_VECTORS)}/{len(EDGE_VECTORS)} bytes")


def test_all_values(port, res):
    """Every 8-bit value, sent as one gapless block."""
    drain(port)
    payload = bytes(range(256))
    port.write(payload)
    port.flush()
    got = read_exactly(port, len(payload), timeout=5.0 + len(payload) * 10 / 115200)
    if got == payload:
        res.ok("all 256 byte values", "in order, none dropped")
    else:
        res.fail("all 256 byte values", first_difference(payload, got))


def test_throughput(port, res, count, baud):
    """The test that actually catches a marginal link: sustained, gapless traffic.

    A pattern with no repeats within a byte period means a dropped or doubled
    byte shows up as a mismatch rather than sliding by unnoticed.
    """
    drain(port)
    payload = bytes((i * 7 + 3) & 0xFF for i in range(count))

    # 10 bits per byte each way, plus a floor for the round trip and for the
    # adapter's own latency timer.
    budget = 2.0 + (count * 10) / baud * 2.5

    start = time.monotonic()
    port.write(payload)
    port.flush()
    got = read_exactly(port, count, timeout=budget)
    elapsed = time.monotonic() - start

    if got == payload:
        rate = count / elapsed if elapsed else float("inf")
        res.ok(
            f"throughput, {count} bytes",
            f"{elapsed:.2f} s, {rate:,.0f} B/s round trip "
            f"({rate * 10 * 2 / baud:.0%} of the line's capacity)",
        )
    else:
        res.fail(f"throughput, {count} bytes",
                 f"{len(got)} bytes back in {elapsed:.2f} s -- "
                 + first_difference(payload, got))


def test_banner(port, res, timeout):
    drain(port)
    print(f"  ....  press KEY[1] on the board within {timeout:.0f} s")
    got = read_exactly(port, len(BANNER), timeout=timeout)
    if got == BANNER:
        res.ok("KEY[1] banner", f"received {BANNER!r}")
    elif not got:
        res.fail("KEY[1] banner", "nothing received (button not pressed, or TX is dead)")
    else:
        res.fail("KEY[1] banner", f"expected {BANNER!r}, got {got!r}")


CHECKLIST = """
Nothing echoed. Work down this list -- it is ordered by how often each one is
the actual cause:

  1. Crossover. The adapter's TX goes to GPIO_1[4] (PIN_A13, JP2 pin 5) and
     its RX to GPIO_0[4] (PIN_D17, JP1 pin 5). TX-to-TX is the usual mistake,
     and here the two pins are on different headers.
  2. Ground. The adapter's GND must reach JP1 pin 12. Without a common ground
     the line level is undefined and the receiver sees noise or nothing.
  3. The .sof. RTL/quartus_uart_loopback/output_files/uart_loopback.sof has to
     be the design on the board -- not RTL/quartus, whose top_system build has
     no pin constraints at all and places uart_rx wherever the fitter likes.
  4. Baud. The design is built for 115200 8N1; --baud must match.
  5. Port. Check that /dev/ttyUSB0 is the adapter and nothing else holds it
     open (fuser -v /dev/ttyUSB0), and that you are in the dialout group.
  6. Levels. The DE0-CV GPIO banks are 3.3-V LVTTL and are not 5 V tolerant.
     A 5 V adapter will not work and may damage the pin.

To split the link in half, run with --banner and press KEY[1]: if the banner
arrives, the FPGA's transmit direction and the adapter's receive side are both
fine and the fault is in the other direction.
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--bytes", type=int, default=4096,
                    help="payload size for the throughput test (default 4096)")
    ap.add_argument("--invert", action="store_true",
                    help="also run the complement test, assuming SW[0] is already up")
    ap.add_argument("--banner", action="store_true",
                    help="wait for a KEY[1] press and check the banner")
    ap.add_argument("--banner-timeout", type=float, default=15.0)
    args = ap.parse_args()

    res = Results()
    print(f"port {args.port} @ {args.baud} baud, 8N1")

    try:
        port = serial.Serial(args.port, args.baud, bytesize=8,
                             parity=serial.PARITY_NONE, stopbits=1,
                             timeout=0.2, write_timeout=5.0)
    except serial.SerialException as exc:
        sys.exit(f"cannot open {args.port}: {exc}")

    with port:
        time.sleep(0.1)                      # let the adapter settle after open

        if test_liveness(port, res):
            test_edge_vectors(port, res)
            test_all_values(port, res)
            test_throughput(port, res, args.bytes, args.baud)

            if args.invert:
                test_edge_vectors(port, res, invert=True)
            else:
                print("  ....  skipping the complement test; raise SW[0] and "
                      "re-run with --invert to prove the FPGA is in the path")

        if args.banner:
            test_banner(port, res, args.banner_timeout)

    print(f"\n{res.passed} passed, {res.failed} failed")
    if res.failed and res.passed == 0:
        print(CHECKLIST)
    return 1 if res.failed else 0


if __name__ == "__main__":
    sys.exit(main())
