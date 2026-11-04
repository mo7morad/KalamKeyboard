"""Tiles the bottom part (from top_pt) of several screenshots, 2x downscaled, into one PNG for review.
usage: sheet.py out.png top_pt cols files..."""
import sys, zlib, struct
from png import read
out, top, cols, files = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
tiles = []
for f in files:
    w, h, rows = read(f)
    tiles.append([r[::2] for r in rows[round(top * 3)::2]])
tw, th = len(tiles[0][0]), len(tiles[0]); n = len(tiles); rws = (n + cols - 1) // cols
W, H = cols * (tw + 8), rws * (th + 8)
img = [bytearray(b'\x80' * (W * 3)) for _ in range(H)]
for i, t in enumerate(tiles):
    ox, oy = (i % cols) * (tw + 8), (i // cols) * (th + 8)
    for y, r in enumerate(t):
        img[oy + y][ox * 3:(ox + tw) * 3] = bytes(c for p in r for c in p)
raw = b''.join(b'\x00' + bytes(r) for r in img)
chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
open(out, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
