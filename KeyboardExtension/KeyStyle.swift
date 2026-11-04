import UIKit

/// Colors from docs/reference/README.md (iPhone 17, iOS 27). The panel itself is the system's
/// `.keyboard` input view backdrop.
struct Palette {
    let key: UIColor
    let keyPressed: UIColor
    let label: UIColor
    let secondaryLabel: UIColor
    let bubble: UIColor
    let strip: UIColor
    let stripSelection: UIColor
    let barText: UIColor
    let barDivider: UIColor

    static let light = Palette(
        key: .white, keyPressed: UIColor(white: 0xDC / 255, alpha: 1), label: .black,
        secondaryLabel: UIColor(white: 0x8E / 255, alpha: 1), bubble: .white, strip: .white,
        stripSelection: UIColor(red: 0xE3 / 255, green: 0xE4 / 255, blue: 0xE6 / 255, alpha: 1),
        barText: UIColor(red: 0x4A / 255, green: 0x4A / 255, blue: 0x4C / 255, alpha: 1),
        barDivider: UIColor(red: 0xD3 / 255, green: 0xD4 / 255, blue: 0xD9 / 255, alpha: 1))

    static let dark = Palette(
        key: UIColor(white: 0x44 / 255, alpha: 1), keyPressed: UIColor(white: 0x67 / 255, alpha: 1), label: .white,
        secondaryLabel: UIColor(white: 0x9A / 255, alpha: 1), bubble: UIColor(white: 0x56 / 255, alpha: 1),
        strip: UIColor(white: 0x35 / 255, alpha: 1), stripSelection: UIColor(white: 0x56 / 255, alpha: 1),
        barText: UIColor(white: 0xA2 / 255, alpha: 1),
        barDivider: UIColor(red: 0x31 / 255, green: 0x31 / 255, blue: 0x33 / 255, alpha: 1))
}

/// Label sizes in points, matched to the captures by ink height.
enum KeyFont {
    static let lowercase = UIFont.systemFont(ofSize: 25, weight: .regular)
    static let uppercase = UIFont.systemFont(ofSize: 21.6, weight: .regular)
    static let arabic = UIFont.systemFont(ofSize: 21.7, weight: .regular)
    /// Case-sensitive forms raise brackets and dashes to sit with digits, as Apple's keys do.
    static let symbol = UIFont(descriptor: uppercase.fontDescriptor.addingAttributes([.featureSettings: [[
        UIFontDescriptor.FeatureKey.type: kCaseSensitiveLayoutType,
        UIFontDescriptor.FeatureKey.selector: kCaseSensitiveLayoutOnSelector,
    ]]]), size: 0)
    static let function = UIFont.systemFont(ofSize: 18, weight: .regular)
    /// Apple sets "#+=" smaller and heavier than the other page labels.
    static let symbolsPage = UIFont.systemFont(ofSize: 12.8, weight: .semibold)
    static let arabicFunction = UIFont.systemFont(ofSize: 15, weight: .regular)
    /// The "123" key on the #+= pages, a little smaller than the bottom row's.
    static let numbersPage = UIFont.systemFont(ofSize: 15.3, weight: .regular)
    static let arabicNumbersPage = UIFont.systemFont(ofSize: 18, weight: .regular)
    /// The Arabic tanween key, drawn on a dotted circle.
    static let tanween = UIFont.systemFont(ofSize: 25, weight: .regular)
    static let hint = UIFont.systemFont(ofSize: 10, weight: .regular)
    static let spaceMark = UIFont.systemFont(ofSize: 10, weight: .regular)
    static let bar = UIFont.systemFont(ofSize: 17, weight: .regular)
    static let iconSize: CGFloat = 19
}

/// Renders labels and SF Symbols once into bitmaps used as layer contents.
final class GlyphCache {
    private var images: [String: CGImage] = [:]
    var scale: CGFloat = 3

    func text(_ string: String, font: UIFont, color: UIColor) -> CGImage? {
        let id = "t|\(string)|\(font.pointSize)|\(font.fontName)|\(color.hashValue)"
        return cached(id) {
            let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            let size = attributed.size()
            return render(CGSize(width: ceil(size.width), height: ceil(size.height))) { _ in attributed.draw(at: .zero) }
        }
    }

    func symbol(_ name: String, size: CGFloat, color: UIColor) -> CGImage? {
        cached("s|\(name)|\(size)|\(color.hashValue)") {
            let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
            guard let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
            return render(image.size) { _ in image.draw(at: .zero) }
        }
    }

    private func cached(_ id: String, make: () -> CGImage?) -> CGImage? {
        if let image = images[id] { return image }
        let image = make()
        images[id] = image
        return image
    }

    private func render(_ size: CGSize, draw: (UIGraphicsImageRendererContext) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: draw).cgImage
    }
}
