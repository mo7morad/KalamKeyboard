"""Writer for the .klex base lexicon format. Layout: docs/klex-format.md."""
import math
import struct
import zlib

from normalize import normalize

VERSION = 1
HEADER = struct.Struct("<4sH2sI")  # magic, version, lang, body crc32
SECTION = struct.Struct("<III")  # offset, length, count
NODE = struct.Struct("<IIHHHxx")  # first child, key id, child count, char, max subtree q
KEY = struct.Struct("<II")  # first variant, variant count
VARIANT = struct.Struct("<IHHB3x")  # string offset, string length, q, flags
BIGRAM_INDEX = struct.Struct("<II")  # first bigram, bigram count
BIGRAM = struct.Struct("<IHxx")  # w2 word id, q
CASING = struct.Struct("<IIHxx")  # word id, string offset, string length
HEADER_SIZE = HEADER.size + 7 * SECTION.size
NO_KEY = 0xFFFFFFFF
VALID, PREFERRED = 1, 2
TOP_BIGRAMS = 32
SENTENCE_START = "<s>"


def quantize(prob: float) -> int:
    """-ln(prob) in thousandths of a nat, so lower is more likely."""
    return min(0xFFFF, round(-math.log(prob) * 1000))


def utf16(text: str) -> tuple:
    raw = text.encode("utf-16-le")
    return struct.unpack(f"<{len(raw) // 2}H", raw)


def write_klex(lang: str, words: dict, bigrams: dict, casing: dict) -> bytes:
    """words: surface -> (frequency, flags). bigrams: (w1, w2) -> P(w2 | w1), w1 may be <s>.
    casing: surface -> display form. Output is deterministic for the same input."""
    by_key = {}
    for surface, (freq, flags) in words.items():
        by_key.setdefault(utf16(normalize(surface, lang)), []).append((quantize(freq), surface, flags))
    keys = sorted(by_key)

    strings = bytearray()

    def add_string(text):
        raw = text.encode("utf-8")
        strings.extend(raw)
        return len(strings) - len(raw), len(raw)

    variants, key_records, word_id = [], [], {}
    for key in keys:
        key_records.append(KEY.pack(len(variants), len(by_key[key])))
        for q, surface, flags in sorted(by_key[key]):
            word_id[surface] = len(variants)
            variants.append(VARIANT.pack(*add_string(surface), q, flags))

    nodes = _trie_nodes(keys, [min(q for q, _, _ in by_key[k]) for k in keys])

    index, bigram_records = _bigram_records(bigrams, word_id)

    casing_records = [
        CASING.pack(word_id[s], *add_string(casing[s])) for s in sorted(casing, key=word_id.get) if s in word_id
    ]

    sections = [nodes, key_records, variants, index, bigram_records, casing_records]
    sections = [(b"".join(records), len(records)) for records in sections] + [(bytes(strings), len(strings))]
    table, body, offset = [], bytearray(), HEADER_SIZE
    for blob, count in sections:
        table.append(SECTION.pack(offset, len(blob), count))
        body.extend(blob)
        offset += len(blob)
    header = HEADER.pack(b"KLEX", VERSION, lang.encode("ascii"), zlib.crc32(body))
    return header + b"".join(table) + bytes(body)


def _bigram_records(bigrams: dict, word_id: dict) -> tuple:
    """One index record per word id plus <s>, each pointing at its top bigrams, most probable first."""
    by_w1 = {}
    for (w1, w2), p in bigrams.items():
        if w2 in word_id:
            by_w1.setdefault(w1, []).append((quantize(p), word_id[w2]))
    index, records = [], []
    for w1 in sorted(word_id, key=word_id.get) + [SENTENCE_START]:
        followers = sorted(by_w1.get(w1, []))[:TOP_BIGRAMS]
        index.append(BIGRAM_INDEX.pack(len(records), len(followers)))
        records.extend(BIGRAM.pack(wid, q) for q, wid in followers)
    return index, records


def _trie_nodes(keys: list, best_q: list) -> list:
    """Breadth-first trie so every node's children are contiguous and sorted by UTF-16 unit."""
    root = {"children": {}, "key": NO_KEY, "char": 0}
    for key_id, units in enumerate(keys):
        node = root
        for unit in units:
            node = node["children"].setdefault(unit, {"children": {}, "key": NO_KEY, "char": unit})
        node["key"] = key_id

    def max_subtree(node):
        own = best_q[node["key"]] if node["key"] != NO_KEY else 0xFFFF
        node["best"] = min([own] + [max_subtree(c) for c in node["children"].values()])
        return node["best"]

    max_subtree(root)
    order, next_free, records = [root], 1, []
    for node in order:  # order grows while we walk it: breadth-first
        children = [node["children"][u] for u in sorted(node["children"])]
        records.append(NODE.pack(next_free if children else 0, node["key"], len(children), node["char"], node["best"]))
        order.extend(children)
        next_free += len(children)
    return records
