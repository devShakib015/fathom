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
    var slot: WidgetSlot = WidgetSlot(family: .small, index: 1)
    var family: WidgetDoc.Family { slot.family }
    /// Which provider callback produced this entry. WidgetKit will happily
    /// show a placeholder forever if the timeline never arrives, and the two
    /// states are indistinguishable on screen without this.
    var origin: String = "?"
    var diagnosis: StoreDiagnosis = StoreDiagnosis(urlResolves: false, readable: false,
                                                   writable: false, documentCount: 0,
                                                   familiesPresent: [], containerPath: "not checked")
}

/// One provider per slot.
struct DocumentProvider: TimelineProvider {
    let slot: WidgetSlot
    private var family: WidgetDoc.Family { slot.family }

    func placeholder(in context: Context) -> DocumentEntry {
        let diagnosis = StoreDiagnosis.current()
        ExtensionTrace.write("placeholder slot=\(slot.key) \(diagnosis.summary)")
        return DocumentEntry(date: Date(),
                             doc: DocumentCatalog.document(for: slot),
                             data: ResolvedData(),
                             slot: slot,
                             origin: "placeholder",
                             diagnosis: diagnosis)
    }

    func getSnapshot(in context: Context, completion: @escaping (DocumentEntry) -> Void) {
        let diagnosis = StoreDiagnosis.current()
        let doc = DocumentCatalog.document(for: slot)
        ExtensionTrace.write("snapshot slot=\(slot.key) doc=\(doc?.name ?? "none") \(diagnosis.summary)")
        // The gallery must not wait on somebody's endpoint, so system values
        // only, resolved synchronously.
        completion(DocumentEntry(date: Date(),
                                 doc: doc,
                                 data: doc.map { Self.systemOnlyData($0) } ?? ResolvedData(),
                                 slot: slot,
                                 origin: "snapshot",
                                 diagnosis: diagnosis))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DocumentEntry>) -> Void) {
        let now = Date()
        let diagnosis = StoreDiagnosis.current()
        let doc = DocumentCatalog.document(for: slot)
        ExtensionTrace.write("timeline slot=\(slot.key) doc=\(doc?.name ?? "none") \(diagnosis.summary)")

        func finish(_ entry: DocumentEntry, refresh: TimeInterval) {
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refresh))))
        }

        guard let doc else {
            finish(DocumentEntry(date: now, doc: nil, data: ResolvedData(),
                                 slot: slot, origin: "timeline", diagnosis: diagnosis),
                   refresh: WidgetDoc.refreshFloor)
            return
        }

        let refresh = max(doc.minimumRefresh, WidgetDoc.refreshFloor)

        // A document with no network source needs no concurrency, and going
        // async anyway would mean returning from `getTimeline` before calling
        // back — the one shape where WidgetKit can keep showing the placeholder
        // forever with nothing to say why.
        if doc.sources.allSatisfy({ $0.kind == .system }) {
            let data = Self.systemOnlyData(doc, now: now)
            trace(doc, data)
            finish(DocumentEntry(date: now, doc: doc, data: data,
                                 slot: slot, origin: "timeline", diagnosis: diagnosis),
                   refresh: refresh)
            return
        }

        Task {
            let data = await DataResolver.resolve(doc, now: now)
            trace(doc, data)
            // One entry per reload rather than a pre-computed run of them.
            // Pre-computing is the standard iOS workaround for a reload budget;
            // on macOS the floor is 64 seconds and does not decay, so asking
            // again is both allowed and more accurate than guessing the future.
            finish(DocumentEntry(date: now, doc: doc, data: data,
                                 slot: slot, origin: "timeline", diagnosis: diagnosis),
                   refresh: refresh)
        }
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
        ExtensionTrace.write("rendered slot=\(slot.key) doc=\(doc.name) stale=\(data.isStale) [\(rendered)]")
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
                EmptyStateView(slot: entry.slot, diagnosis: entry.diagnosis, origin: entry.origin)
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

/// What a placed widget shows when it has nothing to draw — and, crucially,
/// why.
///
/// A widget extension has no console and no usable debugger, and on
/// this machine the unified log returns nothing at all. So the widget face is
/// the diagnostic channel. "No widget yet" and "the shared store is denied to
/// this build's signature" are completely different problems that would
/// otherwise look identical from across the room.
struct EmptyStateView: View {
    let slot: WidgetSlot
    let diagnosis: StoreDiagnosis
    let origin: String

