"""Minimal stdlib PNG reader: 8/16-bit RGB/RGBA, non-interlaced. Returns (w, h, rows) with rows[y][x] = (r, g, b) 8-bit."""
import struct, zlib

def read(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat = 8, []
    while pos < len(data):
        n, t = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', body)
        elif t == b'IDAT':
            idat.append(body)
        pos += 12 + n
    assert inter == 0 and ctype in (2, 6) and depth in (8, 16)
    ch = 3 if ctype == 2 else 4
    bpp = ch * depth // 8
    stride = w * bpp
    raw = zlib.decompress(b''.join(idat))
    prev = bytearray(stride)
    rows = []
    for y in range(h):
        f = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 1:
            for i in range(bpp, stride): cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif f == 2:
            cur = bytearray((a + b) & 255 for a, b in zip(cur, prev))
        elif f == 3:
            for i in range(stride): cur[i] = (cur[i] + ((cur[i - bpp] if i >= bpp else 0) + prev[i]) // 2) & 255
        elif f == 4:
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0; b = prev[i]; c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = cur
        step = depth // 8
        rows.append([tuple(cur[x * bpp + k * step] for k in range(3)) for x in range(w)])
    return w, h, rows

if __name__ == '__main__':
    import sys
    w, h, rows = read(sys.argv[1]); print(w, h, rows[h // 2][w // 2])
