import Foundation
import Testing
@testable import KalamEngine

struct NormalizationVector: Decodable, Sendable, CustomTestStringConvertible {
    let lang: Lang
    let input: String
    let expected: String
    var testDescription: String { input }
}

private let vectors: [NormalizationVector] = {
    struct File: Decodable { let cases: [NormalizationVector] }
    let url = repoRoot.appendingPathComponent("shared-test-vectors/normalization_vectors.json")
    return (try? JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases) ?? []
}()

@Test func vectorsAreLoaded() {
    #expect(vectors.count >= 30)
}

@Test(arguments: vectors)
func normalizesSharedVector(_ v: NormalizationVector) {
    #expect(normalize(v.input, lang: v.lang) == v.expected)
}
