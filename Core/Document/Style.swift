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
    /// An installed font family by name. nil means the system font, shaped by
    /// `design`.
    ///
    /// Stored as a name rather than embedded, which means a document can arrive
    /// on a Mac that does not have the font. It falls back to the system font
    /// rather than refusing to draw — see `isAvailable` — and the import sheet
    /// says so before anything is added.
    var family: String?

    init(size: Double,
         weight: Weight = .regular,
         design: Design = .default,
         monospacedDigits: Bool = true,
         family: String? = nil) {
        self.size = size
        self.weight = weight
        self.design = design
        self.monospacedDigits = monospacedDigits
        self.family = family
    }

    enum CodingKeys: String, CodingKey {
        case size, weight, design, monospacedDigits, family
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Defaulted, not required. See the note on Style's own decoder.
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 13
        weight = try c.decodeIfPresent(Weight.self, forKey: .weight) ?? .regular
        design = try c.decodeIfPresent(Design.self, forKey: .design) ?? .default
        monospacedDigits = try c.decodeIfPresent(Bool.self, forKey: .monospacedDigits) ?? true
        family = try c.decodeIfPresent(String.self, forKey: .family)
    }

    /// Whether this Mac actually has the named family.
    var isAvailable: Bool {
        guard let family, !family.isEmpty else { return true }
        return FontCatalogue.has(family)
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
        var f: Font
        if let family, !family.isEmpty, FontCatalogue.has(family) {
            f = Font.custom(family, size: size * scale).weight(weight.swiftUI)
        } else {
            // A named font this Mac does not have falls back rather than
            // refusing to draw. A widget that renders nothing because of a
            // missing typeface is worse than one that renders in San Francisco.
            f = Font.system(size: size * scale, weight: weight.swiftUI, design: design.swiftUI)
        }
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

    // MARK: Added in schema 3

    /// Degrees clockwise, about the element's centre.
    var rotation: Double
    /// Letter spacing, in points at the reference size. Small negative values
    /// are what make large numerals look typeset rather than typed.
    var tracking: Double
    /// A drop shadow. Radius 0 means none, which is the default — a shadow on
    /// by default would quietly soften every design anyone builds.
    var shadowRadius: Double
    var shadowColor: ColorSpec
    var shadowY: Double
    /// An outline drawn around a shape, independent of its fill.
    var strokeColor: ColorSpec?
    var strokeWidth: Double
    /// A second colour, turning a shape's fill or a bar's track into a
    /// gradient. nil keeps the flat fill.
    var gradientEnd: ColorSpec?
    var gradientAngle: Double
    /// Where a circular arc begins, in degrees clockwise from twelve, and how
    /// far it sweeps. The defaults are a full ring; 135 and 270 give the open
    /// gauge that every dashboard uses.
    var arcStart: Double
    var arcSweep: Double
    /// How an image fills its box.
    var contentMode: ContentMode

    enum ContentMode: String, Codable, CaseIterable {
        case fit, fill
        var displayName: String { self == .fit ? "Fit" : "Fill" }
    }

    init(font: FontSpec = FontSpec(size: 14),
         foreground: ColorSpec = .text,
         fill: ColorSpec? = nil,
         alignment: TextAlignment = .leading,
         lineLimit: Int = 1,
         cornerRadius: Double = 0,
         lineWidth: Double = 6,
         opacity: Double = 1,
         rotation: Double = 0,
         tracking: Double = 0,
         shadowRadius: Double = 0,
         shadowColor: ColorSpec = ColorSpec("#000000", opacity: 0.45),
         shadowY: Double = 2,
         strokeColor: ColorSpec? = nil,
         strokeWidth: Double = 1,
         gradientEnd: ColorSpec? = nil,
         gradientAngle: Double = 135,
         arcStart: Double = 0,
         arcSweep: Double = 360,
         contentMode: ContentMode = .fit) {
        self.font = font
        self.foreground = foreground
        self.fill = fill
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.rotation = rotation
        self.tracking = tracking
        self.shadowRadius = shadowRadius
        self.shadowColor = shadowColor
        self.shadowY = shadowY
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.gradientEnd = gradientEnd
        self.gradientAngle = gradientAngle
        self.arcStart = arcStart
        self.arcSweep = arcSweep
        self.contentMode = contentMode
    }

    /// Every field added after schema 2 decodes with a default, so a document
    /// written by an older build still opens rather than failing to parse.
    /// This is the whole reason the format is hand-decoded here instead of
    /// relying on the synthesised initialiser.
    enum CodingKeys: String, CodingKey {
        case font, foreground, fill, alignment, lineLimit, cornerRadius, lineWidth, opacity
        case rotation, tracking, shadowRadius, shadowColor, shadowY
        case strokeColor, strokeWidth, gradientEnd, gradientAngle
        case arcStart, arcSweep, contentMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every field defaulted, including the ones that have been here since
        // schema 1.
        //
        // Half-tolerance is not tolerance. The post-schema-2 fields were
        // already optional while these were required, which means a document
        // missing any one of them fails to decode *entirely* — and that failure
        // is invisible, because slot one falls back to any document of the
        // right size and the desktop simply shows a different design. The same
        // shape of bug was found and fixed in `Format`; this is the rest of it.
        font = try c.decodeIfPresent(FontSpec.self, forKey: .font) ?? FontSpec(size: 13)
        foreground = try c.decodeIfPresent(ColorSpec.self, forKey: .foreground)
            ?? ColorSpec("#FFFFFF")
        fill = try c.decodeIfPresent(ColorSpec.self, forKey: .fill)
        alignment = try c.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? .leading
        lineLimit = try c.decodeIfPresent(Int.self, forKey: .lineLimit) ?? 1
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 6
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        tracking = try c.decodeIfPresent(Double.self, forKey: .tracking) ?? 0
        shadowRadius = try c.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? 0
        shadowColor = try c.decodeIfPresent(ColorSpec.self, forKey: .shadowColor)
            ?? ColorSpec("#000000", opacity: 0.45)
        shadowY = try c.decodeIfPresent(Double.self, forKey: .shadowY) ?? 2
        strokeColor = try c.decodeIfPresent(ColorSpec.self, forKey: .strokeColor)
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 1
        gradientEnd = try c.decodeIfPresent(ColorSpec.self, forKey: .gradientEnd)
        gradientAngle = try c.decodeIfPresent(Double.self, forKey: .gradientAngle) ?? 135
        arcStart = try c.decodeIfPresent(Double.self, forKey: .arcStart) ?? 0
        arcSweep = try c.decodeIfPresent(Double.self, forKey: .arcSweep) ?? 360
        contentMode = try c.decodeIfPresent(ContentMode.self, forKey: .contentMode) ?? .fit
    }

    /// The fill as a shape style — a gradient when a second colour is set,
    /// otherwise the flat colour. Type-erased because `fill` and `stroke` need
    /// one concrete `ShapeStyle`, not a branch between two.
    func paint(_ base: ColorSpec) -> AnyShapeStyle {
        guard let end = gradientEnd else { return AnyShapeStyle(base.color) }
        return AnyShapeStyle(LinearGradient(colors: [base.color, end.color],
                                            startPoint: gradientStart,
                                            endPoint: gradientStop))
    }

    private var gradientStart: UnitPoint {
        let r = gradientAngle * .pi / 180
        return UnitPoint(x: 0.5 - cos(r) * 0.5, y: 0.5 - sin(r) * 0.5)
    }

    private var gradientStop: UnitPoint {
        let r = gradientAngle * .pi / 180
        return UnitPoint(x: 0.5 + cos(r) * 0.5, y: 0.5 + sin(r) * 0.5)
    }
}

// MARK: - Bridging back from SwiftUI

extension ColorSpec {
    /// Round-trips a colour picked in the inspector back into the document's
    /// hex form. Converted through sRGB explicitly: `NSColor(Color)` can hand
    /// back a catalog or display-P3 colour whose components are meaningless as
    /// hex, and the widget would then render a different colour from the one
    /// the user chose.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        self.init(String(format: "#%02X%02X%02X",
                         Int((ns.redComponent * 255).rounded()),
                         Int((ns.greenComponent * 255).rounded()),
                         Int((ns.blueComponent * 255).rounded())),
                  opacity: ns.alphaComponent)
    }

    /// Opaque form, for a picker that manages opacity separately.
    var opaqueColor: Color { Color(nsColor: nsColor) }
}
