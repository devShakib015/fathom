import Foundation

/// One drawable thing on a widget.
///
/// The six kinds here are the whole vocabulary of v1, and the vocabulary is
/// the hard ceiling on what anybody can ever build with Fathom — an extension
/// interprets a document, it cannot compile new code. So these were chosen to
/// compose rather than to enumerate: a "temperature widget" is not a kind, it
/// is a text bound to a number next to a symbol bound to a condition.
struct Element: Codable, Identifiable, Hashable {
    var id: UUID
    /// Shown in the editor's layer list. Optional because a default derived
    /// from the content reads better than "Text 4" until the user renames it.
    var name: String?
    var kind: Kind
    var frame: Frame
    var style: Style
    /// The literal content: the string for `.text`, the SF Symbol name for
    /// `.symbol`, a number for `.arc`, comma-separated numbers for `.spark`.
    /// When `binding` is nil this is what renders. When a binding is present
    /// this is what the editor shows as a design-time preview.
    var text: String
    /// nil means the element shows `text` literally.
    var binding: DataBinding?
    /// Nested elements, in unit space *relative to this element's own box*.
    ///
    /// Only `.repeater` and `.group` draw children today, but the model allows
    /// them anywhere and the renderer recurses, so a future container kind
    /// needs no format change. Frames being relative all the way down is what
    /// makes that free.
    var children: [Element]
    /// An expression that decides whether this element draws at all.
    ///
    /// Empty means always. "Hide this when the value is zero" is one of the
    /// most common things anyone wants from a data-driven design, and without
    /// it every such widget needs a second document.
    var visibleWhen: String?

    init(id: UUID = UUID(),
         name: String? = nil,
         kind: Kind,
         frame: Frame,
         style: Style = Style(),
         text: String = "",
         binding: DataBinding? = nil,
         children: [Element] = [],
         visibleWhen: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.style = style
        self.text = text
        self.binding = binding
        self.children = children
        self.visibleWhen = visibleWhen
    }

    /// Older documents have no `children` or `visibleWhen` key at all.
    enum CodingKeys: String, CodingKey {
        case id, name, kind, frame, style, text, binding, children, visibleWhen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        frame = try c.decode(Frame.self, forKey: .frame)
        style = try c.decode(Style.self, forKey: .style)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        binding = try c.decodeIfPresent(DataBinding.self, forKey: .binding)
        children = try c.decodeIfPresent([Element].self, forKey: .children) ?? []
        visibleWhen = try c.decodeIfPresent(String.self, forKey: .visibleWhen)
    }

    var isContainer: Bool { kind == .repeater || kind == .group }

    enum Kind: String, Codable, CaseIterable {
        case text
        case symbol
        case shape
        case divider
        case arc
        case spark
        /// A picture fetched from a URL, literal or bound.
        case image
        /// A straight progress bar. An arc says "a proportion of a whole"; a
        /// bar says "how far along", and designs want both.
        case bar
        /// Repeats its children once per item of a bound array. This is what
        /// turns a seven-day forecast into seven columns without seven copies
        /// of the same three elements.
        case repeater
        /// Children positioned inside this element's box, moved and hidden
        /// together. No drawing of its own.
        case group

        var displayName: String {
            switch self {
            case .text: "Text"
            case .symbol: "Symbol"
            case .shape: "Shape"
            case .divider: "Divider"
            case .arc: "Arc"
            case .spark: "Sparkline"
            case .image: "Image"
            case .bar: "Bar"
            case .repeater: "Repeater"
            case .group: "Group"
            }
        }

        /// The SF Symbol used for this kind in the editor's palette.
        var paletteSymbol: String {
            switch self {
            case .text: "textformat"
            case .symbol: "star"
            case .shape: "rectangle"
            case .divider: "minus"
            case .arc: "circle.dotted"
            case .spark: "waveform.path.ecg"
            case .image: "photo"
            case .bar: "chart.bar.fill"
            case .repeater: "square.grid.3x1.below.line.grid.1x2"
            case .group: "square.on.square"
            }
        }
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(24)) }
        return kind.displayName
    }
}

// MARK: - Defaults

extension Element {
    /// A new element of `kind`, sized and styled so that it is visible and
    /// sensible the moment it lands on the canvas.
    ///
    /// Dropping something invisible — a zero-width shape, white text on a
    /// light background, an arc bound to nothing — is the fastest way to make
    /// a builder feel broken, so every default here renders as *something*.
    static func new(_ kind: Kind, in doc: WidgetDoc) -> Element {
        // Placed slightly below and right of whatever is already there, so a
        // run of additions fans out instead of stacking into one pile.
        let offset = min(Double(doc.elements.count) * 0.03, 0.3)

        switch kind {
        case .text:
            return Element(kind: .text,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.5, height: 0.14),
                           style: Style(font: FontSpec(size: 18, weight: .semibold), foreground: .text),
                           text: "Text")
        case .symbol:
            return Element(kind: .symbol,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.18, height: 0.18),
                           style: Style(foreground: .accent, alignment: .center),
                           text: "star.fill")
        case .shape:
            return Element(kind: .shape,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.4, height: 0.2),
                           style: Style(fill: ColorSpec(Palette.accentHex, opacity: 0.18),
                                        cornerRadius: 10))
        case .divider:
            return Element(kind: .divider,
                           frame: Frame(x: 0.08, y: 0.10 + offset, width: 0.84, height: 0.02),
                           style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.35),
                                        lineWidth: 1))
        case .arc:
            return Element(kind: .arc,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.3, height: 0.3),
                           style: Style(foreground: .accent,
                                        fill: ColorSpec(Palette.accentHex, opacity: 0.16),
                                        lineWidth: 6),
                           text: "0.65")
        case .spark:
            return Element(kind: .spark,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.5, height: 0.22),
                           style: Style(foreground: ColorSpec(Palette.accentAltHex),
                                        fill: ColorSpec(Palette.accentAltHex, opacity: 0.3),
                                        lineWidth: 6),
                           text: "12,15,13,19,17,24,22,29")
        case .image:
            return Element(kind: .image,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.34, height: 0.34),
                           style: Style(foreground: .dim, cornerRadius: 10),
                           text: "")
        case .bar:
            return Element(kind: .bar,
                           frame: Frame(x: 0.08, y: 0.10 + offset, width: 0.6, height: 0.06),
                           style: Style(foreground: .accent,
                                        fill: ColorSpec(Palette.accentHex, opacity: 0.16)))
        case .group:
            return Element(kind: .group,
                           frame: Frame(x: 0.08, y: 0.08 + offset, width: 0.6, height: 0.3),
                           style: Style())
        case .repeater:
            // Ships with one child, because an empty repeater draws nothing at
            // all and reads as broken rather than as waiting for content.
            return Element(kind: .repeater,
                           frame: Frame(x: 0.06, y: 0.08 + offset, width: 0.88, height: 0.3),
                           style: Style(lineWidth: 4),
                           children: [
                               Element(name: "Item",
                                       kind: .text,
                                       frame: Frame(x: 0, y: 0, width: 1, height: 1),
                                       style: Style(font: FontSpec(size: 13, weight: .medium),
                                                    foreground: .text,
                                                    alignment: .center),
                                       text: "—",
                                       binding: nil),
                           ])
        }
    }
}

extension Element {
    /// How many rows a repeater will ever draw.
    ///
    /// An endpoint returning 500 hourly readings would otherwise produce 500
    /// sets of views inside a widget that can show maybe eight, and the
    /// extension would be killed for it long before anyone saw a layout.
    static let repeaterLimit = 48
}
