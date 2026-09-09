import AppKit
import Carbon.HIToolbox
import SwiftUI
import Observation

/// Owns the summoned panel: the hotkey, the window, and the rule that it goes
/// away.
@MainActor
@Observable
final class SummonController {
    private(set) var summon: Summon?
    private(set) var isVisible = false
    /// Set when macOS refused the combination, which nearly always means
    /// another app already owns it. Surfaced rather than swallowed.
    private(set) var registrationFailed = false

    @ObservationIgnored private var window: SummonWindow?
    @ObservationIgnored private var model: SummonModel?
    @ObservationIgnored private let monitor = HotKeyMonitor()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var blurWatcher: Any?
    @ObservationIgnored private var escapeMonitor: Any?

    init() {
        summon = SummonStore.shared.load()
    }

    func start() { if summon?.isEnabled == true { arm() } }

    // MARK: - Editing

    func set(_ summon: Summon?) {
        self.summon = summon
        SummonStore.shared.save(summon)
        hide()
        monitor.unregister()
        registrationFailed = false
        if summon?.isEnabled == true { arm() }
    }

    func use(_ doc: WidgetDoc) { set(Summon(documentID: doc.id)) }

    func clear() { set(nil) }

    func documentChanged(_ documentID: UUID) {
        guard summon?.documentID == documentID, isVisible else { return }
        Task { await refresh() }
    }

    private func arm() {
        guard let summon else { return }
        registrationFailed = !monitor.register(summon.hotKey) { [weak self] in
            self?.toggle()
        }
    }

    // MARK: - Showing

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard let summon,
              let doc = DocumentStore.shared.document(id: summon.documentID),
              let screen = pointerScreen() else { return }

        let model = SummonModel(doc: doc, dims: summon.dimsBackground)
        model.onDismiss = { [weak self] in self?.hide() }
        self.model = model

        let size = CGSize(width: doc.family.referenceSize.width * summon.scale,
                          height: doc.family.referenceSize.height * summon.scale)
        let window = SummonWindow(content: NSHostingView(rootView: SummonContent(model: model)))
        window.setFrame(frame(size: size, on: screen, placement: summon.placement), display: false)
        self.window = window

        window.onEscape = { [weak self] in self?.hide() }
        window.alphaValue = 0
        // Key, so Escape reaches it. A panel you summoned with a key that then
        // ignores keys is a confusing object.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        isVisible = true
        Task { await refresh() }

        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(summon.refresh, Summon.refreshFloor)))
                await self?.refresh()
            }
        }

        // Escape, by local monitor rather than by responder chain.
        //
        // A borderless NSPanel does not reliably become key, so
        // `cancelOperation` and SwiftUI's `onExitCommand` both go unreached —
        // measured: the panel opened, Escape did nothing, and the hotkey toggle
        // worked the whole time, which is what made it look like a key handling
        // problem rather than a focus one. A local monitor sees the app's own
        // key events whichever of its windows has focus, and asks for no
        // permission at all.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            self?.hide()
            return nil
        }

        if summon.dismissOnBlur {
            blurWatcher = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.hide() }
                }
        }
    }

    func hide() {
        // Refreshing stops the moment it leaves the screen. A panel nobody is
        // looking at should cost exactly nothing — this is the one host that
        // can make that promise, because it is the one that is usually away.
        task?.cancel(); task = nil
        if let blurWatcher { NotificationCenter.default.removeObserver(blurWatcher) }
        blurWatcher = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil

        guard let window else { isVisible = false; return }
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.window = nil
            self?.model = nil
        }
    }

    // MARK: - Placement

    /// The display the pointer is on, not the main one.
    ///
    /// A panel summoned by a keystroke has to appear where the person's
    /// attention already is. On a multi-display Mac the pointer is the only
    /// honest evidence of that; `NSScreen.main` is wherever the menu bar
    /// happens to be.
    private func pointerScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func frame(size: CGSize, on screen: NSScreen,
                       placement: Summon.Placement) -> CGRect {
        let visible = screen.visibleFrame
        let origin: CGPoint
        switch placement {
        case .centre:
            // Slightly above true centre. Optical centre sits higher than
            // geometric centre, and a panel placed at exactly half the height
            // reads as sagging.
            origin = CGPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2 + visible.height * 0.06)
        case .underCursor:
            let point = NSEvent.mouseLocation
            origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height - 12)
        case .topRight:
            origin = CGPoint(x: visible.maxX - size.width - 20,
                             y: visible.maxY - size.height - 20)
        }
        // Never off screen, whatever the placement worked out to.
        return CGRect(origin: CGPoint(
            x: min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)),
                      size: size)
    }

    private func refresh() async {
        guard let summon,
              let doc = DocumentStore.shared.document(id: summon.documentID) else { hide(); return }
        let data = await DataResolver.resolve(doc)
        model?.doc = doc
        model?.data = data
    }
}

/// The panel. Key-capable, unlike every other window Fathom owns.
final class SummonWindow: NSPanel {
    init(content: NSView) {
        // Borderless, but NOT `.nonactivatingPanel`.
        //
        // That flag is for palettes that must never steal focus, and it is the
        // wrong choice here on purpose: a panel you summoned with a keystroke
        // should take the keyboard, and dismiss-on-blur is defined in terms of
        // resigning key, which a window that never becomes key cannot do.
        //
        // Confirmed with the panel open: `isKeyWindow` true, `NSApp.isActive`
        // true, and a real Escape reaching the local monitor as key code 53.
        super.init(contentRect: content.frame,
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isMovableByWindowBackground = true
        contentView = content
    }

    // Unlike the overlay, menu bar and island windows, this one takes the
    // keyboard: Escape has to dismiss it, and a panel you summoned with a key
    // that then ignores keys is a confusing object.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape, from anywhere in the panel.
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
@Observable
final class SummonModel {
    var doc: WidgetDoc
    var data = ResolvedData()
    var dims: Bool
    @ObservationIgnored var onDismiss: (() -> Void)?
    init(doc: WidgetDoc, dims: Bool) { self.doc = doc; self.dims = dims }
}

private struct SummonContent: View {
    @Bindable var model: SummonModel

    var body: some View {
        ZStack {
            model.doc.background.swatch
            WidgetCanvas(doc: model.doc, data: model.data)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onExitCommand { model.onDismiss?() }
    }
}


