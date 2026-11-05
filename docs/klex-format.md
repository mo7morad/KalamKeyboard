# .klex format (version 1)

One file per language. Written by `Tools/lexicon-builder/klex.py`, read by `KalamEngine/Suggestions/BaseLexicon.swift` (memory-mapped). All integers are little-endian. Records are packed with no alignment padding beyond what is listed.

## Header (96 bytes)

| Offset | Type | Field |
|---|---|---|
| 0 | 4 bytes | magic `KLEX` |
| 4 | u16 | version = 1 |
| 6 | 2 bytes | lang, ASCII `en` or `ar` |
| 8 | u32 | CRC32 (zlib) of bytes 96 to end of file |
| 12 | 7 x (u32 offset, u32 length, u32 count) | section table, in the order below |

`length` is in bytes and must equal `count x stride`. The writer lays the sections out contiguously after the header, in order.

## Sections

| # | Section | Stride | Record |
|---|---|---|---|
| 0 | nodes | 16 | u32 first child, u32 key id (0xFFFFFFFF = not terminal), u16 child count, u16 char (UTF-16 unit), u16 max-subtree q, 2 pad |
| 1 | keys | 8 | u32 first variant, u32 variant count |
| 2 | variants | 12 | u32 surface offset, u16 surface length (UTF-8 bytes, in the string pool), u16 q, u8 flags (1 = valid, 2 = preferred, 4 = candidate: a generated Egyptian form, offered and scored but never valid), 3 pad |
| 3 | bigram index | 8 | u32 first bigram, u32 bigram count; one record per word id, plus a last one for `<s>` (so count = variants + 1) |
| 4 | bigrams | 8 | u32 w2 word id, u16 q of P(w2 given w1), 2 pad; top 32 per w1, most probable first |
| 5 | casing | 12 | u32 word id, u32 display offset, u16 display length, 2 pad; sorted by word id |
| 6 | strings | 1 | UTF-8 string pool |

- **q** is a quantized log-probability: `q = round(-ln(p) x 1000)`, capped at 65535. Lower is more likely; `ln(p) = -q / 1000`.
- **Trie:** over normalized keys (SPEC 6.1) as UTF-16 units. Node 0 is the root (char 0). Nodes are in breadth-first order, so a node's children are contiguous, come after it, and are sorted by char. Max-subtree q is the best (lowest) variant q anywhere in the node's subtree, for best-first completion.
- **Keys** are numbered in sorted order of their UTF-16 units. A key's variants are contiguous, sorted by q then surface, so the first is the most probable.
- **Word id** = variant index. `<s>` has word id = variant count (bigram index only).

## Validation

- `BaseLexicon.init?` checks only the header (magic, version, lang) and that each section lies inside the file with `length = count x stride`, plus a non-empty node table and `bigram index count = variants + 1`. That keeps open time flat whatever the file size.
- Every record read is bounds-checked at read time: an out-of-range index, child range, variant range or string reads as empty. Child ranges must start after their parent, which rules out cycles. A corrupt body degrades to missing words and never crashes.
- The body CRC32 is checked by the builder's pytest, `swift test`, and `kalam-cli verify <file>`, not by the keyboard.
