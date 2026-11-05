import CoreGraphics
import Testing
@testable import KalamEngine

/// Apple's iPhone 17 layout (docs/reference/apple/README.md) with 4 pt cap gaps (Apple's are 6) and
/// 58 pt rows (device round 4: bigger keys).
@Test func englishCapPositions() throws {
    let geometry = KeyGeometry(layout: try #require(Layout.bundled("en-letters")), width: 402)
    func cap(_ id: String) throws -> CGRect { try #require(geometry.frames.first { $0.key.id == id }).cap }
    let expected: [(String, CGFloat, CGFloat)] = [
        ("q", 5.4, 40.92), ("p", 361.08, 396.6), ("a", 25.16, 60.68), ("shift", 5.4, 52.78),
        ("z", 64.68, 100.2), ("backspace", 349.22, 396.6), ("numbers", 5.4, 50.8),
        ("lang", 54.8, 100.2), ("space", 104.2, 297.8), ("return", 301.8, 396.6),
    ]
    for (id, minX, maxX) in expected {
        #expect(abs(try cap(id).minX - minX) < 0.01, "\(id) minX")
        #expect(abs(try cap(id).maxX - maxX) < 0.01, "\(id) maxX")
    }
    #expect(abs(try cap("q").height - 48.8) < 1e-9)
    #expect(try cap("a").minY - cap("q").minY == KeyGeometry.rowPitch)
}

@Test func arabicPitchIsElevenKeysWide() throws {
    let geometry = KeyGeometry(layout: try #require(Layout.bundled("ar-letters")), width: 402)
    #expect(abs(geometry.unit - 35.9) < 0.05)
    let backspace = try #require(geometry.frames.first { $0.key.id == "backspace" })
    #expect(abs(backspace.cap.maxX - 396.6) < 0.01)
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

@Test func keyAreaHeightPerSetting() {
    #expect(abs(KeyGeometry.height(.default, numberRow: false) - KeyGeometry.height) < 1e-9)
    let expected: [(KeyboardHeight, CGFloat, CGFloat)] = [(.compact, 218.4, 252.4), (.default, 234.4, 272.4), (.tall, 250.4, 292.4)]
    for (setting, off, on) in expected {
        #expect(abs(KeyGeometry.height(setting, numberRow: false) - off) < 1e-9)
        #expect(abs(KeyGeometry.height(setting, numberRow: true) - on) < 1e-9)
        #expect(KeyGeometry.rowPitch(setting, numberRow: false, rows: 4) == CGFloat(setting.rowPitch))
        #expect(KeyGeometry.rowPitch(setting, numberRow: true, rows: 5) == CGFloat(setting.rowPitch) - 4)
    }
}

/// Rows tile from the same top with no gaps, and every page fills the setting's key area.
@Test(arguments: KeyboardHeight.allCases, [false, true])
func rowsTileTheKeyArea(_ setting: KeyboardHeight, _ numberRow: Bool) throws {
    let letters = try #require(Layout.bundled("en-letters"))
    for layout in [numberRow ? letters.withNumberRow(digits: "1234567890".map(String.init)) : letters, try #require(Layout.bundled("en-numbers"))] {
        let pitch = KeyGeometry.rowPitch(setting, numberRow: numberRow, rows: layout.rows.count)
        let geometry = KeyGeometry(layout: layout, width: 402, origin: CGPoint(x: 0, y: 40), rowPitch: pitch)
        let tops = Set(geometry.frames.map(\.hit.minY)).sorted()
        #expect(tops.count == layout.rows.count)
        #expect(abs(tops[0] - (40 + 2)) < 1e-9)
        for frame in geometry.frames {
            #expect(frame.hit.height == pitch)
            #expect(abs(frame.cap.height - (pitch - 9.2)) < 1e-9)
        }
        for (a, b) in zip(tops, tops.dropFirst()) { #expect(abs(b - a - pitch) < 1e-9) }
        let lowestCap = try #require(geometry.frames.map(\.cap.maxY).max())
        #expect(abs(lowestCap + 4.5 - (40 + KeyGeometry.height(setting, numberRow: numberRow))) < 1e-9)
    }
}

/// SPEC 5.2: tap points stay in the page's own key units at every height, with or without the number row.
@Test(arguments: KeyboardHeight.allCases, ["en-letters", "ar-letters"])
func keyUnitsIgnoreHeightAndNumberRow(_ setting: KeyboardHeight, _ id: String) throws {
    let plain = try #require(Layout.bundled(id))
    let centers = plain.keyCenters()
    for numberRow in [false, true] {
        let layout = numberRow ? plain.withNumberRow(digits: "1234567890".map(String.init)) : plain
        let pitch = KeyGeometry.rowPitch(setting, numberRow: numberRow, rows: layout.rows.count)
        let geometry = KeyGeometry(layout: layout, width: 402, origin: CGPoint(x: 0, y: 40), rowPitch: pitch)
        for frame in geometry.frames where frame.key.kind == .char {
            #expect(frame.inNumberRow == (numberRow && frame.hit.minY < 42 + 1))
            let units = geometry.keyUnits(CGPoint(x: frame.hit.midX, y: frame.hit.midY))
            if frame.inNumberRow {
                #expect(abs(units.y + 0.5) < 1e-9)
                continue
            }
            let center = try #require(centers[frame.key.output])
            #expect(abs(units.x - center.x) < 1e-9 && abs(units.y - center.y) < 1e-9, "\(frame.key.id)")
        }
    }
}
