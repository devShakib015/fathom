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
    private(set) var state: State = .hidden

    @ObservationIgnored private var window: IslandWindow?
    @ObservationIgnored private var model: IslandModel?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var tracking: Task<Void, Never>?
    /// When the pointer first left, for the grace period before hiding.
    @ObservationIgnored private var leaveAt: Date?

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
        self.model = model

        let hosting = NSHostingView(rootView: IslandContent(model: model))
        let window = IslandWindow(content: hosting)
        self.window = window

        // Hidden to begin with when it reveals on approach, so it does not
        // flash onto the screen at launch before the pointer has gone anywhere
        // near the notch.
        state = island.reveal == .always ? .compact : .hidden
        apply(animated: false)
        if state != .hidden { window.orderFront(nil) }

        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(max(island.refresh, Island.refreshFloor)))
            }
        }
        startTracking()
    }

    private func teardown() {
        task?.cancel(); task = nil
        tracking?.cancel(); tracking = nil
        window?.orderOut(nil); window = nil
        model = nil
        state = .hidden
    }

    // MARK: - Following the pointer

    /// The island's whole behaviour, driven by one source of truth.
    ///
    /// Pointer position is polled rather than watched with a global event
    /// monitor: monitoring mouse events globally is the kind of thing that
    /// needs Accessibility on some systems, and an app that asks for that to
    /// draw a clock has misjudged what it is worth. `NSEvent.mouseLocation` is
    /// a plain read and needs nothing.
    enum State { case hidden, compact, expanded }

    private func startTracking() {
        tracking?.cancel()
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.followPointer() }
                // Thirty times a second. One coordinate read, and the latency
                // has to be below what reads as a delay when you flick the
                // pointer to the top of the screen.
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func followPointer() {
        guard let island, island.isEnabled, window != nil else { return }

        let wanted: State
        if island.reveal == .always {
            wanted = isOverIsland() && canExpand ? .expanded : .compact
        } else if isOverIsland() {
            wanted = canExpand ? .expanded : .compact
        } else if isNearNotch() {
            wanted = .compact
        } else {
            wanted = .hidden
        }

        guard wanted != state else { leaveAt = nil; return }

        // Leaving waits; arriving does not. Resizing a window under the pointer
        // can briefly put the cursor outside it, and reacting to that instantly
        // makes the island flicker rather than open.
        if wanted == .hidden || (state == .expanded && wanted == .compact) {
            let now = Date()
            if leaveAt == nil { leaveAt = now; return }
            guard now.timeIntervalSince(leaveAt!) > 0.25 else { return }
        }
        leaveAt = nil
        state = wanted
        Task { await refresh() }
        apply(animated: true)
    }

    private var canExpand: Bool {
        guard let island else { return false }
        return island.expandOnHover && island.expandedDocumentID != nil
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard let island else { return NSScreen.main }
        return screens.indices.contains(island.screenIndex)
            ? screens[island.screenIndex] : (NSScreen.main ?? screens.first)
    }

    private func isOverIsland() -> Bool {
        guard state != .hidden, let frame = window?.frame else { return false }
        return frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    /// The patch of screen that summons it: the notch and a little around it.
    ///
    /// Generous horizontally so a quick flick upward finds it, and shallow
    /// vertically so crossing the top of the screen on the way somewhere else
    /// does not.
    private func isNearNotch() -> Bool {
        guard let screen = targetScreen(), let island else { return false }
        let width = max(compactSize().width, 200) + 120
        let depth = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + island.topGap + 12
        let zone = CGRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.maxY - depth,
                          width: width, height: depth)
        return zone.contains(NSEvent.mouseLocation)
    }

    private func compactSize() -> CGSize {
        guard let island,
              let doc = DocumentStore.shared.document(id: island.documentID)
        else { return CGSize(width: 240, height: 34) }
        return doc.family.referenceSize
    }

    // MARK: - Placement

    private func currentDocument() -> WidgetDoc? {
        guard let island else { return nil }
        if state == .expanded, let id = island.expandedDocumentID {
            return DocumentStore.shared.document(id: id)
        }
        return DocumentStore.shared.document(id: island.documentID)
    }

    private func frame(for size: CGSize, hidden: Bool) -> CGRect? {
        guard let island, let screen = targetScreen() else { return nil }
        // The safe area is the notch where there is one and zero where there is
        // not; the status bar height covers the second case, so a notched
        // laptop and an external display both land correctly.
        let inset = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let top = screen.frame.maxY - inset - island.topGap
        // Hidden means tucked up behind the menu bar, so revealing is a slide
        // out from under it rather than something appearing from nowhere.
        let y = hidden ? screen.frame.maxY - size.height * 0.2 : top - size.height
        return CGRect(x: screen.frame.midX - size.width / 2, y: y,
                      width: size.width, height: size.height)
    }

    private func apply(animated: Bool) {
        guard let window, let doc = currentDocument() else { return }
        let size = doc.family.referenceSize
        guard let target = frame(for: size, hidden: state == .hidden) else { return }

        if state == .hidden {
            guard animated else { window.orderOut(nil); return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(target, display: true)
                window.animator().alphaValue = 0
            } completionHandler: { [weak window] in
                if self.state == .hidden { window?.orderOut(nil) }
            }
            return
        }

        if !window.isVisible {
            // Start tucked away so the reveal is a movement, not a pop.
            if let from = frame(for: size, hidden: true) { window.setFrame(from, display: false) }
            window.alphaValue = 0
            window.orderFront(nil)
        }
        guard animated else {
            window.setFrame(target, display: true); window.alphaValue = 1; return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }
    }

    private func reposition() { apply(animated: false) }

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
    }
}
