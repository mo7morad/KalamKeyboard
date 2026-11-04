"""Ink bounding box inside a key rect (pt), using a luminance threshold halfway between cap and label.
usage: glyph.py file scale x0 y0 x1 y1"""
import sys
from png import read
f, s = sys.argv[1], float(sys.argv[2]); x0, y0, x1, y1 = (round(float(v) * s) for v in sys.argv[3:7])
w, h, rows = read(f)
lum = lambda c: sum(c) / 3
cap = lum(rows[y0 + 6][x0 + 6])
ink = [(x, y) for y in range(y0, y1) for x in range(x0, x1) if abs(lum(rows[y][x]) - cap) > 100]
xs, ys = [p[0] for p in ink], [p[1] for p in ink]
print(f"ink x {min(xs)/s:.2f}-{(max(xs)+1)/s:.2f}pt  y {min(ys)/s:.2f}-{(max(ys)+1)/s:.2f}pt  h {(max(ys)-min(ys)+1)/s:.2f}pt  w {(max(xs)-min(xs)+1)/s:.2f}pt")
