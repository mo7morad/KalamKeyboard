import CoreGraphics
import Testing
@testable import KalamEngine

/// Apple's iPhone 17 cap positions from docs/reference/apple/README.md, within 1 pt.
@Test func englishCapsMatchApple() throws {
    let geometry = KeyGeometry(layout: try #require(Layout.bundled("en-letters")), width: 402)
    func cap(_ id: String) throws -> CGRect { try #require(geometry.frames.first { $0.key.id == id }).cap }
    let expected: [(String, CGFloat, CGFloat)] = [
        ("q", 7.0, 40.0), ("p", 362.3, 395.3), ("a", 26.7, 59.5), ("shift", 7.0, 51.7),
        ("z", 66.0, 99.0), ("backspace", 350.3, 395.3), ("numbers", 7.0, 49.7),
        ("lang", 56.3, 99.0), ("space", 105.7, 296.3), ("return", 303.0, 395.3),
    ]
    for (id, minX, maxX) in expected {
        #expect(abs(try cap(id).minX - minX) < 1, "\(id) minX")
        #expect(abs(try cap(id).maxX - maxX) < 1, "\(id) maxX")
    }
    #expect(abs(try cap("q").height - 42.3) < 1)
    #expect(try cap("a").minY - cap("q").minY == KeyGeometry.rowPitch)
}

@Test func arabicPitchIsElevenKeysWide() throws {
    let geometry = KeyGeometry(layout: try #require(Layout.bundled("ar-letters")), width: 402)
    #expect(abs(geometry.unit - 35.9) < 0.05)
    let backspace = try #require(geometry.frames.first { $0.key.id == "backspace" })
    #expect(abs(backspace.cap.maxX - 395.3) < 1)
}

@Test func nearestKeyCoversEdgesAndGaps() throws {
    let geometry = KeyGeometry(layout: try #require(Layout.bundled("en-letters")), width: 402, origin: CGPoint(x: 0, y: 44))
    let cases: [(CGPoint, String)] = [
        (CGPoint(x: 0, y: 44), "q"),         // above and left of everything
        (CGPoint(x: 5, y: 44 + 7 + 54 + 27), "a"),  // row 2 indent
        (CGPoint(x: 58, y: 44 + 7 + 108 + 27), "shift"),  // inside the shift/z gap, nearer shift
        (CGPoint(x: 401, y: 269), "return"), // bottom-right corner
    ]
    for (point, id) in cases { #expect(geometry.key(at: point)?.key.id == id) }
}

@Test func keyUnitsMatchLayoutCenters() throws {
    let layout = try #require(Layout.bundled("en-letters"))
    let geometry = KeyGeometry(layout: layout, width: 402, origin: CGPoint(x: 0, y: 44))
    for frame in geometry.frames where frame.key.kind == .char {
        let units = geometry.keyUnits(CGPoint(x: frame.hit.midX, y: frame.hit.midY))
        let center = try #require(layout.keyCenters()[frame.key.output])
        #expect(abs(units.x - center.x) < 1e-9 && abs(units.y - center.y) < 1e-9)
    }
}
