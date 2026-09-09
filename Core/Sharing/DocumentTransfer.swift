import Foundation

/// Reading and writing `.fathom` files, and saying what is in one before it
/// runs.
///
/// Section 9.2 settled that the format would be designed for sharing and that
/// sharing would not ship until there was a trust story. This is that story.
/// A widget is not a picture — it can call a URL, read your calendar, open a
/// link when a condition holds — so the question "what will this do?" has to be
/// answerable **before** anything is added, from the file alone, without
/// running it.
enum DocumentTransfer {

    static let fileExtension = "fathom"

    /// Everything worth knowing about a document somebody sent you.
    struct Inspection: Identifiable {
        var id: UUID { doc.id }
        var doc: WidgetDoc
        /// Endpoints it will contact on every refresh.
        var hosts: [String]
        /// Personal data it wants: calendar, reminders.
        var permissions: [DataSource.Kind]
        /// Fonts it names that this Mac does not have.
        var missingFonts: [String]
        /// Written by a build newer than this one, so it may use features this
        /// version cannot draw.
        var isFromNewerVersion: Bool
        var elementCount: Int
        /// What clicking it will do, in plain words, one line per action.
        ///
        /// A design that opens a link or runs a shortcut when clicked is the
        /// single most important thing to tell somebody *before* they install
        /// it, and the only point at which telling them is useful.
        var actions: [String]

        /// True when the document does nothing the recipient has to think
        /// about — no network, no personal data, nothing missing, nothing that
        /// happens when it is clicked.
        var isInert: Bool {
            hosts.isEmpty && permissions.isEmpty && missingFonts.isEmpty
                && actions.isEmpty && !isFromNewerVersion
        }
    }

    // MARK: - Writing

    static func data(for doc: WidgetDoc) throws -> Data {
        var copy = doc.sanitised
        // Provenance is about this Mac's catalog and means nothing on another;
        // and a fresh identity stops an import overwriting a document the
        // recipient already has.
        copy.origin = nil
        copy.id = UUID()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(copy)
    }

    static func suggestedFilename(for doc: WidgetDoc) -> String {
        let safe = doc.name
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? "Widget" : safe).\(fileExtension)"
    }

    // MARK: - Reading

    static func inspect(_ data: Data) throws -> Inspection {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var doc = try decoder.decode(WidgetDoc.self, from: data).sanitised
        // Always a new identity: importing the same file twice should give two
        // widgets, not silently replace the first.
        doc.id = UUID()
        doc.origin = nil

        return Inspection(
            doc: doc,
            hosts: doc.declaredHosts,
            permissions: doc.sources.map(\.kind).filter(\.needsPermission).uniqued(),
            missingFonts: FontCatalogue.missing(in: doc),
            isFromNewerVersion: doc.schemaVersion > WidgetDoc.currentSchemaVersion,
            elementCount: doc.elements.allIDs().count,
            actions: doc.declaredActions)
    }

    static func inspect(contentsOf url: URL) throws -> Inspection {
        // A file chosen in an open panel is readable inside the sandbox, but
        // only while the scope is held.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try inspect(try Data(contentsOf: url))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
