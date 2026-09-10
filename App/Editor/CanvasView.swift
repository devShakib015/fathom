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
    /// Arrow-key nudging needs real keyboard focus, and clicking an element
    /// goes through a drag gesture that does not grant it. The canvas takes
    /// focus explicitly whenever anything on it is touched.
    @FocusState private var focused: Bool
    /// Shows the design with none of the editor around it.
    ///
    /// The canvas is a working surface — grid, handles, a selection outline,
    /// magnified to two hundred percent — and there was no way to see what you
    /// were actually making. Preview is the same renderer the desktop uses, at
    /// the size the desktop uses, with all of that taken away.
    @State private var previewing = false

    private var canvasSize: CGSize {
        let reference = model.doc.family.referenceSize
        return CGSize(width: reference.width * zoom, height: reference.height * zoom)
    }

    /// Every element's absolute rect, nested ones included, so a repeater's
    /// child can be clicked and dragged like anything else.
    private var placements: [Placement] {
        ElementLayout.placements(model.doc, data: model.data, in: canvasSize, scale: zoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Palette.hairline)
            surface
        }
        .background(Palette.background)
        // A drag that never ends — the view goes away mid-gesture, or the
        // document is switched — would otherwise leave saving suspended and
        // silently drop the edit.
        .onDisappear { model.endGesture() }
    }

    /// One grid step per press, or one hundredth with the grid off — the two
    /// sizes of adjustment anyone actually wants from an arrow key.
    private func nudge(_ dx: Double, _ dy: Double) -> KeyPress.Result {
        guard !model.selection.isEmpty else { return .ignored }
        let step = model.snapEnabled ? 1.0 / Double(model.gridDivisions) : 0.01
        model.nudgeSelected(dx: dx * step, dy: dy * step)
        return .handled
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        // Scrolls rather than compresses.
        //
        // Twice now, adding a control has made this row wider than its column:
        // the first time it shoved the whole window sideways and clipped the
        // sidebar, the second time SwiftUI squeezed the labels to one character
        // per line. A row that can scroll cannot do either, whatever is added
        // to it next or however narrow the window gets.
        ScrollView(.horizontal, showsIndicators: false) {
            toolbarContents
        }
        .frame(height: 30)
    }

    private var toolbarContents: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $previewing) {
                Label("Preview", systemImage: "eye")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("See it the way it will look on the desktop")

            // Icon-only, with tooltips. Spelled out, these three labels no
            // longer fit the column and SwiftUI compressed them to one
            // character per line — "G r i d" stacked vertically. Preview keeps
            // its word because it is the one somebody needs to find.
            Toggle(isOn: $model.gridVisible) {
                Label("Grid", systemImage: "grid")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .help("Show the grid")

            Toggle(isOn: $model.snapEnabled) {
                Label("Snap", systemImage: "dot.squareshape.split.2x2")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .help("Pull elements onto the grid as you move them")

            Divider().frame(height: 16)

            // Lining things up by eye and arrow key was the only option, which
            // is why nothing anybody made looked straight.
            ForEach(ElementAlignment.allCases) { alignment in
                Button { model.align(alignment) } label: {
                    Image(systemName: alignment.symbol)
                }
                .disabled(model.selection.isEmpty
                          || (alignment.needsThree && model.selection.count < 3))
                .help(alignment.label)
                .controlSize(.small)
            }

            Spacer()

            Button { model.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                .disabled(model.selection.isEmpty)
                .help("Duplicate  ⌘D")
            Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                .disabled(model.selection.isEmpty)
                .help("Delete  ⌫")

            Divider().frame(height: 16)

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
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused)
                    .onKeyPress(.leftArrow) { nudge(-1, 0) }
                    .onKeyPress(.rightArrow) { nudge(1, 0) }
                    .onKeyPress(.upArrow) { nudge(0, -1) }
                    .onKeyPress(.downArrow) { nudge(0, 1) }
                    .onTapGesture { focused = true; model.deselect() }

                if previewing { preview } else { widget.padding(60) }
            }
            .frame(minWidth: canvasSize.width + 120, minHeight: canvasSize.height + 120)
        }
        .background(
            LinearGradient(colors: [Palette.surface.opacity(0.55), Palette.background],
                           startPoint: .top, endPoint: .bottom))
    }

    /// The design at its true size, twice — the size it will be on the
    /// desktop, and doubled for looking at closely.
    private var preview: some View {
        let size = model.doc.family.referenceSize
        return VStack(spacing: 26) {
            Text("This is how it will look. Press Escape to go back.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)

            ForEach([1.0, 2.0], id: \.self) { scale in
                VStack(spacing: 7) {
                    ZStack {
                        model.doc.background.swatch
                        WidgetCanvas(doc: model.doc, data: model.data)
                    }
                    .frame(width: size.width * scale, height: size.height * scale)
                    .clipShape(RoundedRectangle(
                        cornerRadius: WidgetDoc.Family.cornerRadius * scale, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 18 * scale, y: 8 * scale)

                    Text(scale == 1 ? "Actual size" : "Twice actual size")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textDim.opacity(0.8))
                }
            }
        }
        .padding(50)
        .onExitCommand { previewing = false }
    }

    private var widget: some View {
        ZStack(alignment: .topLeading) {
            model.doc.background.swatch
            // The rendered document is a picture here, not an interaction
            // target. Text and images are hit-testable views, and leaving them
            // live means every canvas click races the selection layer above
            // them — which is precisely how clicking an element stopped
            // selecting it. Only the chrome should ever receive a click.
            WidgetCanvas(doc: model.doc, data: model.data)
                .allowsHitTesting(false)
            if model.gridVisible, !previewing { grid }
            if !previewing { chrome }
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
            // Every fourth line is drawn stronger, so the eye has quarters and
            // a centre to aim at rather than an undifferentiated mesh.
            var strong = Path()
            let quarter = Double(model.gridDivisions) / 4
            for i in 1..<model.gridDivisions where Double(i).truncatingRemainder(dividingBy: quarter) == 0 {
                let px = step * Double(i), py = vStep * Double(i)
                strong.move(to: CGPoint(x: px, y: 0)); strong.addLine(to: CGPoint(x: px, y: size.height))
                strong.move(to: CGPoint(x: 0, y: py)); strong.addLine(to: CGPoint(x: size.width, y: py))
            }
            // Was 0.05 — invisible on a dark backdrop, which is the whole
            // reason people said there was no grid.
            context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
            context.stroke(strong, with: .color(.white.opacity(0.22)), lineWidth: 0.5)
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

            ForEach(placements) { placement in
                ElementHandle(focused: $focused,
                              element: placement.element,
                              isSelected: model.selection.contains(placement.id),
                              isTemplate: placement.isTemplate,
                              isHidden: placement.isHidden,
                              model: model,
                              containerSize: placement.containerSize,
                              dragOrigin: $dragOrigin)
                    .frame(width: max(placement.rect.width, 10),
                           height: max(placement.rect.height, 10))
                    .position(x: placement.rect.midX, y: placement.rect.midY)
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
    @FocusState.Binding var focused: Bool
    let element: Element
    let isSelected: Bool
    /// Drawn once per row of a repeater. Marked so the outline can say so —
    /// moving it moves every copy, which is surprising unless it is signposted.
    let isTemplate: Bool
    /// Currently hidden by its own condition. Outlined faintly even when not
    /// selected, so it can still be found and clicked.
    let isHidden: Bool
    @Bindable var model: EditorModel
    /// The box this element's frame is relative to, which is its container's,
    /// not the canvas's.
    let containerSize: CGSize
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
                Rectangle().stroke(outlineColour,
                                   style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1,
                                                      dash: isTemplate || isHidden ? [4, 3] : []))
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

    private var outlineColour: Color {
        if isSelected { return isTemplate ? Palette.accentAlt : Palette.accent }
        // Nothing is drawn where a hidden element sits, so without this its
        // handle would be an invisible target.
        return isHidden ? Palette.textDim.opacity(0.55) : .clear
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
                // Divided by the container, not the canvas: a child of a
                // repeater cell moves in that cell's unit space.
                let dx = value.translation.width / containerSize.width
                let dy = value.translation.height / containerSize.height
                let origins = dragOrigin
                model.edit("Move", coalescing: true) { doc in
                    for (id, origin) in origins {
                        doc.elements.update(id) { element in
                            element.frame.x = model.snap(origin.x + dx)
                            element.frame.y = model.snap(origin.y + dy)
                            element.frame = element.frame.normalised
                        }
                    }
                }
            }
            .onEnded { _ in
                if !isMoving {
                    focused = true
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
                let dx = value.translation.width / containerSize.width
                let dy = value.translation.height / containerSize.height
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
