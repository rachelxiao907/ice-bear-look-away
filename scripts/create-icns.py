#!/usr/bin/env python3
"""Pack PNG icon sizes into a macOS ICNS file."""

import struct
import sys
from pathlib import Path


def chunk(kind: bytes, data: bytes) -> bytes:
    return kind + struct.pack(">I", len(data) + 8) + data


source = Path(sys.argv[1])
destination = Path(sys.argv[2])
sizes = {
    16: b"icp4",
    32: b"icp5",
    64: b"icp6",
    128: b"ic07",
    256: b"ic08",
    512: b"ic09",
    1024: b"ic10",
}
payload = b"".join(
    chunk(kind, (source / f"icon-{size}.png").read_bytes())
    for size, kind in sizes.items()
)
destination.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
