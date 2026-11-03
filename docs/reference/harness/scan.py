"""Prints color runs along a horizontal (h) or vertical (v) line, in px and pt.
usage: scan.py file scale h|v coord_pt [from_pt to_pt] [tol]"""
import sys
from png import read

def runs(px, tol):
    out, start = [], 0
    for i in range(1, len(px) + 1):
        if i == len(px) or max(abs(a - b) for a, b in zip(px[i], px[start])) > tol:
            out.append((start, i - 1, px[start])); start = i
    return out

f, s, mode, c = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4])
w, h, rows = read(f)
lo = float(sys.argv[5]) if len(sys.argv) > 5 else 0
hi = float(sys.argv[6]) if len(sys.argv) > 6 else 1e9
tol = int(sys.argv[7]) if len(sys.argv) > 7 else 6
if mode == 'h':
    y = round(c * s); px = rows[y][max(0, round(lo * s)):min(w, round(hi * s))]; off = max(0, round(lo * s))
else:
    x = round(c * s); off = max(0, round(lo * s)); px = [rows[y][x] for y in range(off, min(h, round(hi * s)))]
for a, b, col in runs(px, tol):
    if b - a >= 2:
        print(f"{a+off:5d}-{b+off:5d}px  {(a+off)/s:7.2f}-{(b+off+1)/s:7.2f}pt  len {(b-a+1)/s:6.2f}pt  #{col[0]:02x}{col[1]:02x}{col[2]:02x}")
