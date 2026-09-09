import Foundation
import FoundationModels

/// On-device widget generation, using Apple's Foundation Models.
///
/// **This lives in the app and never in the widget extension, deliberately.**
/// Keeping render time deterministic is what makes "at most 64 seconds stale"
/// a true statement, and running a language model on every reload would be
/// neither fast nor honest. The model helps you *build* a widget; the widget
/// itself stays data.
///
/// It also keeps Fathom's promises exactly as written: on device,
/// no account, no network, no cost. Nothing typed here leaves the Mac.
///
/// **What it is asked to do is narrow on purpose.** The system model is small,
/// with a context window to match, and asking it to emit a whole document —
/// unit frames, styles, bindings, expressions — would produce plausible JSON
/// that renders as nonsense. It is asked instead to *choose*: which of the
/// designed layouts, which palette, which size. That is a classification task
/// with a bounded vocabulary, which a small model does well, and every answer
/// is validated against the catalog before anything is built. The worst case
/// is a reasonable widget rather than a broken one.
enum Intelligence {

    // MARK: - Availability

    enum Status: Equatable {
        case ready
        case notEnabled
        case notEligible
        case notReady
        case unsupported

        var isReady: Bool { self == .ready }

        /// What to tell someone, in their terms rather than the framework's.
        var explanation: String {
            switch self {
            case .ready: ""
            case .notEnabled: "Turn on Apple Intelligence in System Settings to describe widgets in words."
            case .notEligible: "This Mac does not support Apple Intelligence. Everything else in Fathom works exactly the same."
            case .notReady: "Apple Intelligence is still downloading. Try again shortly."
            case .unsupported: "This build of macOS does not offer on-device models."
            }
        }
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .deviceNotEligible: return .notEligible
            case .modelNotReady: return .notReady
            @unknown default: return .unsupported
            }
        @unknown default:
            return .unsupported
        }
    }

    // MARK: - What the model is allowed to answer

    /// A choice among things Fathom already knows how to build.
    ///
    /// Every field is checked against the catalog afterwards, so a hallucinated
    /// layout name costs a fuzzy match rather than a broken document.
    @Generable
    struct WidgetPlan {
        @Guide(description: "The id of the single best-matching layout, copied exactly from the list of layouts given.")
        var layout: String

        @Guide(description: "The id of the palette that best fits the mood asked for, copied exactly from the list of palettes given.")
        var palette: String

        @Guide(description: "One of: small, medium, large, extraLarge. Pick small unless the request implies more room.")
        var size: String

        @Guide(description: "A name for this widget: one to three plain words, no punctuation.")
        var name: String
    }

    /// A field worth putting on a widget, chosen out of a fetched endpoint.
    @Generable
    struct FieldSuggestion {
        @Guide(description: "The key path, copied exactly from the list given.")
        var path: String

        @Guide(description: "A short human label for it: one or two words, sentence case.")
        var label: String
    }

    @Generable
    struct FieldSuggestions {
        @Guide(description: "Between three and six fields, most interesting first.")
        var fields: [FieldSuggestion]
    }

    // MARK: - Generating

    private static let designerInstructions = """
        You help someone pick a ready-made widget layout for their Mac desktop.
        You are given a list of layout ids with short descriptions, and a list of
        palette ids. Choose exactly one of each, copying the ids exactly as they
        appear. Never invent an id. Prefer the simplest layout that satisfies the
        request. If the request mentions a colour or a mood, let that decide the
        palette; otherwise pick one that suits the subject.
        """

    /// Turns a sentence into a choice.
    static func plan(for description: String) async throws -> WidgetPlan {
        let session = LanguageModelSession(instructions: designerInstructions)
        let response = try await session.respond(to: prompt(for: description),
                                                 generating: WidgetPlan.self)
        return response.content
    }

    private static func prompt(for description: String) -> String {
        // The catalog is described to the model rather than hardcoded into the
        // prompt, so a layout added tomorrow is available today.
        let layouts = Catalog.templates.map { template in
            "\(template.id): \(template.name). \(template.category.rawValue). \(template.tags.joined(separator: ", ")). Sizes: \(template.families.map(\.rawValue).joined(separator: "/"))."
        }.joined(separator: "\n")

        let palettes = Theme.all.map { "\($0.id): \($0.name) — \($0.mood)" }.joined(separator: "\n")

        return """
            Layouts:
            \(layouts)

            Palettes:
            \(palettes)

            The person asked for: "\(description)"

            Choose the best layout id, the best palette id, a size, and a name.
            """
    }

    // MARK: - Restyling

    @Generable
    struct PaletteChoice {
        @Guide(description: "The id of the palette that best fits the mood asked for, copied exactly from the list of palettes given.")
        var palette: String
    }

    /// Chooses a palette for a design that already exists.
    ///
    /// Narrower than `plan` on purpose, and narrower again than it looks: the
    /// model is not asked to restyle anything. It picks one id out of twenty,
    /// and the recolouring is done by `Restyle`, which is ordinary code with
    /// tests. The model's whole job is understanding that "warmer" means Ember
    /// and not Ice.
    static func palette(for description: String) async throws -> Theme {
        let session = LanguageModelSession(instructions: """
            You choose a colour palette to match a mood. You are given a list of \
            palettes, each with an id and a description of what it looks like. \
            Answer with exactly one id, copied from the list. Never invent one.
            """)

        let palettes = Theme.all.map { "\($0.id): \($0.name) — \($0.mood)" }
            .joined(separator: "\n")

        let response = try await session.respond(to: """
            Palettes:
            \(palettes)

            The person asked for: "\(description)"

            Choose the palette id that best fits.
            """, generating: PaletteChoice.self)

        // Validated against the catalogue like every other answer, so a
        // hallucinated id becomes a near match rather than a failure.
        let ids = Theme.all.map(\.id)
        let matched = PlanMatcher.match(response.content.palette, in: ids) ?? ids[0]
        return Theme.named(matched)
    }

    /// Picks the interesting fields out of an endpoint somebody just pasted.
    static func suggestFields(from paths: [(path: String, sample: String)]) async throws -> [FieldSuggestion] {
        // A small model with a small context: send the leaves, not the tree,
        // and cap it well short of the window.
        let listed = paths.prefix(60)
            .map { "\($0.path) = \($0.sample)" }
            .joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You help someone choose which values from a web endpoint are worth
            showing on a small desktop widget. Prefer values a person would
            glance at: temperatures, counts, statuses, times. Ignore identifiers,
            internal codes, timing metadata and anything that never changes.
            Copy key paths exactly.
            """)

        let response = try await session.respond(to: """
            Fields available:
            \(listed)

            Choose the three to six most useful for a widget.
            """, generating: FieldSuggestions.self)
        return response.content.fields
    }
}
