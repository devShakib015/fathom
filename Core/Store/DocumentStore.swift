import Foundation
import WidgetKit

/// Reads and writes widget documents in the shared container.
///
/// Both sides use this class: the app writes, the extension reads. There is no
/// database and no observation — the extension is a fresh process on nearly
/// every timeline reload, so it re-reads from disk every time, and that is
/// cheaper than any cache would be.
struct DocumentStore {
    static let shared = DocumentStore()

    private let fileExtension = "fathom"

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        // Sorted keys and pretty printing because these files are meant to be
        // readable: sharing is designed for now and shipped later, and the
        // first thing anyone will do with a shared widget is open it.
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Reading

    func allDocuments() -> [WidgetDoc] {
        guard let dir = AppGroup.documents,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }

        return names
            .filter { $0.hasSuffix(".\(fileExtension)") }
            .sorted()
            .compactMap { document(at: dir.appendingPathComponent($0)) }
    }

    func document(id: UUID) -> WidgetDoc? {
        guard let dir = AppGroup.documents else { return nil }
        return document(at: dir.appendingPathComponent("\(id.uuidString).\(fileExtension)"))
    }

    func document(at url: URL) -> WidgetDoc? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(WidgetDoc.self, from: data).sanitised
        } catch {
            AppGroup.log.error("Unreadable document at \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Writing

    @discardableResult
    func save(_ doc: WidgetDoc) -> Bool {
        guard let dir = AppGroup.documents else {
            AppGroup.log.error("Cannot save: \(AppGroup.diagnosis)")
            return false
        }
        let url = dir.appendingPathComponent("\(doc.id.uuidString).\(fileExtension)")
        do {
            try encoder.encode(doc.sanitised).write(to: url, options: .atomic)
            return true
        } catch {
            AppGroup.log.error("Save failed: \(error.localizedDescription)")
            return false
        }
    }

    func delete(id: UUID) {
        guard let dir = AppGroup.documents else { return }
        try? FileManager.default.removeItem(
            at: dir.appendingPathComponent("\(id.uuidString).\(fileExtension)"))
    }

    /// Ask WidgetKit to rebuild every placed widget now. Called after a save so
    /// an edit shows up immediately rather than at the next 64-second tick.
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Which document a placed widget shows

extension DocumentStore {
    /// v1 binds one document per family. That is a real limitation — two small
    /// widgets on the desktop will show the same thing — and the fix is an
    /// `AppIntentConfiguration` so each placement can pick its own document.
    /// Doing it this way first keeps the end-to-end path short enough to prove
    /// before the editor exists.
    private var activeFileURL: URL? {
        AppGroup.container?.appendingPathComponent("active.json")
    }

    func activeDocumentID(for family: WidgetDoc.Family) -> UUID? {
        guard let url = activeFileURL,
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: UUID].self, from: data)
        else { return nil }
        return map[family.rawValue]
    }

    func activeDocument(for family: WidgetDoc.Family) -> WidgetDoc? {
        if let id = activeDocumentID(for: family), let doc = document(id: id), doc.family == family {
            return doc
        }
        return allDocuments().first { $0.family == family }
    }

    func setActiveDocument(_ id: UUID?, for family: WidgetDoc.Family) {
        guard let url = activeFileURL else { return }
        var map = (try? JSONDecoder().decode([String: UUID].self, from: Data(contentsOf: url))) ?? [:]
        map[family.rawValue] = id
        if id == nil { map.removeValue(forKey: family.rawValue) }
        try? JSONEncoder().encode(map).write(to: url, options: .atomic)
    }
}
