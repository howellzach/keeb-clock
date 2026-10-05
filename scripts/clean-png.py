#!/usr/bin/env python3
"""Remove non-rendering metadata from project PNGs without recompressing pixels."""
import struct
import sys
from pathlib import Path

# Keep image data and rendering metadata.
KEEP = {b'IHDR', b'PLTE', b'IDAT', b'IEND', b'tRNS', b'gAMA', b'cHRM',
        b'sRGB', b'iCCP', b'sBIT', b'bKGD', b'pHYs'}


def clean(path):
    data = path.read_bytes()
    signature = b'\x89PNG\r\n\x1a\n'
    if not data.startswith(signature):
        raise ValueError(f'Not a PNG: {path}')
    chunks = [signature]
    offset = 8
    complete = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError(f'Truncated PNG: {path}')
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + length + 12
        if end > len(data):
            raise ValueError(f'Truncated PNG chunk: {path}')
        if kind in {b'acTL', b'fcTL', b'fdAT'}:
            raise ValueError(f'Animated PNG is not supported: {path}')
        if kind in KEEP:
            chunks.append(data[offset:end])
        elif not kind[0] & 32:
            raise ValueError(f'Unknown critical PNG chunk: {path}')
        offset = end
        if kind == b'IEND':
            complete = True
            break
    if not complete:
        raise ValueError(f'Missing PNG end: {path}')
    cleaned = b''.join(chunks)
    if cleaned != data:
        path.write_bytes(cleaned)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit('Usage: clean-png.py image.png [...]')
    for filename in sys.argv[1:]:
        clean(Path(filename))