    private var brokenStorage: Bool { !diagnosis.usable }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: brokenStorage ? "exclamationmark.triangle.fill" : "square.dashed")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(brokenStorage ? .orange : Palette.accent)

            Text(brokenStorage
                 ? "Shared storage unreachable"
                 : slot.index == 1
                   ? "No \(slot.family.displayName.lowercased()) widget yet"
                   : "\(slot.displayName) is empty")
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
            Text("\(slot.key) · \(origin) · \(diagnosis.summary)")
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

// One `Widget` per slot. `StaticConfiguration` cannot be reconfigured once a
// widget is placed, so several designs at one size means several widget kinds —
// see `WidgetSlot`.
//
// Written out rather than generated from a generic `SlotWidget<Identity>`, which
// is what this was first. That version compiled and registered, and WidgetKit
// then never asked any of it for a timeline again — the same silence.
// The shape that demonstrably works is a concrete type with a literal `kind`,
// so that is the shape, ten times. Repetition that runs beats elegance that
// does not.

struct FathomSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomSmall",
                            provider: DocumentProvider(slot: WidgetSlot(family: .small, index: 1))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Small")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemSmall])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomSmall2Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomSmall2",
                            provider: DocumentProvider(slot: WidgetSlot(family: .small, index: 2))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Small 2")
        .description("Another Fathom design at this size. Assign one to it in the app.")
        .supportedFamilies([.systemSmall])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomSmall3Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomSmall3",
                            provider: DocumentProvider(slot: WidgetSlot(family: .small, index: 3))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Small 3")
        .description("Another Fathom design at this size. Assign one to it in the app.")
        .supportedFamilies([.systemSmall])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomSmall4Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomSmall4",
                            provider: DocumentProvider(slot: WidgetSlot(family: .small, index: 4))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Small 4")
        .description("Another Fathom design at this size. Assign one to it in the app.")
        .supportedFamilies([.systemSmall])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomMedium",
                            provider: DocumentProvider(slot: WidgetSlot(family: .medium, index: 1))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Medium")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemMedium])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomMedium2Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomMedium2",
                            provider: DocumentProvider(slot: WidgetSlot(family: .medium, index: 2))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Medium 2")
        .description("Another Fathom design at this size. Assign one to it in the app.")
        .supportedFamilies([.systemMedium])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomMedium3Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomMedium3",
                            provider: DocumentProvider(slot: WidgetSlot(family: .medium, index: 3))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Medium 3")
        .description("Another Fathom design at this size. Assign one to it in the app.")
        .supportedFamilies([.systemMedium])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomLargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomLarge",
                            provider: DocumentProvider(slot: WidgetSlot(family: .large, index: 1))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Large")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemLarge])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomLarge2Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomLarge2",
                            provider: DocumentProvider(slot: WidgetSlot(family: .large, index: 2))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Large 2")
        .description("Another Fathom design at this size. Assign one to it in the app.")
        .supportedFamilies([.systemLarge])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}
struct FathomExtraLargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FathomExtraLarge",
                            provider: DocumentProvider(slot: WidgetSlot(family: .extraLarge, index: 1))) {
            DocumentWidgetView(entry: $0)
        }
        .configurationDisplayName("Fathom — Extra large")
        .description("A widget you designed in Fathom.")
        .supportedFamilies([.systemExtraLarge])
        // Elements are positioned in unit space across the whole box, so the
        // system's default content margins would silently crop every design.
        .contentMarginsDisabled()
    }
}

@main
struct FathomWidgetBundle: WidgetBundle {
    // Split into groups because `WidgetBundleBuilder` tops out at ten.
    @WidgetBundleBuilder
    var body: some Widget {
        smallWidgets
        largerWidgets
    }

    @WidgetBundleBuilder
    var smallWidgets: some Widget {
        FathomSmallWidget()
        FathomSmall2Widget()
        FathomSmall3Widget()
        FathomSmall4Widget()
    }

    @WidgetBundleBuilder
    var largerWidgets: some Widget {
        FathomMediumWidget()
        FathomMedium2Widget()
        FathomMedium3Widget()
        FathomLargeWidget()
        FathomLarge2Widget()
        FathomExtraLargeWidget()
    }
}
