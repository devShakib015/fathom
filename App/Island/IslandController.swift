import AppKit
import SwiftUI
import Observation

/// Hangs a document under the notch.
///
/// The placement is measured, not assumed. `NSScreen.safeAreaInsets.top` is the
/// notch on a Mac that has one and zero on a Mac that does not, so the island
/// sits flush under the menu bar on both without a special case — which is what
/// you want, since an external display has no notch and the island should still
/// look deliberate there.
@MainActor
@Observable
final class IslandController {
    private(set) var island: Island?
    private(set) var isExpanded = false

    @ObservationIgnored private var window: IslandWindow?
    @ObservationIgnored private var model: IslandModel?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var collapse: Task<Void, Never>?

    init() {
        island = IslandStore.shared.load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
    }

    func start() { if island?.isEnabled == true { show() } }

    // MARK: - Editing

    func set(_ island: Island?) {
        self.island = island
        IslandStore.shared.save(island)
        teardown()
        if island?.isEnabled == true { show() }
    }

    func use(_ doc: WidgetDoc) {
        set(Island(documentID: doc.id))
    }

    func clear() { set(nil) }

    func documentChanged(_ documentID: UUID) {
        guard let island, island.documentID == documentID || island.expandedDocumentID == documentID
        else { return }
        Task { await refresh() }
    }

    // MARK: - Window

    private func show() {
        guard let island,
              let doc = DocumentStore.shared.document(id: island.documentID) else { return }

        let model = IslandModel(doc: doc)
        model.onHover = { [weak self] hovering in self?.hover(hovering) }
        self.model = model

        let hosting = NSHostingView(rootView: IslandContent(model: model))
        let window = IslandWindow(content: hosting)
        self.window = window
        reposition()
        window.orderFront(nil)

        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(max(island.refresh, Island.refreshFloor)))
            }
        }
    }

    private func teardown() {
        task?.cancel(); task = nil
        collapse?.cancel(); collapse = nil
        window?.orderOut(nil); window = nil
        model = nil
        isExpanded = false
    }

    private func hover(_ hovering: Bool) {
        guard let island, island.expandOnHover, island.expandedDocumentID != nil else { return }
        collapse?.cancel()
        if hovering {
            guard !isExpanded else { return }
            isExpanded = true
            Task { await refresh() }
            reposition(animated: true)
        } else {
            // A short grace period. Resizing the window under the pointer can
            // briefly put the cursor outside it, and collapsing instantly on
            // that would make the island flicker rather than expand.
            collapse = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.isExpanded else { return }
                    self.isExpanded = false
                    Task { await self.refresh() }
                    self.reposition(animated: true)
                }
            }
        }
    }

    private func currentDocument() -> WidgetDoc? {
        guard let island else { return nil }
        if isExpanded, let id = island.expandedDocumentID {
            return DocumentStore.shared.document(id: id)
        }
        return DocumentStore.shared.document(id: island.documentID)
    }

    private func reposition(animated: Bool = false) {
        guard let island, let window, let doc = currentDocument() else { return }
        let screens = NSScreen.screens
        let screen = screens.indices.contains(island.screenIndex)
            ? screens[island.screenIndex] : (NSScreen.main ?? screens.first)
        guard let screen else { return }

        let size = doc.family.referenceSize
        // The safe area is the notch where there is one and zero where there is
        // not; the status bar height covers the second case.
        let inset = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let top = screen.frame.maxY - inset - island.topGap
        let frame = CGRect(x: screen.frame.midX - size.width / 2,
                           y: top - size.height,
                           width: size.width, height: size.height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func refresh() async {
        guard let doc = currentDocument() else { teardown(); return }
        let data = await DataResolver.resolve(doc)
        model?.doc = doc
        model?.data = data
    }
}

/// The island's window. Floating and non-activating, like an overlay, but never
/// draggable — its whole identity is being in one place.
final class IslandWindow: NSPanel {
    init(content: NSView) {
        super.init(contentRect: content.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
final class IslandModel {
    var doc: WidgetDoc
    var data = ResolvedData()
    @ObservationIgnored var onHover: ((Bool) -> Void)?
    init(doc: WidgetDoc) { self.doc = doc }
}

private struct IslandContent: View {
    @Bindable var model: IslandModel

    var body: some View {
        ZStack {
            model.doc.background.swatch
            WidgetCanvas(doc: model.doc, data: model.data)
        }
        // Fully rounded rather than the widget corner radius: an island reads
        // as a capsule hanging from the notch, not as a small widget.
        .clipShape(RoundedRectangle(cornerRadius: min(model.doc.family.referenceSize.height / 2, 22),
                                    style: .continuous))
        .onHover { model.onHover?($0) }
    }
}
