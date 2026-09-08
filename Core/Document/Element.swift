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
    var binding: Binding?

    init(id: UUID = UUID(),
         name: String? = nil,
         kind: Kind,
         frame: Frame,
         style: Style = Style(),
         text: String = "",
         binding: Binding? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.style = style
        self.text = text
        self.binding = binding
    }

    enum Kind: String, Codable, CaseIterable {
        case text
        case symbol
        case shape
        case divider
        case arc
        case spark

        var displayName: String {
            switch self {
            case .text: "Text"
            case .symbol: "Symbol"
            case .shape: "Shape"
            case .divider: "Divider"
            case .arc: "Arc"
            case .spark: "Sparkline"
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
