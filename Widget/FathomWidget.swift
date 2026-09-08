import AppIntents
import SwiftUI
import WidgetKit

// The universal widget extension.
//
// There is exactly one of these and it never changes when a user builds a new
// widget — it reads a document out of the shared store and interprets it. That
// is not a design preference; WidgetKit extensions are compiled SwiftUI and
// macOS will not load code at runtime, so a widget-per-user would need a
// compiler on the user's Mac and a signature it could never get.

struct DocumentEntry: TimelineEntry {
    let date: Date
    let doc: WidgetDoc?
    let data: ResolvedData
    var family: WidgetDoc.Family = .small
    /// Which provider callback produced this entry. WidgetKit will happily
    /// show a placeholder forever if the timeline never arrives, and the two
    /// states are indistinguishable on screen without this.
    var origin: String = "?"
    var diagnosis: StoreDiagnosis = StoreDiagnosis(urlResolves: false, readable: false,
                                                   writable: false, documentCount: 0,
                                                   familiesPresent: [], containerPath: "not checked")
}

/// One provider, generic over the four per-family configuration intents.
struct DocumentProvider<I: DocumentSelectingIntent>: AppIntentTimelineProvider {
    private var family: WidgetDoc.Family { I.family }

    func placeholder(in context: Context) -> DocumentEntry {
        let diagnosis = StoreDiagnosis.current()
        ExtensionTrace.write("placeholder family=\(family.rawValue) \(diagnosis.summary)")
        return DocumentEntry(date: Date(),
                             doc: DocumentCatalog.document(selected: nil, family: family),
                             data: ResolvedData(),
                             family: family,
                             origin: "placeholder",
                             diagnosis: diagnosis)
    }

    func snapshot(for configuration: I, in context: Context) async -> DocumentEntry {
        let diagnosis = StoreDiagnosis.current()
        let doc = DocumentCatalog.document(selected: configuration.selectedDocumentID, family: family)
        ExtensionTrace.write("snapshot family=\(family.rawValue) doc=\(doc?.name ?? "none") \(diagnosis.summary)")
        // The gallery snapshot must not wait on somebody's endpoint, so system
        // values only. A widget being previewed on a slow connection should
        // still show its layout instantly.
        return DocumentEntry(date: Date(),
                             doc: doc,
                             data: doc.map { Self.systemOnlyData($0) } ?? ResolvedData(),
                             family: family,
                             origin: "snapshot",
                             diagnosis: diagnosis)
    }

    func timeline(for configuration: I, in context: Context) async -> Timeline<DocumentEntry> {
        let now = Date()
        let diagnosis = StoreDiagnosis.current()
        let doc = DocumentCatalog.document(selected: configuration.selectedDocumentID, family: family)
        ExtensionTrace.write("timeline family=\(family.rawValue) doc=\(doc?.name ?? "none") \(diagnosis.summary)")

        guard let doc else {
            // Nothing designed for this family yet. Still schedule a reload,
            // otherwise placing a widget before building one leaves it blank
            // permanently rather than until the next tick.
            let entry = DocumentEntry(date: now, doc: nil, data: ResolvedData(),
                                      family: family, origin: "timeline", diagnosis: diagnosis)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(WidgetDoc.refreshFloor)))
        }

        let data = doc.sources.allSatisfy({ $0.kind == .system })
            ? Self.systemOnlyData(doc, now: now)          // no network, no waiting
            : await DataResolver.resolve(doc, now: now)

        trace(doc, data)
        let entry = DocumentEntry(date: now, doc: doc, data: data,
                                  family: family, origin: "timeline", diagnosis: diagnosis)

        // One entry per reload rather than a pre-computed run of them.
        // Pre-computing is the standard iOS workaround for a reload budget; on
        // macOS the floor is 64 seconds and does not decay, so asking again is
        // both allowed and more accurate than guessing the future.
        let next = now.addingTimeInterval(max(doc.minimumRefresh, WidgetDoc.refreshFloor))
        return Timeline(entries: [entry], policy: .after(next))
    }

    private static func systemOnlyData(_ doc: WidgetDoc, now: Date = Date()) -> ResolvedData {
        var data = ResolvedData(capturedAt: now)
        for source in doc.sources where source.kind == .system {
            data.trees[source.id] = SystemSource.snapshot(now: now)
        }
        return data
    }

    private func trace(_ doc: WidgetDoc, _ data: ResolvedData) {
        let rendered = doc.elements
            .filter { $0.binding != nil }
            .map { "\($0.displayName)=\(data.text(for: $0))" }
            .joined(separator: " ")
        ExtensionTrace.write("rendered family=\(family.rawValue) doc=\(doc.name) stale=\(data.isStale) [\(rendered)]")
    }
}

struct DocumentWidgetView: View {
    var entry: DocumentEntry

    var body: some View {
        Group {
            if let doc = entry.doc {
                WidgetCanvas(doc: doc, data: entry.data)
                    .fathomWidgetBackground(doc.background)
            } else {
                EmptyStateView(family: entry.family, diagnosis: entry.diagnosis, origin: entry.origin)
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

/// What a placed widget shows when it has nothing to draw — and, crucially,
/// why.
///
/// A widget extension has no console and no usable debugger (trap 4), and on
/// this machine the unified log returns nothing at all. So the widget face is
/// the diagnostic channel. "No widget yet" and "the shared store is denied to
/// this build's signature" are completely different problems that would
/// otherwise look identical from across the room.
struct EmptyStateView: View {
    let family: WidgetDoc.Family
    let diagnosis: StoreDiagnosis
    let origin: String

    private var brokenStorage: Bool { !diagnosis.usable }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: brokenStorage ? "exclamationmark.triangle.fill" : "square.dashed")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(brokenStorage ? .orange : Palette.accent)

            Text(brokenStorage ? "Shared storage unreachable" : "No \(family.displayName.lowercased()) widget yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(diagnosis.headline)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // The state of the store as the extension sees it. Small and dim:
            // readable when you go looking, ignorable when you are not.
            Text("\(origin) · \(diagnosis.summary)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Palette.textDim.opacity(0.65))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

// MARK: - Configurations

// One `Widget` per family. WidgetKit picks the configuration by the size the
// user placed, and each carries its own intent so the picker only offers
// designs authored for that size.

struct FathomSmallWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FathomSmall",
                               intent: SmallWidgetIntent.self,
                               provider: DocumentProvider<SmallWidgetIntent>()) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Small")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemSmall])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design by
        // a few points on each edge.
        .contentMarginsDisabled()
    }
}

struct FathomMediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FathomMedium",
                               intent: MediumWidgetIntent.self,
                               provider: DocumentProvider<MediumWidgetIntent>()) {
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
        AppIntentConfiguration(kind: "FathomLarge",
                               intent: LargeWidgetIntent.self,
                               provider: DocumentProvider<LargeWidgetIntent>()) {
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
        AppIntentConfiguration(kind: "FathomExtraLarge",
                               intent: ExtraLargeWidgetIntent.self,
                               provider: DocumentProvider<ExtraLargeWidgetIntent>()) {
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
