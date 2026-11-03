import Foundation
import KalamEngine

/// kalam-cli verify <file.klex>: header, section bounds and body CRC32.
func verify(_ args: [String]) -> Int32 {
    guard let path = args.first else {
        print("usage: kalam-cli verify <file.klex>")
        return 2
    }
    guard let lexicon = BaseLexicon(url: URL(fileURLWithPath: path)) else {
        print("\(path): FAIL, unreadable or bad header / section bounds")
        return 1
    }
    guard lexicon.verifyChecksum() else {
        print("\(path): FAIL, body CRC32 mismatch")
        return 1
    }
    let c = lexicon.counts
    print("\(path): OK lang=\(lexicon.lang.rawValue) nodes=\(c.nodes) keys=\(c.keys) variants=\(c.variants) bigrams=\(c.bigrams)")
    return 0
}
