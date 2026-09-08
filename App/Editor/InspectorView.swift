import SwiftUI

/// The right-hand panel: everything about the selected element, then the
/// document itself.
struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let element = model.focusedElement {
                    ElementInspector(model: model, element: element)
                } else {
                    emptySelection
                }
                Divider().overlay(Palette.hairline)
                DocumentInspector(model: model)
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
            InspectorRow(label: "Face") {
                Picker("", selection: binding(\.style.font.design, "Face")) {
                    ForEach(FontSpec.Design.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
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

/// An SF Symbol name field with a live check, because a mistyped symbol name
/// renders as a question mark on the desktop and nowhere says why.
private struct SymbolField: View {
    @Binding var name: String

    private var valid: Bool { NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil }

    var body: some View {
        HStack(spacing: 8) {
            TextField("sun.max.fill", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            Image(systemName: valid ? name : "questionmark")
                .foregroundStyle(valid ? Palette.accent : .orange)
                .frame(width: 18)
                .help(valid ? "Valid SF Symbol" : "No SF Symbol with that name")
        }
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
