"""Groups keyboard keys from an XCUITest dump into rows: label[x+w] (pt). usage: rows.py dump..."""
import re, sys
pat = re.compile(r"(Key|Button), 0x[0-9a-f]+, \{\{([\d.]+), ([\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}(?:, identifier: '([^']*)')?(?:, label: '([^']*)')?")
for f in sys.argv[1:]:
    rows = {}
    for m in pat.finditer(open(f).read()):
        _, x, y, w, h, ident, label = m.groups()
        x, y, w, h = map(float, (x, y, w, h))
        if w == 0 or y < 590 or y > 800: continue
        name = label or ident or '?'
        if ident and ident not in ('emoji',): name = f"{ident}:{label}" if label and label != ident else ident
        rows.setdefault(y, []).append((x, name, w))
    print('==', f.split('/')[-1])
    for y in sorted(rows):
        r = sorted(set(rows[y]))
        print(f"  y{y:.0f}: " + '  '.join(f"{n.encode('unicode_escape').decode() if n.startswith(chr(0x200e)) else n}({w:.1f})" for x, n, w in r))
