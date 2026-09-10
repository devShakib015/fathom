import SwiftUI

/// The right-hand panel: everything about the selected element, then the
/// document itself.
struct InspectorView: View {
    @Bindable var model: EditorModel

    /// Two tabs rather than one long column.
    ///
    /// Stacked, the fields tree sat below the element's own controls and fell
    /// off the bottom of the panel the moment anything was selected — which
    /// defeats the whole gesture, since binding means having a selected
    /// element and a field list visible at the same time.
    enum Tab: String, CaseIterable {
        case design = "Design"
        case data = "Data"
    }

    @State private var tab: Tab = .design

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().overlay(Palette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .design:
                        if let element = model.focusedElement {
                            ElementInspector(model: model, element: element)
                        } else {
                            emptySelection
                        }
                        Divider().overlay(Palette.hairline)
                        DocumentInspector(model: model)
                        Divider().overlay(Palette.hairline)
                        PaletteSection(model: model)
                        Divider().overlay(Palette.hairline)
                        SurfacesSection(doc: model.doc)
                    case .data:
                        SourcesInspector(model: model) { elementID, sourceID, keyPath, value in
                            model.bind(element: elementID, to: keyPath, value: value, source: sourceID)
                        }
                    }
                }
            }
        }
        .background(Palette.background)
    }

    private var emptySelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.text)
            Text("Pick an element on the canvas, or add one from the palette.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

// MARK: - Element

private struct ElementInspector: View {
    @Bindable var model: EditorModel
    let element: Element

    /// Writes through to the model so that every keystroke is undoable and
    /// autosaved, rather than the view holding a private copy that has to be
    /// reconciled later.
    private func binding<V>(_ keyPath: WritableKeyPath<Element, V>, _ name: String) -> Binding<V> {
        Binding(
            get: { model.doc.elements.first { $0.id == element.id }?[keyPath: keyPath] ?? element[keyPath: keyPath] },
            set: { value in model.update(element.id, name) { $0[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            InspectorSection(title: "Content") {
                content
            }
            Divider().overlay(Palette.hairline)

            InspectorSection(title: "Position") {
                InspectorRow(label: "X") { NumberField(label: "X", value: binding(\.frame.x, "Move"), range: -0.5...1.5) }
                InspectorRow(label: "Y") { NumberField(label: "Y", value: binding(\.frame.y, "Move"), range: -0.5...1.5) }
                InspectorRow(label: "Width") { NumberField(label: "W", value: binding(\.frame.width, "Resize"), range: 0.01...2) }
                InspectorRow(label: "Height") { NumberField(label: "H", value: binding(\.frame.height, "Resize"), range: 0.01...2) }
            }
            Divider().overlay(Palette.hairline)

            InspectorSection(title: "Style") {
                style
            }
            Divider().overlay(Palette.hairline)

            VisibilityInspector(model: model, element: element)
            Divider().overlay(Palette.hairline)
            ActionInspector(model: model, element: element)
            Divider().overlay(Palette.hairline)

            BindingInspector(model: model, element: element)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: element.kind.paletteSymbol)
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
            TextField("Name", text: Binding(
                get: { element.name ?? "" },
                set: { new in model.update(element.id, "Rename") { $0.name = new.isEmpty ? nil : new } }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.text)
            Spacer()
            if let parent = model.doc.parentID(of: element.id),
               let container = model.doc.element(parent) {
                // Position and size mean something different inside a
                // container, so say which one you are inside.
                Text("in \(container.displayName)")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.accentAlt)
                    .lineLimit(1)
            }
            Text(element.kind.displayName)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch element.kind {
        case .text:
            TextField("Text", text: binding(\.text, "Edit text"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
        case .symbol:
            SymbolField(name: binding(\.text, "Symbol"))
        case .arc:
            InspectorRow(label: "Value") {
                NumberField(label: "Value", value: Binding(
                    get: { Double(element.text) ?? 0 },
                    set: { new in model.update(element.id, "Value") { $0.text = String(format: "%.2f", new) } }
                ), range: 0...1)
            }
        case .spark:
            TextField("12, 15, 13, 19", text: binding(\.text, "Series"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        case .bar:
            InspectorRow(label: "Value") {
                NumberField(label: "Value", value: Binding(
                    get: { Double(element.text) ?? 0 },
                    set: { new in model.update(element.id, "Value") { $0.text = String(format: "%.2f", new) } }
                ), range: 0...1)
            }
        case .image:
            VStack(alignment: .leading, spacing: 4) {
                TextField("https://example.com/picture.png", text: binding(\.text, "Image URL"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Text("Fetched when the widget reloads and cached, so a dropped connection keeps the last picture.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .repeater:
            Text("Bind this to a list below. Its children are drawn once per item, and inside them `item`, `index` and `total` are available.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        case .group:
            Text("Holds other elements so they move, hide and fade together.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        case .shape, .divider:
            Text("Nothing to set — this element draws itself.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
        }
    }

    @ViewBuilder
    private var style: some View {
        if element.kind == .text || element.kind == .symbol {
            InspectorRow(label: "Size") {
                NumberField(label: "Size", value: binding(\.style.font.size, "Font size"),
                            range: 4...160, step: 1, format: "%.0f")
            }
            InspectorRow(label: "Weight") {
                Picker("", selection: binding(\.style.font.weight, "Weight")) {
                    ForEach(FontSpec.Weight.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
            }
        }

        if element.kind == .text {
            InspectorRow(label: "Font") {
                Picker("", selection: Binding(
                    get: { element.style.font.family ?? "" },
                    set: { new in
                        model.update(element.id, "Font") {
                            $0.style.font.family = new.isEmpty ? nil : new
                        }
                    }
                )) {
                    // The system font is not a family and cannot be asked for
                    // by name, so it is the empty selection rather than an
                    // entry in the list.
                    Text("System").tag("")
                    Divider()
                    ForEach(FontCatalogue.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            if element.style.font.family == nil {
                InspectorRow(label: "Face") {
                    Picker("", selection: binding(\.style.font.design, "Face")) {
                        ForEach(FontSpec.Design.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .labelsHidden()
                }
            } else if !element.style.font.isAvailable {
                Label("This Mac does not have that font — it will draw in the system font.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InspectorRow(label: "Lines") {
                NumberField(label: "Lines", value: Binding(
                    get: { Double(element.style.lineLimit) },
                    set: { new in model.update(element.id, "Line limit") { $0.style.lineLimit = Int(new) } }
                ), range: 0...8, step: 1, format: "%.0f")
            }
            InspectorRow(label: "Digits") {
                Toggle("Monospaced", isOn: binding(\.style.font.monospacedDigits, "Digits"))
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)
            }
        }

        if element.kind != .shape {
            InspectorRow(label: "Align") {
                Picker("", selection: binding(\.style.alignment, "Alignment")) {
                    Image(systemName: "text.alignleft").tag(TextAlignment.leading)
                    Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                    Image(systemName: "text.alignright").tag(TextAlignment.trailing)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }

        ColorRow(label: element.kind == .shape ? "Colour" : "Foreground",
                 spec: binding(\.style.foreground, "Colour"))

        if element.kind == .shape || element.kind == .arc || element.kind == .spark {
            OptionalColorRow(label: element.kind == .arc ? "Track" : "Fill",
                             spec: binding(\.style.fill, "Fill"),
                             fallback: ColorSpec(Palette.accentHex, opacity: 0.2))
        }

        if element.kind == .arc || element.kind == .spark || element.kind == .divider {
            InspectorRow(label: "Thickness") {
                NumberField(label: "Thickness", value: binding(\.style.lineWidth, "Thickness"),
                            range: 0.5...40, step: 0.5, format: "%.1f")
            }
        }

        if element.kind == .shape {
            InspectorRow(label: "Corner") {
                NumberField(label: "Corner", value: binding(\.style.cornerRadius, "Corner"),
                            range: 0...80, step: 1, format: "%.0f")
            }
        }

        InspectorRow(label: "Opacity") {
            Slider(value: binding(\.style.opacity, "Opacity"), in: 0...1)
            Text(String(format: "%.0f%%", element.style.opacity * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.textDim)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// Picking an icon by looking at icons.
///
/// This was a bare text field: you typed an exact SF Symbol name from memory
/// and a tick told you afterwards whether you had guessed right. The field is
/// still here, because someone who knows the name should be able to type it and
/// because a symbol name can be bound to data — but it is no longer the only
/// way in.
private struct SymbolField: View {
    @Binding var name: String
    @State private var browsing = false

    private var valid: Bool { NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil }

    var body: some View {
        HStack(spacing: 6) {
            TextField("sun.max.fill", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            Button { browsing = true } label: {
                Image(systemName: valid ? name : "square.grid.2x2")
                    .font(.system(size: 12))
                    .foregroundStyle(valid ? Palette.accent : Palette.textDim)
                    .frame(width: 26, height: 20)
                    .background(Palette.hairline.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Choose an icon")
            .popover(isPresented: $browsing, arrowEdge: .bottom) {
                SymbolPicker(chosen: $name) { browsing = false }
            }
        }
    }
}

/// A grid of icons, grouped and searchable.
private struct SymbolPicker: View {
    @Binding var chosen: String
    var onPick: () -> Void

    @State private var query = ""

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search icons — try weather, battery, arrow", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let groups = SymbolCatalogue.search(query)
                    if groups.isEmpty {
                        Text("No icons match “\(query)”. You can still type an exact SF Symbol name.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(groups, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.name.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.textDim)
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    Button {
                                        chosen = symbol
                                        onPick()
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.system(size: 14))
                                            .frame(width: 30, height: 26)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .fill(symbol == chosen
                                                          ? Palette.accent.opacity(0.25)
                                                          : Color.clear))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(symbol == chosen ? Palette.accent : Palette.text)
                                    .help(symbol)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(height: 260)
        }
        .padding(12)
        .frame(width: 300)
        .background(Palette.background)
    }
}

// MARK: - Document

private struct DocumentInspector: View {
    @Bindable var model: EditorModel

    var body: some View {
        InspectorSection(title: "Widget") {
            InspectorRow(label: "Name") {
                TextField("Name", text: Binding(
                    get: { model.doc.name },
                    set: { model.setName($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            InspectorRow(label: "Size") {
                Text(model.doc.family.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
                Spacer()
            }

            // Where it came from, and the way back.
            //
            // The catalogue exists to be duplicated and edited, which only
            // works if editing is safe to try. Without this, the six hundred
            // and eightieth design is as unrecoverable as the first edit made
            // to it.
            if let origin = model.doc.origin, let entry = Catalog.entry(origin) {
                InspectorRow(label: "From") {
                    Text(entry.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                    Spacer()
                    if model.doc.differsFromOriginal {
                        Button("Revert") { model.revertToOriginal() }
                            .font(.system(size: 10))
                            .buttonStyle(.link)
                            .help("Put every element, style and source back the way \(entry.name) shipped. Your name for it is kept, and this can be undone.")
                    } else {
                        Text("unchanged")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textDim.opacity(0.7))
                    }
                }
            }
            InspectorRow(label: "Backdrop") {
                Picker("", selection: Binding(
                    get: { model.doc.background.kind },
                    set: { kind in
                        var background = model.doc.background
                        background.kind = kind
                        model.setBackground(background)
                    }
                )) {
                    ForEach(Background.Kind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }

            if model.doc.background.kind == .color || model.doc.background.kind == .gradient {
                ColorRow(label: "From", spec: Binding(
                    get: { model.doc.background.color },
                    set: { var b = model.doc.background; b.color = $0; model.setBackground(b) }
                ))
            }
            if model.doc.background.kind == .gradient {
                ColorRow(label: "To", spec: Binding(
                    get: { model.doc.background.gradientEnd },
                    set: { var b = model.doc.background; b.gradientEnd = $0; model.setBackground(b) }
                ))
                InspectorRow(label: "Angle") {
                    NumberField(label: "Angle", value: Binding(
                        get: { model.doc.background.angle },
                        set: { var b = model.doc.background; b.angle = $0; model.setBackground(b) }
                    ), range: 0...360, step: 15, format: "%.0f")
                }
            }

            InspectorRow(label: "Refresh") {
                Text("every \(Int(model.doc.minimumRefresh)) s")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
                Spacer()
            }
            Text("64 seconds is the floor macOS enforces. Asking for less is silently rounded up.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
