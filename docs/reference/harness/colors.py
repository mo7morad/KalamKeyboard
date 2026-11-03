"""Samples named points (pt) and the label ink color of the Q/q key. usage: colors.py file scale"""
import sys
from png import read
f, s = sys.argv[1], float(sys.argv[2])
w, h, rows = read(f)
hexc = lambda c: '#%02x%02x%02x' % c
pts = {'screen above kb': (200, 500), 'bar bg': (60, 556), 'panel bg (row gap)': (200, 754), 'letter key': (35, 603),
       'shift': (48, 742), 'delete': (392, 742), '123': (12, 798), 'emoji': (60, 798), 'space': (200, 798), 'return': (390, 798), 'globe row bg': (200, 840)}
for k, (x, y) in pts.items():
    print(f"{k:20s} {hexc(rows[round(y*s)][round(x*s)])}")
lum = lambda c: sum(c)
box = [rows[y][x] for y in range(round(608*s), round(630*s)) for x in range(round(15*s), round(32*s))]
key = rows[round(603*s)][round(35*s)]
ink = max(box, key=lambda c: abs(lum(c) - lum(key)))
print(f"{'label ink (Q)':20s} {hexc(ink)}")
