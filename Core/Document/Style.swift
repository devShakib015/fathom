import SwiftUI

// Geometry, colour and type for a design document.
//
// Everything here is stored in a form that survives being written to JSON,
// read back by a different build, and one day handed to somebody else's Mac.
// That means: no NSColor archives, no synthesised integer enum cases, no
// absolute pixel measurements.

/// A rectangle in unit space: 0…1 across the widget's box, origin top-left.
///
/// Widget families are not a fixed number of points — the same `systemSmall`
/// is a different size on a Retina desktop than on an external display, and
/// Apple has changed the numbers between releases. Storing 0…1 and
/// multiplying at render time is the only version of this that keeps working.
struct Frame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = Frame(x: 0, y: 0, width: 1, height: 1)

    /// The concrete rect this frame describes inside a box of `size`.
    func resolved(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width,
               y: y * size.height,
               width: width * size.width,
               height: height * size.height)
    }

    /// Clamped so an element can never be dragged entirely off the canvas.
    var normalised: Frame {
        Frame(x: min(max(x, -0.5), 1.5),
              y: min(max(y, -0.5), 1.5),
              width: min(max(width, 0.01), 2),
              height: min(max(height, 0.01), 2))
    }
}

/// A colour as `#RRGGBB` plus a separate opacity.
///
/// Hex because it is the one colour encoding every human and every tool can
/// read. Opacity is kept out of the hex so that an eight-digit string never
/// has to be disambiguated from a six-digit one.
struct ColorSpec: Codable, Hashable {
    var hex: String
    var opacity: Double

    init(_ hex: String, opacity: Double = 1) {
        self.hex = hex
        self.opacity = opacity
    }

    var color: Color {
        Color(nsColor: nsColor).opacity(opacity)
    }

    var nsColor: NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1) // loud on purpose
        }
        return NSColor(srgbRed: Double((v >> 16) & 0xFF) / 255,
                       green: Double((v >> 8) & 0xFF) / 255,
                       blue: Double(v & 0xFF) / 255,
                       alpha: 1)
    }

    static let text = ColorSpec(Palette.textHex)
    static let dim = ColorSpec(Palette.textDimHex)
    static let accent = ColorSpec(Palette.accentHex)
}

/// Type. `size` is in points *at the family's reference size*; the renderer
/// scales it by the same factor it scales the box, so a design laid out at
/// 170×170 still reads correctly at 190×190.
struct FontSpec: Codable, Hashable {
    var size: Double
    var weight: Weight
    var design: Design
    /// Digits that do not jitter as the value changes. On by default for
    /// anything bound to data, because a 64-second refresh makes reflow
    /// visible in a way a static label never does.
    var monospacedDigits: Bool

    init(size: Double, weight: Weight = .regular, design: Design = .default, monospacedDigits: Bool = true) {
        self.size = size
        self.weight = weight
        self.design = design
        self.monospacedDigits = monospacedDigits
    }

    enum Weight: String, Codable, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
        var swiftUI: Font.Weight {
            switch self {
            case .ultraLight: .ultraLight
            case .thin: .thin
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
            }
        }
    }

    enum Design: String, Codable, CaseIterable {
        case `default`, rounded, monospaced, serif
        var swiftUI: Font.Design {
            switch self {
            case .default: .default
            case .rounded: .rounded
            case .monospaced: .monospaced
            case .serif: .serif
            }
        }
    }

    func font(scale: Double) -> Font {
        var f = Font.system(size: size * scale, weight: weight.swiftUI, design: design.swiftUI)
        if monospacedDigits { f = f.monospacedDigit() }
        return f
    }
}

enum TextAlignment: String, Codable, CaseIterable {
    case leading, center, trailing

    var swiftUI: SwiftUI.TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Everything an element can be styled with. Not every field applies to every
/// kind — `lineWidth` means nothing to a text element — but one flat struct
/// keeps the JSON legible and the inspector trivial to write. Fields that do
/// not apply are simply ignored by that kind's renderer.
struct Style: Codable, Hashable {
    var font: FontSpec
    var foreground: ColorSpec
    var fill: ColorSpec?
    var alignment: TextAlignment
    var lineLimit: Int
    var cornerRadius: Double
    var lineWidth: Double
    var opacity: Double

    init(font: FontSpec = FontSpec(size: 14),
         foreground: ColorSpec = .text,
         fill: ColorSpec? = nil,
         alignment: TextAlignment = .leading,
         lineLimit: Int = 1,
         cornerRadius: Double = 0,
         lineWidth: Double = 6,
         opacity: Double = 1) {
        self.font = font
        self.foreground = foreground
        self.fill = fill
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.opacity = opacity
    }
}
