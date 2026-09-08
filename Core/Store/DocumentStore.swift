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
        guard let dir = SharedStore.documents,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }

        return names
            .filter { $0.hasSuffix(".\(fileExtension)") }
            .sorted()
            .compactMap { document(at: dir.appendingPathComponent($0)) }
    }

    func document(id: UUID) -> WidgetDoc? {
        guard let dir = SharedStore.documents else { return nil }
        return document(at: dir.appendingPathComponent("\(id.uuidString).\(fileExtension)"))
    }

    func document(at url: URL) -> WidgetDoc? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(WidgetDoc.self, from: data).sanitised
        } catch {
            SharedStore.log.error("Unreadable document at \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Writing

    @discardableResult
    func save(_ doc: WidgetDoc) -> Bool {
        guard let dir = SharedStore.documents else {
            SharedStore.log.error("Cannot save: \(SharedStore.diagnosis)")
            return false
        }
        let url = dir.appendingPathComponent("\(doc.id.uuidString).\(fileExtension)")
        do {
            try encoder.encode(doc.sanitised).write(to: url, options: .atomic)
            return true
        } catch {
            SharedStore.log.error("Save failed: \(error.localizedDescription)")
            return false
        }
    }

    func delete(id: UUID) {
        guard let dir = SharedStore.documents else { return }
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
    /// Assignments live in one small file keyed by slot. Slot one's key is the
    /// bare family name, which is what earlier builds wrote, so nothing has to
    /// be migrated.
    private var activeFileURL: URL? {
        SharedStore.container?.appendingPathComponent("active.json")
    }

    private func assignments() -> [String: UUID] {
        guard let url = activeFileURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: UUID].self, from: data)) ?? [:]
    }

    func activeDocumentID(for slot: WidgetSlot) -> UUID? {
        assignments()[slot.key]
    }

    /// What a slot renders.
    ///
    /// Slot one falls back to any document of the right size, so a widget
    /// placed before anything was assigned still shows something. The other
    /// slots do not: falling back there would make every slot show the same
    /// design, which is the exact problem slots exist to solve.
    func activeDocument(for slot: WidgetSlot) -> WidgetDoc? {
        if let id = activeDocumentID(for: slot),
           let doc = document(id: id),
           doc.family == slot.family {
            return doc
        }
        guard slot.index == 1 else { return nil }
        return allDocuments().first { $0.family == slot.family }
    }

    func setActiveDocument(_ id: UUID?, for slot: WidgetSlot) {
        guard let url = activeFileURL else { return }
        var map = assignments()
        // A document can only be in one slot of its size at a time; putting it
        // in a second would silently duplicate it on the desktop.
        if let id {
            for other in WidgetSlot.all(for: slot.family) where map[other.key] == id {
                map.removeValue(forKey: other.key)
            }
            map[slot.key] = id
        } else {
            map.removeValue(forKey: slot.key)
        }
        try? JSONEncoder().encode(map).write(to: url, options: .atomic)
    }

    /// Which slot holds this document, if any.
    func slot(holding id: UUID) -> WidgetSlot? {
        let map = assignments()
        return WidgetSlot.everything.first { map[$0.key] == id }
    }

    /// The first slot of a size with nothing in it, for "show this on the
    /// desktop" to choose without asking.
    func firstFreeSlot(for family: WidgetDoc.Family) -> WidgetSlot? {
        let map = assignments()
        return WidgetSlot.all(for: family).first { map[$0.key] == nil }
    }
}
