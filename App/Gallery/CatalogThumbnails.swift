import SwiftUI

/// Renders catalog entries to pictures, on demand.
///
/// Rendering every entry up front would mean composing and rasterising a
/// thousand documents to show twelve. Cells ask for their own thumbnail as they
/// scroll into view, results are kept in memory for the session and on disk
/// between them, and nothing is ever rendered that nobody looked at.
///
/// Thumbnails resolve system values but never fetch anything: a gallery that
/// made a thousand network requests while you scrolled would be indefensible in
/// an app that promises no traffic you did not ask for. Entries bound to an
/// endpoint show their design-time literals, which is what those literals are
/// for.
@MainActor
@Observable
final class CatalogThumbnails {
    static let shared = CatalogThumbnails()

    private var memory: [String: Data] = [:]
    private var inFlight: Set<String> = []

    private var directory: URL? { SharedStore.directory("Catalog") }

    func thumbnail(for entry: CatalogEntry) -> Data? {
        if let cached = memory[entry.id] { return cached }
        if let onDisk = try? Data(contentsOf: file(entry.id)) {
            memory[entry.id] = onDisk
            return onDisk
        }
        return nil
    }

    /// Kicks off a render if one is not already running or cached.
    func request(_ entry: CatalogEntry) {
        guard memory[entry.id] == nil, !inFlight.contains(entry.id) else { return }
        if (try? Data(contentsOf: file(entry.id))) != nil { _ = thumbnail(for: entry); return }
        inFlight.insert(entry.id)

        Task { @MainActor in
            defer { inFlight.remove(entry.id) }
            let data = await render(entry)
            guard let data else { return }
            memory[entry.id] = data
            try? data.write(to: file(entry.id), options: .atomic)
        }
    }

    private func render(_ entry: CatalogEntry) async -> Data? {
        // No sources are resolved at all: no kernel reads, no network, nothing
        // that could differ between two runs. Every binding falls through to
        // the element's design-time literal, which is what a catalog should be
        // showing anyway — the layout, not this machine's current numbers.
        let data = ResolvedData(placeholders: true)
        return PreviewExporter.png(for: entry.document(), data: data, scale: 1)
    }

    private func file(_ id: String) -> URL {
        (directory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("\(id).png")
    }
}
