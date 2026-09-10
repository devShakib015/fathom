import SwiftUI

/// The editor: palette and layers on the left, canvas in the middle,
/// inspector on the right. The arrangement every design tool has converged on,
/// because it is the one where nothing you need is more than one glance away.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        // An HStack, not an HSplitView.
        //
        // HSplitView remembers where its dividers were and will keep widths the
        // window can no longer afford: the panes sum wider than the window and
        // SwiftUI clips instead of re-laying out. The symptom was labels cut
        // mid-word at the right edge with no scrollbar and no way to reach
        // them — and pinning the inspector to a fixed width made it worse,
        // pushing the sidebar off the left as well.
        //
        // The cost is that the dividers no longer drag. The rails are the
        // fixed-width kind in every tool this resembles, and a layout that is
        // always right beats one that is adjustable and sometimes broken.
        HStack(spacing: 0) {
            leftRail
                .frame(width: 232)
            Divider().overlay(Palette.hairline)

            CanvasView(model: model)
                .frame(maxWidth: .infinity)
            Divider().overlay(Palette.hairline)

            InspectorView(model: model)
                .frame(width: 300)
        }
        // Bounded height, so the inspector's ScrollView actually scrolls.
        //
        // Without it the row grows to whatever its tallest child wants, the
        // scroll view is offered unbounded height, and content past the bottom
        // of the window is simply unreachable — real scroll-wheel events did
        // nothing. That is how the Wallpaper controls, the Summon section and
        // the "Grant again" button all ended up impossible to click.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            Text("Click one to drop it on the widget, then drag it where you want it.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

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
                    // Nothing anywhere said what an arc or a repeater was, and
                    // somebody who does not already know cannot be expected to
                    // guess from a nine-point label.
                    .help("\(kind.displayName) — \(kind.explanation)")
                    .foregroundStyle(Palette.text)
                }
            }
        }
        .padding(12)
    }
}

/// Draw order, front at the top — the opposite of the array and the same as
/// every other design tool. Containers show their contents indented beneath
/// them, because a repeater whose children are invisible here is a repeater
/// nobody can edit.
struct LayerList: View {
    @Bindable var model: EditorModel

    /// Front-first, with each container's children directly under it.
    private var rows: [(element: Element, depth: Int)] {
        func walk(_ elements: [Element], depth: Int) -> [(Element, Int)] {
            elements.reversed().flatMap { element in
                [(element, depth)] + walk(element.children, depth: depth + 1)
            }
        }
        return walk(model.doc.elements, depth: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LAYERS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textDim)
                    .tracking(0.8)
                Spacer()
                Text("\(model.doc.elements.allIDs().count)")
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
                ForEach(rows, id: \.element.id) { row in
                    LayerRow(element: row.element, depth: row.depth)
                        .tag(row.element.id)
                        .contextMenu {
                            Button("Bring to Front") { model.move(row.element.id, toFront: true) }
                            Button("Send to Back") { model.move(row.element.id, toFront: false) }
                            Divider()
                            Button("Duplicate") {
                                model.select(row.element.id); model.duplicateSelected()
                            }
                            Button("Delete", role: .destructive) {
                                model.select(row.element.id); model.deleteSelected()
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
    let depth: Int

    var body: some View {
        HStack(spacing: 7) {
            if depth > 0 {
                // A rule rather than plain indentation: at one glance it says
                // "this belongs to the thing above", which matters most for a
                // repeater's template.
                Rectangle()
                    .fill(Palette.accentAlt.opacity(0.4))
                    .frame(width: 1)
                    .padding(.leading, CGFloat(depth - 1) * 9)
                    .padding(.vertical, 1)
            }
            Image(systemName: element.kind.paletteSymbol)
                .font(.system(size: 10))
                .foregroundStyle(element.isContainer ? Palette.accentAlt : Palette.textDim)
                .frame(width: 14)
            Text(element.displayName)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 4)
            if element.visibleWhen?.isEmpty == false {
                Image(systemName: "eye")
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.textDim)
                    .help("Only shown when a condition holds")
            }
            if element.binding != nil {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.accent)
                    .help("Bound to live data")
            }
        }
        .padding(.vertical, 1)
    }
}
