import Foundation

/// A memory-mapped .klex base lexicon (layout: docs/klex-format.md).
/// The init checks the header and section bounds only, so it stays fast whatever the file size.
/// Every record read is bounds-checked: a corrupt body degrades to missing words, never a crash.
public final class BaseLexicon {
    public let lang: Lang
    private let data: Data
    private let nodeTable, keyTable, variantTable, bigramIndexTable, bigramTable, casingTable, stringPool: Section

    private struct Section {
        let offset: Int
        let count: Int
        let stride: Int
    }

    static let headerSize = 96
    private static let strides = [16, 8, 12, 8, 8, 12, 1]
    private static let noKey = 0xFFFF_FFFF

    public convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        self.init(data: data)
    }

    public init?(data: Data) {
        guard data.count >= Self.headerSize,
              data.le(0, as: UInt32.self) == 0x5845_4C4B,  // "KLEX"
              data.le(4, as: UInt16.self) == 1,
              let lang = Lang(rawValue: String(decoding: [data.le(6, as: UInt8.self), data.le(7, as: UInt8.self)], as: UTF8.self))
        else { return nil }
        var sections: [Section] = []
        for (i, stride) in Self.strides.enumerated() {
            let entry = 12 + i * 12
            let offset = Int(data.le(entry, as: UInt32.self))
            let length = Int(data.le(entry + 4, as: UInt32.self))
            let count = Int(data.le(entry + 8, as: UInt32.self))
            guard offset >= Self.headerSize, length == count * stride, offset + length <= data.count else { return nil }
            sections.append(Section(offset: offset, count: count, stride: stride))
        }
        guard sections[0].count > 0, sections[3].count == sections[2].count + 1 else { return nil }
        self.lang = lang
        self.data = data
        (nodeTable, keyTable, variantTable, bigramIndexTable, bigramTable, casingTable, stringPool) =
            (sections[0], sections[1], sections[2], sections[3], sections[4], sections[5], sections[6])
    }

    /// Checks the body CRC32 in the header. Reads the whole file: for the CLI and tests, not the keyboard.
    public func verifyChecksum() -> Bool {
        let body = data.withUnsafeBytes { crc32(UnsafeRawBufferPointer(rebasing: $0[Self.headerSize...])) }
        return body == data.le(8, as: UInt32.self)
    }

    public var counts: (nodes: Int, keys: Int, variants: Int, bigrams: Int) {
        (nodeTable.count, keyTable.count, variantTable.count, bigramTable.count)
    }

    // MARK: Trie

    static let root = 0

    /// Children are stored after their parent (breadth-first), which also rules out cycles in a corrupt file.
    func children(_ node: Int) -> Range<Int> {
        let first = Int(field(nodeTable, node, 0, UInt32.self))
        let end = first + Int(field(nodeTable, node, 8, UInt16.self))
        return first > node && end <= nodeTable.count ? first..<end : 0..<0
    }

    func char(_ node: Int) -> UInt16 { field(nodeTable, node, 10, UInt16.self) }

    func key(_ node: Int) -> Int? {
        let key = Int(field(nodeTable, node, 4, UInt32.self))
        return key != Self.noKey && key < keyTable.count ? key : nil
    }

    /// Best unigram log-prob of any word in the node's subtree.
    func bestLogProb(_ node: Int) -> Double { dequantize(field(nodeTable, node, 12, UInt16.self)) }

    func child(_ node: Int, _ unit: UInt16) -> Int? {
        var range = children(node)
        while !range.isEmpty {
            let mid = range.lowerBound + range.count / 2
            let c = char(mid)
            if c == unit { return mid }
            range = c < unit ? mid + 1..<range.upperBound : range.lowerBound..<mid
        }
        return nil
    }

    /// Key id of a normalized lookup key.
    public func key(for normalized: String) -> Int? {
        var node = Self.root
        for unit in normalized.utf16 {
            guard let next = child(node, unit) else { return nil }
            node = next
        }
        return key(node)
    }

    // MARK: Words

    /// Word ids of a key's variants, most probable first.
    public func variants(ofKey key: Int) -> Range<Int> {
        let first = Int(field(keyTable, key, 0, UInt32.self))
        let end = first + Int(field(keyTable, key, 4, UInt32.self))
        return end <= variantTable.count ? first..<end : 0..<0
    }

    public func surface(_ word: Int) -> String {
        string(at: Int(field(variantTable, word, 0, UInt32.self)), length: Int(field(variantTable, word, 4, UInt16.self)))
    }

    public func logProb(_ word: Int) -> Double { dequantize(field(variantTable, word, 6, UInt16.self)) }
    public func isValid(_ word: Int) -> Bool { field(variantTable, word, 8, UInt8.self) & 1 != 0 }
    public func isPreferred(_ word: Int) -> Bool { field(variantTable, word, 8, UInt8.self) & 2 != 0 }
    /// A word the engine offers and scores: valid, or a generated Egyptian form (4), which never blocks autocorrect.
    public func isCandidate(_ word: Int) -> Bool { field(variantTable, word, 8, UInt8.self) & 5 != 0 }

    /// The id bigrams use for <s>.
    public var sentenceStartID: Int { variantTable.count }

    /// Word id of an ident (SPEC 6.3), or sentenceStartID for <s>.
    public func wordID(ident: String) -> Int? {
        if ident == sentenceStart { return sentenceStartID }
        guard let key = key(for: normalize(ident, lang: lang)) else { return nil }
        return variants(ofKey: key).first { surface($0) == ident }
    }

    /// log P(w2 | w1) when w2 is among w1's top bigrams.
    public func bigramLogProb(_ w1: Int, _ w2: Int) -> Double? {
        for i in bigramRange(w1) where Int(field(bigramTable, i, 0, UInt32.self)) == w2 {
            return dequantize(field(bigramTable, i, 4, UInt16.self))
        }
        return nil
    }

    /// Word ids of w1's top bigram continuations, most probable first.
    public func bigrams(after w1: Int) -> [Int] {
        bigramRange(w1).map { Int(field(bigramTable, $0, 0, UInt32.self)) }
    }

    private func bigramRange(_ w1: Int) -> Range<Int> {
        let first = Int(field(bigramIndexTable, w1, 0, UInt32.self))
        let end = min(first + Int(field(bigramIndexTable, w1, 4, UInt32.self)), bigramTable.count)
        return first..<max(first, end)
    }

    /// Corpus display casing (e.g. "i" -> "I"), when it differs from the surface.
    public func casing(_ word: Int) -> String? {
        var range = 0..<casingTable.count
        while !range.isEmpty {
            let mid = range.lowerBound + range.count / 2
            let id = Int(field(casingTable, mid, 0, UInt32.self))
            if id == word {
                return string(at: Int(field(casingTable, mid, 4, UInt32.self)), length: Int(field(casingTable, mid, 8, UInt16.self)))
            }
            range = id < word ? mid + 1..<range.upperBound : range.lowerBound..<mid
        }
        return nil
    }

    // MARK: Raw reads

    private func field<T: FixedWidthInteger>(_ s: Section, _ index: Int, _ offset: Int, _ type: T.Type) -> T {
        guard index >= 0, index < s.count else { return 0 }
        return data.le(s.offset + index * s.stride + offset, as: type)
    }

    private func string(at offset: Int, length: Int) -> String {
        guard offset + length <= stringPool.count else { return "" }
        let start = stringPool.offset + offset
        return data.withUnsafeBytes { String(decoding: UnsafeRawBufferPointer(rebasing: $0[start..<start + length]), as: UTF8.self) }
    }

    private func dequantize(_ q: UInt16) -> Double { -Double(q) / 1000 }
}

private extension Data {
    /// Little-endian read; 0 when out of bounds.
    func le<T: FixedWidthInteger>(_ offset: Int, as: T.Type) -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else { return 0 }
        return withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
    }
}

// ponytail: bitwise CRC32, ~0.5 s on a 40 MB file; add a lookup table if verify gets slow.
private func crc32(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
    }
    return ~crc
}
