"""Estimates a key's corner radius: per pixel row from the cap's top edge, the coverage-weighted left inset.
usage: corner.py file scale left_pt top_pt  (a point just outside the cap's top-left corner)"""
import sys, math
from png import read
f, s, L, T = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
w, h, rows = read(f)
x0, y0 = round(L * s), round(T * s)
bg = rows[y0][x0]; cap = rows[y0 + 40][x0 + 40]
lum = lambda c: sum(c) / 3
den = lum(cap) - lum(bg)
cov = lambda c: min(1, max(0, (lum(c) - lum(bg)) / den))
# find top edge row: first row where pixel at x0+40 is mostly cap
top = next(y for y in range(y0, y0 + 30) if cov(rows[y][x0 + 40]) > 0.5)
left = next(x for x in range(x0, x0 + 30) if cov(rows[y0 + 40][x]) > 0.5)
fits = []
for dy in range(0, 30):
    y = top + dy
    covered = sum(cov(rows[y][x]) for x in range(left - 3, left + 40))
    inset = 43 - 3 - covered  # px of missing cap at this row (approx)
    print(dy, round(inset, 2))
    if inset < 0.3: break
    # circle: inset = r - sqrt(r^2 - (r - (dy+0.5))^2)
    for r10 in range(10, 600):
        r = r10 / 10
        yy = r - (dy + 0.5)
        if yy < 0: continue
        if abs(r - math.sqrt(max(0, r * r - yy * yy)) - inset) < 0.15: fits.append(r); break
print('bg', bg, 'cap', cap, 'top', top, 'left', left, 'r_px median', sorted(fits)[len(fits)//2] if fits else None, 'r_pt', (sorted(fits)[len(fits)//2] / s) if fits else None)
