import SwiftUI
import WidgetKit

enum AboutWindow {
    static let id = "about"
}

/// Overlays are windows Fathom owns, so Fathom has to still be running for
/// them to exist. Closing the editor is not quitting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct FathomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = Library()
    @State private var overlays = OverlayController()
    @State private var rules = RuleEngine()
    @State private var menuBar = MenuBarController()
    @State private var island = IslandController()
    @State private var summon = SummonController()
    @Environment(\.openWindow) private var openWindow

    private func openAbout() { openWindow(id: AboutWindow.id) }

    var body: some Scene {
        Window("Fathom", id: "main") {
            RootView()
                .environment(library)
                .environment(overlays)
                .environment(rules)
                .environment(menuBar)
                .environment(island)
                .environment(summon)
                .task {
                    overlays.start()
                    menuBar.start()
                    island.start()
                    summon.start()
                    // Resumes only if permission was already given. Nothing is
                    // asked for here; see LocationService.request().
                    LocationService.shared.start()
                    // The extension cannot read the calendar; the app keeps its
                    // snapshot fresh so a desktop widget has something true.
                    CalendarKeeper.shared.start()
                    // The engine can put overlays on and off screen, so it
                    // needs to know who owns them.
                    rules.overlays = overlays
                    await rules.refreshNotificationPermission()
                    rules.start()
                }
                .frame(minWidth: 1080, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Replaces the stock About panel, which would show none of the
            // three things section 2 requires be said plainly.
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.name)") { openAbout() }
            }
            EditorCommands()
        }

        Window("About \(AppInfo.name)", id: AboutWindow.id) {
            AboutView()
                .environment(library)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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
            if let free = DocumentStore.shared.firstFreeSlot(for: starter.family) {
                DocumentStore.shared.setActiveDocument(starter.id, for: free)
            }
        }
    }

    // MARK: - Library management

    @discardableResult
    func create(family: WidgetDoc.Family) -> WidgetDoc {
        let doc = WidgetDoc(name: "Untitled", family: family, sources: [DataSource.system()])
        DocumentStore.shared.save(doc)
        reload()
        selection = doc.id
        return doc
    }

    /// Takes a document out of the catalog and makes it the user's own — a new
    /// identity, so the same entry can be added more than once and edited in
    /// different directions.
    func add(_ doc: WidgetDoc) {
        var copy = doc
        copy.id = UUID()
        DocumentStore.shared.save(copy)
        reload()
        selection = copy.id
        // Straight onto the desktop if there is room, because adding something
        // from the catalog and then hunting for how to show it is a step nobody
        // asked for.
        if let free = DocumentStore.shared.firstFreeSlot(for: copy.family) {
            DocumentStore.shared.setActiveDocument(copy.id, for: free)
            DocumentStore.shared.reloadWidgets()
        }
    }

    func duplicate(_ doc: WidgetDoc) {
        var copy = doc
        copy.id = UUID()
        copy.name = "\(doc.name) copy"
        DocumentStore.shared.save(copy)
        reload()
        selection = copy.id
    }

    func delete(_ doc: WidgetDoc) {
        // Overlays showing a deleted document would be windows nothing can
        // fill, so they go with it.
        OverlayStore.shared.removeAll(forDocument: doc.id)
        MenuBarStore.shared.removeAll(forDocument: doc.id)
        IslandStore.shared.clearIfUses(doc.id)
        SummonStore.shared.clearIfUses(doc.id)
        if let slot = DocumentStore.shared.slot(holding: doc.id) {
            DocumentStore.shared.setActiveDocument(nil, for: slot)
        }
        DocumentStore.shared.delete(id: doc.id)
        reload()
        DocumentStore.shared.reloadWidgets()
    }

    /// Puts a document in a slot. With no slot named, the one it already
    /// occupies, or the first free one of its size.
    func makeActive(_ doc: WidgetDoc, slot: WidgetSlot? = nil) {
        let target = slot
            ?? DocumentStore.shared.slot(holding: doc.id)
            ?? DocumentStore.shared.firstFreeSlot(for: doc.family)
            ?? WidgetSlot(family: doc.family, index: 1)
        DocumentStore.shared.setActiveDocument(doc.id, for: target)
        reload()
        DocumentStore.shared.reloadWidgets()
    }

    func remove(_ doc: WidgetDoc) {
        guard let slot = DocumentStore.shared.slot(holding: doc.id) else { return }
        DocumentStore.shared.setActiveDocument(nil, for: slot)
        reload()
        DocumentStore.shared.reloadWidgets()
    }

    func slot(holding doc: WidgetDoc) -> WidgetSlot? {
        DocumentStore.shared.slot(holding: doc.id)
    }

    /// What is in each slot of a size, for the assignment menu.
    func occupant(of slot: WidgetSlot) -> WidgetDoc? {
        DocumentStore.shared.activeDocumentID(for: slot).flatMap { id in
            documents.first { $0.id == id }
        }
    }
}
