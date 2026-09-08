import AppKit
import SwiftUI
import Observation

/// Owns every overlay window: creating them, feeding them data, and putting
/// them back where they were after a restart.
///
/// One controller, one timer per overlay. Refresh intervals are the overlay's
/// own, because nothing here goes through WidgetKit — the sixty-four second
/// floor is a fact about that framework and stops at this boundary.
@MainActor
@Observable
final class OverlayController {
    private(set) var overlays: [Overlay] = []

    @ObservationIgnored private var windows: [UUID: OverlayWindow] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var models: [UUID: OverlayModel] = [:]

    init() {
        overlays = OverlayStore.shared.all()
        // A display arriving or leaving moves everything; overlays are stored
        // as fractions precisely so they can be put back sensibly.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
    }

    func start() {
        for overlay in overlays where overlay.isEnabled { show(overlay) }
    }

    // MARK: - Lifecycle

    func add(for doc: WidgetDoc) -> Overlay {
        let overlay = Overlay(documentID: doc.id, size: doc.family.referenceSize)
        overlays.append(overlay)
        OverlayStore.shared.upsert(overlay)
        show(overlay)
        return overlay
    }

    func update(_ overlay: Overlay) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        overlays[index] = overlay
        OverlayStore.shared.upsert(overlay)

        if overlay.isEnabled {
            if let window = windows[overlay.id] {
                window.apply(overlay)
                window.setFrame(OverlayPlacement.frame(for: overlay), display: true)
                restartRefresh(for: overlay)
            } else {
                show(overlay)
            }
        } else {
            hide(overlay.id)
        }
    }

    func remove(_ id: UUID) {
        hide(id)
        overlays.removeAll { $0.id == id }
        OverlayStore.shared.remove(id)
    }

    func removeAll(forDocument documentID: UUID) {
        for overlay in overlays where overlay.documentID == documentID { hide(overlay.id) }
        overlays.removeAll { $0.documentID == documentID }
        OverlayStore.shared.removeAll(forDocument: documentID)
    }

    func overlays(for documentID: UUID) -> [Overlay] {
        overlays.filter { $0.documentID == documentID }
    }

    /// Redraws every overlay showing a document that has just been edited, so
    /// the canvas and the desktop never disagree.
    func documentChanged(_ documentID: UUID) {
        for overlay in overlays(for: documentID) where overlay.isEnabled {
            Task { await refresh(overlay) }
        }
    }

    // MARK: - Windows

    private func show(_ overlay: Overlay) {
        guard let doc = DocumentStore.shared.document(id: overlay.documentID) else { return }

        let model = models[overlay.id] ?? OverlayModel(doc: doc)
        model.doc = doc
        models[overlay.id] = model

        let hosting = NSHostingView(rootView: OverlayContent(model: model))
        hosting.frame = CGRect(origin: .zero, size: overlay.size)

        let window = windows[overlay.id] ?? OverlayWindow(overlay: overlay, content: hosting)
        window.contentView = hosting
        window.apply(overlay)
        window.setFrame(OverlayPlacement.frame(for: overlay), display: true)
        window.onMoved = { [weak self] frame in
            Task { @MainActor in self?.moved(overlay.id, to: frame) }
        }
        window.orderFront(nil)
        windows[overlay.id] = window

        restartRefresh(for: overlay)
    }

    private func hide(_ id: UUID) {
        tasks[id]?.cancel(); tasks[id] = nil
        windows[id]?.orderOut(nil)
        windows[id] = nil
        models[id] = nil
    }

    private func reposition() {
        for overlay in overlays where overlay.isEnabled {
            windows[overlay.id]?.setFrame(OverlayPlacement.frame(for: overlay), display: true)
        }
    }

    private func moved(_ id: UUID, to frame: CGRect) {
        guard var overlay = overlays.first(where: { $0.id == id }) else { return }
        OverlayPlacement.store(frame, into: &overlay)
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        overlays[index] = overlay
        OverlayStore.shared.upsert(overlay)
    }

    // MARK: - Data

    private func restartRefresh(for overlay: Overlay) {
        tasks[overlay.id]?.cancel()
        tasks[overlay.id] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(overlay)
                try? await Task.sleep(for: .seconds(max(overlay.refresh, Overlay.refreshFloor)))
            }
        }
    }

    private func refresh(_ overlay: Overlay) async {
        guard let doc = DocumentStore.shared.document(id: overlay.documentID) else {
            remove(overlay.id)
            return
        }
        let data = await DataResolver.resolve(doc)
        models[overlay.id]?.doc = doc
        models[overlay.id]?.data = data
    }
}

/// What one overlay window is currently drawing.
@MainActor
@Observable
final class OverlayModel {
    var doc: WidgetDoc
    var data = ResolvedData()
    init(doc: WidgetDoc) { self.doc = doc }
}

/// The overlay's contents: the same interpreter the widget extension runs.
///
/// Not a second renderer, and not an approximation of one. An overlay and a
/// widget built from the same document have to look identical, or the document
/// stops being the single description of a design.
private struct OverlayContent: View {
    @Bindable var model: OverlayModel

    var body: some View {
        ZStack {
            model.doc.background.swatch
            WidgetCanvas(doc: model.doc, data: model.data)
        }
        .clipShape(RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius, style: .continuous))
    }
}
