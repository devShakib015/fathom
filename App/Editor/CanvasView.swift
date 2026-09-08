import SwiftUI

/// The editing surface.
///
/// The document itself is drawn by `WidgetCanvas` — the same interpreter the
/// widget extension runs — with selection chrome layered on top. There is
/// deliberately no second rendering path: a canvas that draws its own
/// approximation of an element is a canvas that will eventually disagree with
/// the desktop, and then the preview is worse than useless.
struct CanvasView: View {
    @Bindable var model: EditorModel

    /// Points per unit of document space, chosen to fit the available room.
    @State private var zoom: Double = 2
    @State private var dragOrigin: [UUID: Frame] = [:]

    private var canvasSize: CGSize {
        let reference = model.doc.family.referenceSize
        return CGSize(width: reference.width * zoom, height: reference.height * zoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Palette.hairline)
            surface
        }
        .background(Palette.background)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(model.doc.family.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textDim)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Palette.surface, in: Capsule())

            Toggle(isOn: $model.snapEnabled) {
                Label("Snap", systemImage: "grid")
            }
            .toggleStyle(.button)
            .controlSize(.small)

            Spacer()

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")

            Divider().frame(height: 16)

            Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= 1)
            Text("\(Int(zoom * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textDim)
                .frame(width: 42)
            Button { zoom = min(4, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom >= 4)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Surface

    private var surface: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.deselect() }

                widget
                    .padding(60)
            }
            .frame(minWidth: canvasSize.width + 120, minHeight: canvasSize.height + 120)
        }
        .background(
            LinearGradient(colors: [Palette.surface.opacity(0.55), Palette.background],
                           startPoint: .top, endPoint: .bottom))
    }

    private var widget: some View {
        ZStack(alignment: .topLeading) {
            model.doc.background.swatch
            WidgetCanvas(doc: model.doc, data: model.data)
            if model.snapEnabled { grid }
            chrome
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius * zoom, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius * zoom, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 26, y: 12)
    }

    private var grid: some View {
        Canvas { context, size in
            let step = size.width / Double(model.gridDivisions)
            var path = Path()
            var x = step
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            let vStep = size.height / Double(model.gridDivisions)
            var y = vStep
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += vStep }
            context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Selection chrome

    /// Hit targets and outlines, in their own explicitly sized layer.
    ///
    /// `.position` rather than `.offset`: an offset child does not contribute
    /// its displaced bounds to the parent's layout, so the handles rendered in
    /// the right place while the parent stayed the size of one element and
    /// every click fell through to the text underneath.
    private var chrome: some View {
        ZStack(alignment: .topLeading) {
            // Clicking the widget anywhere that is not an element clears the
            // selection, which is what every canvas does.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.deselect() }

            ForEach(model.doc.elements) { element in
                let rect = element.frame.resolved(in: canvasSize)
                ElementHandle(element: element,
                              rect: rect,
                              isSelected: model.selection.contains(element.id),
                              model: model,
                              canvasSize: canvasSize,
                              dragOrigin: $dragOrigin)
                    .frame(width: max(rect.width, 10), height: max(rect.height, 10))
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

/// Hit target, selection outline and resize handles for one element.
///
/// Fills the frame it is given — the parent positions it — so nothing here
/// needs to know where on the canvas it sits except when converting a drag
/// back into unit space.
private struct ElementHandle: View {
    let element: Element
    let rect: CGRect
    let isSelected: Bool
    @Bindable var model: EditorModel
    let canvasSize: CGSize
    @Binding var dragOrigin: [UUID: Frame]

    private let handleSize: CGFloat = 9
    /// Whether the current press has travelled far enough to be a move. A
    /// press that never does is a click.
    @State private var isMoving = false
    @State private var isDropTarget = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .overlay(
                Rectangle().stroke(isSelected ? Palette.accent : .clear, lineWidth: 1.5)
            )
            // Handles sit on the corners, half outside the frame, so they are
            // grabbable even when an element is only a few points tall.
            .overlay(alignment: .topLeading) { handle(.topLeading) }
            .overlay(alignment: .topTrailing) { handle(.topTrailing) }
            .overlay(alignment: .bottomLeading) { handle(.bottomLeading) }
            .overlay(alignment: .bottomTrailing) { handle(.bottomTrailing) }
            .gesture(pressGesture)
            // A field dragged out of the tree browser can be dropped straight
            // onto the element it should feed, which is the shortest path from
            // "what does this endpoint return" to "my widget shows it".
            .dropDestination(for: String.self) { paths, _ in
                guard let keyPath = paths.first,
                      let source = model.doc.sources.first(where: { $0.kind == .json }),
                      let value = model.data.trees[source.id]?[path: keyPath]
                else { return false }
                model.bind(element: element.id, to: keyPath, value: value, source: source.id)
                model.select(element.id)
                return true
            } isTargeted: { targeted in
                isDropTarget = targeted
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Palette.accentAlt, lineWidth: isDropTarget ? 2 : 0)
            )
    }

    // MARK: - Click or move

    /// One gesture for both, rather than a `DragGesture` beside an
    /// `onTapGesture`. Two gestures on the same view compete for the event
    /// stream and the drag wins even when the pointer never moves, which is
    /// how clicking an element on the canvas ended up doing nothing at all
    /// while the layer list selected it fine.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travelled = abs(value.translation.width) + abs(value.translation.height)
                if !isMoving {
                    guard travelled > 3 else { return }
                    isMoving = true
                    if !model.selection.contains(element.id) { model.select(element.id) }
                    // Capture the starting frame of everything being dragged so
                    // a multi-element move stays rigid instead of each element
                    // snapping to the grid independently.
                    for selected in model.selectedElements { dragOrigin[selected.id] = selected.frame }
                }
                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height
                let origins = dragOrigin
                model.edit("Move", coalescing: true) { doc in
                    for index in doc.elements.indices {
                        guard let origin = origins[doc.elements[index].id] else { continue }
                        doc.elements[index].frame.x = model.snap(origin.x + dx)
                        doc.elements[index].frame.y = model.snap(origin.y + dy)
                        doc.elements[index].frame = doc.elements[index].frame.normalised
                    }
                }
            }
            .onEnded { _ in
                if !isMoving {
                    model.select(element.id, add: NSEvent.modifierFlags.contains(.shift))
                }
                isMoving = false
                dragOrigin.removeAll()
                model.endGesture()
            }
    }

    // MARK: - Resize

    @ViewBuilder
    private func handle(_ corner: Corner) -> some View {
        if isSelected {
            Circle()
                .fill(Palette.accent)
                .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1))
                .frame(width: handleSize, height: handleSize)
                .offset(x: corner.isLeading ? -handleSize / 2 : handleSize / 2,
                        y: corner.isTop ? -handleSize / 2 : handleSize / 2)
                .gesture(resizeGesture(corner))
        }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin[element.id] == nil {
                    dragOrigin[element.id] = element.frame
                }
                guard let origin = dragOrigin[element.id] else { return }
                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height
                model.update(element.id, "Resize", coalescing: true) { element in
                    element.frame = corner.resized(origin, dx: dx, dy: dy, snap: model.snap)
                }
            }
            .onEnded { _ in
                dragOrigin.removeAll()
                model.endGesture()
            }
    }

    enum Corner: CaseIterable, Hashable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }

        /// Resizes from the dragged corner, keeping the opposite one pinned.
        func resized(_ frame: Frame, dx: Double, dy: Double, snap: (Double) -> Double) -> Frame {
            var f = frame
            let minimum = 0.02
            switch self {
            case .topLeading:
                let x = snap(frame.x + dx), y = snap(frame.y + dy)
                f.width = max(frame.x + frame.width - x, minimum)
                f.height = max(frame.y + frame.height - y, minimum)
                f.x = min(x, frame.x + frame.width - minimum)
                f.y = min(y, frame.y + frame.height - minimum)
            case .topTrailing:
                let y = snap(frame.y + dy)
                f.width = max(snap(frame.width + dx), minimum)
                f.height = max(frame.y + frame.height - y, minimum)
                f.y = min(y, frame.y + frame.height - minimum)
            case .bottomLeading:
                let x = snap(frame.x + dx)
                f.width = max(frame.x + frame.width - x, minimum)
                f.height = max(snap(frame.height + dy), minimum)
                f.x = min(x, frame.x + frame.width - minimum)
            case .bottomTrailing:
                f.width = max(snap(frame.width + dx), minimum)
                f.height = max(snap(frame.height + dy), minimum)
            }
            return f.normalised
        }
    }
}
