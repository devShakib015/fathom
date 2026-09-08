import SwiftUI
import WidgetKit
import os

// The universal widget extension.
//
// There is exactly one of these and it never changes when a user builds a new
// widget — it reads a document out of the shared container and interprets it.
// That is not a design preference; WidgetKit extensions are compiled SwiftUI
// and macOS will not load code at runtime, so a widget-per-user would need a
// compiler on the user's Mac and a signature it could never get.

struct DocumentEntry: TimelineEntry {
    let date: Date
    let doc: WidgetDoc?
    let data: ResolvedData
}

struct DocumentProvider: TimelineProvider {
    let family: WidgetDoc.Family

    /// Every reload leaves a line in the unified log. Not for debugging — it is
    /// how the cadence gets measured on a real desktop, because trap 4 says any
    /// timing taken under Xcode is fiction. Read it with:
    ///   log show --last 1h --predicate 'subsystem == "com.devshakib.fathom"'
    private static let log = Logger(subsystem: "com.devshakib.fathom", category: "timeline")

    func placeholder(in context: Context) -> DocumentEntry {
        let doc = DocumentStore.shared.activeDocument(for: family) ?? fallbackDocument
        return DocumentEntry(date: Date(), doc: doc, data: ResolvedData())
    }

    func getSnapshot(in context: Context, completion: @escaping (DocumentEntry) -> Void) {
        Task {
            let doc = DocumentStore.shared.activeDocument(for: family)
            // The gallery snapshot must not wait on somebody's endpoint, so
            // system values only. A widget being previewed at 3 KB/s should
            // still show its layout instantly.
            let data = doc.map { context.isPreview ? previewData(for: $0) : ResolvedData() } ?? ResolvedData()
            completion(DocumentEntry(date: Date(), doc: doc ?? fallbackDocument, data: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DocumentEntry>) -> Void) {
        Task {
            let now = Date()
            guard let doc = DocumentStore.shared.activeDocument(for: family) else {
                // Nothing designed for this family yet. Still schedule a
                // reload, otherwise placing a widget before building one
                // leaves it permanently blank.
                Self.log.notice("reload family=\(family.rawValue, privacy: .public) doc=none")
                let entry = DocumentEntry(date: now, doc: nil, data: ResolvedData())
                completion(Timeline(entries: [entry],
                                    policy: .after(now.addingTimeInterval(WidgetDoc.refreshFloor))))
                return
            }

            let data = await DataResolver.resolve(doc, now: now)
            let entry = DocumentEntry(date: now, doc: doc, data: data)

            let rendered = doc.elements
                .filter { $0.binding != nil }
                .map { "\($0.displayName)=\(data.text(for: $0))" }
                .joined(separator: " ")
            Self.log.notice("reload family=\(family.rawValue, privacy: .public) doc=\(doc.name, privacy: .public) elements=\(doc.elements.count) stale=\(data.isStale) values=[\(rendered, privacy: .public)]")

            // One entry per reload rather than a pre-computed run of them.
            // Pre-computing is the standard iOS workaround for a reload budget;
            // on macOS the floor is 64 seconds and does not decay, so asking
            // again is both allowed and more accurate than guessing the future.
            let next = now.addingTimeInterval(max(doc.minimumRefresh, WidgetDoc.refreshFloor))
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func previewData(for doc: WidgetDoc) -> ResolvedData {
        var data = ResolvedData(capturedAt: Date())
        for source in doc.sources where source.kind == .system {
            data.trees[source.id] = SystemSource.snapshot()
        }
        return data
    }

    private var fallbackDocument: WidgetDoc? { nil }
}

struct DocumentWidgetView: View {
    var entry: DocumentEntry

    var body: some View {
        Group {
            if let doc = entry.doc {
                WidgetCanvas(doc: doc, data: entry.data)
                    .fathomWidgetBackground(doc.background)
            } else {
                EmptyStateView()
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

/// What a placed widget shows before anything has been designed for its size.
/// Says which size is missing, because "open Fathom" on its own leaves the
/// user hunting for why their other widget worked and this one did not.
struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "square.dashed")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("No widget yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text("Design one in Fathom and it appears here.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }
}

// MARK: - Configurations

// One `Widget` per family. WidgetKit picks the configuration by the family the
// user placed, and each one loads the document assigned to that size.

struct FathomSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomSmall", provider: DocumentProvider(family: .small)) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Small")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemSmall])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design
        // by a few points on each edge.
        .contentMarginsDisabled()
    }
}

struct FathomMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomMedium", provider: DocumentProvider(family: .medium)) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Medium")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct FathomLargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomLarge", provider: DocumentProvider(family: .large)) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Large")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct FathomExtraLargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomExtraLarge", provider: DocumentProvider(family: .extraLarge)) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Extra large")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemExtraLarge])
        .contentMarginsDisabled()
    }
}

@main
struct FathomWidgetBundle: WidgetBundle {
    var body: some Widget {
        FathomSmallWidget()
        FathomMediumWidget()
        FathomLargeWidget()
        FathomExtraLargeWidget()
    }
}
