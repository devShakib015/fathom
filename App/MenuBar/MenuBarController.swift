import AppKit
import SwiftUI
import Observation

/// Puts documents in the menu bar and keeps them current.
///
/// The item's button carries a rendered image rather than a hosted SwiftUI
/// view. A status item is not a window: it is asked for its content at times
/// AppKit chooses, and an image it already has is always ready. A live view in
/// there is a source of flicker and of layout that arrives a frame late.
@MainActor
@Observable
final class MenuBarController {
    private(set) var items: [MenuBarItem] = []
    /// Whether Fathom keeps a Dock icon. A menu bar app that also sits in the
    /// Dock is two of the same thing; a menu bar app with no way back to its
    /// window is a trap. Hence a setting, defaulting to visible.
    var showsDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showsDockIcon, forKey: Self.dockKey)
            NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        }
    }

    private static let dockKey = "showsDockIcon"

    @ObservationIgnored private var statusItems: [UUID: NSStatusItem] = [:]
    @ObservationIgnored private var popovers: [UUID: NSPopover] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init() {
        items = MenuBarStore.shared.all()
        showsDockIcon = UserDefaults.standard.object(forKey: Self.dockKey) as? Bool ?? true
    }

    func start() {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        for item in items where item.isEnabled { install(item) }
    }

    // MARK: - Editing

    @discardableResult
    func add(for doc: WidgetDoc) -> MenuBarItem {
        let item = MenuBarItem(documentID: doc.id, width: doc.family == .menuBar
                               ? doc.family.referenceSize.width : 160)
        items.append(item)
        persist()
        install(item)
        return item
    }

    func update(_ item: MenuBarItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        persist()
        if item.isEnabled {
            remove(from: item.id)
            install(item)
        } else {
            remove(from: item.id)
        }
    }

    func delete(_ id: UUID) {
        remove(from: id)
        items.removeAll { $0.id == id }
        persist()
    }

    func deleteAll(forDocument documentID: UUID) {
        for item in items where item.documentID == documentID { remove(from: item.id) }
        items.removeAll { $0.documentID == documentID }
        MenuBarStore.shared.removeAll(forDocument: documentID)
        items = MenuBarStore.shared.all()
    }

    func items(for documentID: UUID) -> [MenuBarItem] {
        items.filter { $0.documentID == documentID }
    }

    func documentChanged(_ documentID: UUID) {
        for item in items where item.documentID == documentID && item.isEnabled {
            Task { await redraw(item) }
        }
    }

    private func persist() { MenuBarStore.shared.save(items) }

    // MARK: - Status items

    private func install(_ item: MenuBarItem) {
        let status = NSStatusBar.system.statusItem(withLength: item.width)
        status.button?.imagePosition = .imageOnly
        status.button?.target = self
        status.button?.action = #selector(clicked(_:))
        status.button?.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        statusItems[item.id] = status

        tasks[item.id]?.cancel()
        tasks[item.id] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.redraw(item)
                try? await Task.sleep(for: .seconds(max(item.refresh, MenuBarItem.refreshFloor)))
            }
        }
    }

    private func remove(from id: UUID) {
        tasks[id]?.cancel(); tasks[id] = nil
        popovers[id]?.performClose(nil); popovers[id] = nil
        if let status = statusItems[id] { NSStatusBar.system.removeStatusItem(status) }
        statusItems[id] = nil
    }

    private func redraw(_ item: MenuBarItem) async {
        guard let doc = DocumentStore.shared.document(id: item.documentID) else {
            delete(item.id)
            return
        }
        let data = await DataResolver.resolve(doc)
        guard let status = statusItems[item.id] else { return }

        let height = NSStatusBar.system.thickness
        let size = CGSize(width: item.width, height: height)
        status.length = item.width
        status.button?.image = render(doc, data: data, size: size)
        // Not a template image: the whole point is the design's own colours,
        // and a template would flatten every one of them to the menu bar's
        // foreground.
        status.button?.image?.isTemplate = false
    }

    private func render(_ doc: WidgetDoc, data: ResolvedData, size: CGSize) -> NSImage? {
        let view = ZStack {
            doc.background.swatch
            WidgetCanvas(doc: doc, data: data)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        // Rendered at the screen's scale so it is not soft on a Retina display,
        // then told its point size so AppKit lays it out correctly.
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.size = size
        return image
    }

    // MARK: - Clicking

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw),
              let item = items.first(where: { $0.id == id })
        else { return }

        guard let popoverID = item.popoverDocumentID,
              let doc = DocumentStore.shared.document(id: popoverID) else { return }

        if let existing = popovers[id], existing.isShown {
            existing.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = doc.family.referenceSize
        popover.contentViewController = NSHostingController(rootView: PopoverContent(doc: doc))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        popovers[id] = popover
    }
}

/// What a menu bar item shows when clicked. Resolved when it opens rather than
/// held live: a popover is looked at for a few seconds, not watched.
private struct PopoverContent: View {
    let doc: WidgetDoc
    @State private var data = ResolvedData()

    var body: some View {
        ZStack {
            doc.background.swatch
            WidgetCanvas(doc: doc, data: data)
        }
        .frame(width: doc.family.referenceSize.width, height: doc.family.referenceSize.height)
        .task { data = await DataResolver.resolve(doc) }
    }
}
