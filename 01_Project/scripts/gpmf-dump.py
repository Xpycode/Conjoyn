#!/usr/bin/env python3
"""Minimal GPMF (GoPro Metadata Format) KLV walker.

Reads a raw gpmd elementary stream (as extracted with `ffmpeg -map 0:<gpmd> -c copy -f data`)
and reports, per top-level DEVC payload: byte offset, STMP (microseconds since recording start),
GPSU (UTC wall clock from the GPS receiver), TSMP counts, and whether the KLV walk stays in sync.

Purpose: prove/disprove that a *concatenated* gpmd stream is semantically readable end-to-end by
a sequential GPMF consumer, not merely byte-identical.
"""
import struct
import sys

TYPE_SIZES = {
    b'b': 1, b'B': 1, b'c': 1, b'd': 8, b'f': 4, b'F': 4, b'G': 16, b'j': 8,
    b'J': 8, b'l': 4, b'L': 4, b'q': 4, b'Q': 8, b's': 2, b'S': 2, b'U': 1,
}


def walk(buf, start, end, depth, out, ctx):
    """Walk KLV entries in buf[start:end]. Returns True if the walk stayed aligned."""
    pos = start
    while pos + 8 <= end:
        key = buf[pos:pos + 4]
        typ = buf[pos + 4:pos + 5]
        ssize = buf[pos + 5]
        repeat = struct.unpack('>H', buf[pos + 6:pos + 8])[0]
        length = ssize * repeat
        padded = (length + 3) & ~3
        body = pos + 8
        if body + padded > end:
            out.append(('DESYNC', pos, f'{key!r} claims {length}B, only {end - body}B left'))
            return False
        if not all(32 <= c <= 126 for c in key):
            out.append(('DESYNC', pos, f'non-ASCII key {key!r}'))
            return False
        if typ == b'\x00':  # nested container
            if not walk(buf, body, body + length, depth + 1, out, ctx):
                return False
        else:
            payload = buf[body:body + length]
            if key == b'STMP' and typ == b'J' and length >= 8:
                ctx.setdefault('stmp', []).append(struct.unpack('>Q', payload[:8])[0])
            elif key == b'GPSU' and length >= 16:
                ctx.setdefault('gpsu', []).append(payload[:16].decode('ascii', 'replace'))
            elif key == b'TSMP' and length >= 4:
                ctx.setdefault('tsmp', []).append(struct.unpack('>L', payload[:4])[0])
            elif key == b'DVNM':
                ctx.setdefault('dvnm', set()).add(payload.rstrip(b'\x00').decode('ascii', 'replace'))
        pos = body + padded
    return True


def payloads(buf):
    """Yield (offset, length) for each top-level DEVC payload."""
    pos = 0
    n = len(buf)
    while pos + 8 <= n:
        key = buf[pos:pos + 4]
        ssize = buf[pos + 5]
        repeat = struct.unpack('>H', buf[pos + 6:pos + 8])[0]
        length = ssize * repeat
        padded = (length + 3) & ~3
        if key != b'DEVC':
            print(f'!! top-level key at {pos} is {key!r}, expected DEVC — stream desynced')
            return
        yield pos, 8 + padded
        pos += 8 + padded


def main(path):
    with open(path, 'rb') as fh:
        buf = fh.read()
    print(f'{path}: {len(buf)} bytes')
    n_ok = 0
    prev_stmp = None
    prev_gpsu = None
    rows = []
    for idx, (off, size) in enumerate(payloads(buf)):
        out, ctx = [], {}
        ok = walk(buf, off, off + size, 0, out, ctx)
        n_ok += ok
        stmp = ctx.get('stmp', [None])[0]
        gpsu = ctx.get('gpsu', [None])[0]
        d_stmp = (stmp - prev_stmp) / 1e6 if (stmp is not None and prev_stmp is not None) else None
        rows.append((idx, off, size, ok, stmp, d_stmp, gpsu, out))
        prev_stmp, prev_gpsu = stmp if stmp is not None else prev_stmp, gpsu or prev_gpsu
    print(f'payloads: {len(rows)}  KLV-clean: {n_ok}')
    print(f'{"#":>4} {"offset":>10} {"size":>7} {"ok":>3} {"STMP(us)":>14} {"dSTMP(s)":>9}  GPSU')
    for idx, off, size, ok, stmp, d, gpsu, out in rows:
        ds = f'{d:9.4f}' if d is not None else '        -'
        print(f'{idx:>4} {off:>10} {size:>7} {"Y" if ok else "N":>3} {str(stmp):>14} {ds}  {gpsu}')
        for kind, p, msg in out:
            print(f'        {kind} @{p}: {msg}')


if __name__ == '__main__':
    for p in sys.argv[1:]:
        main(p)
        print()
