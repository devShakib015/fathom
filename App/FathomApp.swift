import SwiftUI
import WidgetKit

@main
struct FathomApp: App {
    @State private var library = Library()

    var body: some Scene {
        Window("Fathom", id: "main") {
            RootView()
                .environment(library)
                .frame(minWidth: 900, minHeight: 580)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// The app's view of what is in the shared container.
///
/// Deliberately not a database. The container is the truth, the extension
/// re-reads it on every reload, and this type just keeps the UI in step with
/// it — so there is no state that can be right in the app and wrong on the
/// desktop.
@Observable
final class Library {
    private(set) var documents: [WidgetDoc] = []
    private(set) var containerPath: String = SharedStore.diagnosis
    var selection: UUID?

    init() {
        seedIfEmpty()
        reload()
    }

    /// Refresh every document's thumbnail once at launch, so the library grid
    /// and any external check see current values rather than whatever was last
    /// selected in the window.
    @MainActor
    func exportAllPreviews() async {
        for doc in documents + [Starters.smokeTest] {
            let data = await DataResolver.resolve(doc)
            PreviewExporter.write(doc, data: data)
        }
    }

    func reload() {
        documents = DocumentStore.shared.allDocuments()
        containerPath = SharedStore.diagnosis
        if selection == nil || !documents.contains(where: { $0.id == selection }) {
            selection = documents.first?.id
        }
    }

    var selected: WidgetDoc? {
        documents.first { $0.id == selection }
    }

    /// Writes the shipped starters on first run. Ids are stable, so this
    /// refreshes them in place on upgrade rather than piling up copies —
    /// but it only ever runs when the family has nothing assigned, so a user
    /// who edited a starter keeps their edit.
    private func seedIfEmpty() {
        let existing = Set(DocumentStore.shared.allDocuments().map(\.id))
        for starter in Starters.all where !existing.contains(starter.id) {
            DocumentStore.shared.save(starter)
            if DocumentStore.shared.activeDocumentID(for: starter.family) == nil {
                DocumentStore.shared.setActiveDocument(starter.id, for: starter.family)
            }
        }
    }

    func makeActive(_ doc: WidgetDoc) {
        DocumentStore.shared.setActiveDocument(doc.id, for: doc.family)
        DocumentStore.shared.reloadWidgets()
    }

    func activeID(for family: WidgetDoc.Family) -> UUID? {
        DocumentStore.shared.activeDocumentID(for: family)
    }
}
