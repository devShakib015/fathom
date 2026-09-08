import SwiftUI

/// The editor: palette and layers on the left, canvas in the middle,
/// inspector on the right. The arrangement every design tool has converged on,
/// because it is the one where nothing you need is more than one glance away.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        HSplitView {
            leftRail
                .frame(minWidth: 190, idealWidth: 210, maxWidth: 280)

            CanvasView(model: model)
                .frame(minWidth: 380)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.delete) { model.deleteSelected(); return .handled }
                .onKeyPress(.deleteForward) { model.deleteSelected(); return .handled }
                .onKeyPress(.leftArrow) { nudge(-1, 0) }
                .onKeyPress(.rightArrow) { nudge(1, 0) }
                .onKeyPress(.upArrow) { nudge(0, -1) }
                .onKeyPress(.downArrow) { nudge(0, 1) }
                .onKeyPress(.escape) { model.deselect(); return .handled }

            InspectorView(model: model)
                .frame(minWidth: 250, idealWidth: 272, maxWidth: 340)
        }
        .task(id: model.doc.id) { await model.resolve() }
        // Re-resolve on the same cadence the widget uses, so the canvas and the
        // desktop never disagree by more than one tick.
        .task(id: model.doc.id) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(WidgetDoc.refreshFloor))
                guard !Task.isCancelled else { return }
                await model.resolve()
            }
        }
    }

    /// One grid step per press, or one hundredth with the grid off — the two
    /// sizes of adjustment anyone actually wants from an arrow key.
    private func nudge(_ dx: Double, _ dy: Double) -> KeyPress.Result {
        guard !model.selection.isEmpty else { return .ignored }
        let step = model.snapEnabled ? 1.0 / Double(model.gridDivisions) : 0.01
        model.nudgeSelected(dx: dx * step, dy: dy * step)
        return .handled
    }

    // MARK: - Left rail

    private var leftRail: some View {
        VStack(spacing: 0) {
            ElementPalette(model: model)
            Divider().overlay(Palette.hairline)
            LayerList(model: model)
        }
        .background(Palette.background)
    }
}

/// The six primitives, as a grid of buttons.
///
/// This set is the hard ceiling on what anybody can build with Fathom — the
/// extension interprets a document, it cannot compile new code — so they were
/// chosen to compose rather than to enumerate. There is no "weather widget"
/// here and there never will be; a weather widget is a text bound to a number
/// beside a symbol bound to a condition.
struct ElementPalette: View {
    @Bindable var model: EditorModel

    private let columns = [GridItem(.adaptive(minimum: 58), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.textDim)
                .tracking(0.8)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Element.Kind.allCases, id: \.self) { kind in
                    Button { model.add(kind) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: kind.paletteSymbol)
                                .font(.system(size: 15, weight: .light))
                            Text(kind.displayName)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Palette.surface.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.text)
                }
            }
        }
        .padding(12)
    }
}

/// Draw order, front at the top — which is the opposite of the array and the
/// same as every other design tool.
struct LayerList: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LAYERS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textDim)
                    .tracking(0.8)
                Spacer()
                Text("\(model.doc.elements.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            List(selection: Binding(
                get: { model.selection },
                set: { model.selection = $0 }
            )) {
                ForEach(model.doc.elements.reversed()) { element in
                    LayerRow(element: element, isBound: element.binding != nil)
                        .tag(element.id)
                        .contextMenu {
                            Button("Bring to Front") { model.move(element.id, toFront: true) }
                            Button("Send to Back") { model.move(element.id, toFront: false) }
                            Divider()
                            Button("Duplicate") { model.select(element.id); model.duplicateSelected() }
                            Button("Delete", role: .destructive) {
                                model.select(element.id); model.deleteSelected()
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct LayerRow: View {
    let element: Element
    let isBound: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: element.kind.paletteSymbol)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim)
                .frame(width: 14)
            Text(element.displayName)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 4)
            if isBound {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.accent)
                    .help("Bound to live data")
            }
        }
        .padding(.vertical, 1)
    }
}
