#!/usr/bin/env python3
"""Run commands on the Jetson over its serial console and return clean output.

Reading a serial console is fiddly: there is no end-of-output signal, so a
fixed read window either truncates long output or wastes seconds on short
output. Each command here is followed by a unique end marker and the port is
read until that marker returns, so results are complete and arrive as soon as
they are ready.

    target-run.py 'uname -a' 'nvpmodel -q'
    target-run.py --timeout 60 'apt-get -y install foo'

Logs in automatically if it finds a login prompt. Credentials default to the
account l4t-preseed.sh creates; override with --user/--password or
TARGET_USER/TARGET_PASS.

SPDX-License-Identifier: Apache-2.0
"""

import argparse
import glob
import os
import sys
import time
import uuid

try:
    import serial
except ImportError:
    sys.exit("error: pyserial missing. install with: pip install pyserial")

# The CP2102N USB-UART on the Jetson's debug header. by-id keeps it stable
# across the renumbering any power cycle can cause.
PORT_GLOBS = ("/dev/serial/by-id/*CP2102N*", "/dev/ttyUSB*")


def find_port() -> str:
    for pattern in PORT_GLOBS:
        hits = sorted(glob.glob(pattern))
        if hits:
            return hits[0]
    sys.exit("error: no CP2102N console adapter found")


def read_until(sp, marker: str, timeout: float) -> str:
    end = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < end:
        chunk = sp.read(65536)
        if chunk:
            buf += chunk
            if marker.encode() in buf:
                break
    return buf.decode("utf-8", "replace").replace("\r", "")


def ensure_shell(sp, user: str, password: str) -> None:
    """Get to a shell prompt, logging in if the console is at a login."""
    for _ in range(5):
        sp.write(b"\r\n")
        sp.flush()
        out = read_until(sp, "\x00", 2.0)          # no marker: just drain
        tail = out.strip().split("\n")[-1] if out.strip() else ""
        if tail.endswith(("$", "#")):
            return
        if "login:" in tail:
            sp.write((user + "\r\n").encode())
            sp.flush()
            time.sleep(1.5)
            sp.write((password + "\r\n").encode())
            sp.flush()
            time.sleep(4)
        elif "assword" in tail:
            sp.write((password + "\r\n").encode())
            sp.flush()
            time.sleep(4)
    sys.exit("error: could not reach a shell prompt on the console")


def run(sp, cmd: str, timeout: float) -> str:
    marker = "__END_" + uuid.uuid4().hex[:8] + "__"
    sp.reset_input_buffer()
    sp.write((cmd + "; echo " + marker + "\r\n").encode())
    sp.flush()
    raw = read_until(sp, marker, timeout)

    # Drop the echoed command line, keep everything up to the marker. The
    # marker is echoed too, so stop at its first appearance.
    lines = raw.split("\n")
    out = []
    for line in lines[1:]:
        if marker in line:
            break
        out.append(line)
    return "\n".join(out).strip()


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("commands", nargs="+")
    ap.add_argument("-p", "--port")
    ap.add_argument("-t", "--timeout", type=float, default=20.0)
    ap.add_argument("--user", default=os.environ.get("TARGET_USER", "flippy"))
    ap.add_argument("--password", default=os.environ.get("TARGET_PASS", "flippy"))
    ap.add_argument("-q", "--quiet", action="store_true",
                    help="print only output, not the command echo")
    args = ap.parse_args()

    port = args.port or find_port()
    try:
        sp = serial.Serial(port, 115200, timeout=0.3)
    except serial.SerialException as exc:
        sys.exit(f"error: cannot open {port}: {exc}")

    try:
        ensure_shell(sp, args.user, args.password)
        for cmd in args.commands:
            if not args.quiet:
                print(f"$ {cmd}")
            print(run(sp, cmd, args.timeout))
    finally:
        sp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
