import SwiftUI

/// Points an element at live data.
///
/// This is the part that makes Fathom worth having — the 64-second floor only
/// matters if the thing refreshing is real. So the panel shows the value the
/// binding resolves to *right now*, next to the controls that produced it. A
/// key path that misses should be obvious here, not after a trip to the
/// desktop and a minute of waiting.
struct BindingInspector: View {
    @Bindable var model: EditorModel
    let element: Element

    private var binding: DataBinding? { element.binding }

    var body: some View {
        InspectorSection(title: "Data") {
            Toggle(isOn: Binding(
                get: { binding != nil },
                set: { on in
                    model.update(element.id, on ? "Bind" : "Unbind") { e in
                        e.binding = on ? Self.defaultBinding(for: e, in: model.doc) : nil
                    }
                }
            )) {
                Text("Bind to a data source")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if let binding {
                sourceRow(binding)
                keyPathRow(binding)
                transformRow(binding)
                formatRows(binding)
                fallbackRow(binding)
                resolved(binding)
            } else {
                Text("Showing the literal content above.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.8))
            }
        }
    }

    // MARK: - Rows

    private func sourceRow(_ b: DataBinding) -> some View {
        InspectorRow(label: "Source") {
            Picker("", selection: bind(\.sourceID, "Source")) {
                ForEach(model.doc.sources) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .labelsHidden()
        }
    }

    private func keyPathRow(_ b: DataBinding) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            InspectorRow(label: "Field") {
                TextField("battery.percent", text: bind(\.keyPath, "Key path"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            // Until the JSON tree browser lands, the system source's own fields
            // are offered as a menu. Nobody should have to guess a key path.
            if model.doc.source(b.sourceID)?.kind == .system {
                Menu {
                    ForEach(SystemSource.schemaDescription, id: \.path) { entry in
                        Button("\(entry.path)  —  \(entry.label)") {
                            model.update(element.id, "Key path") { $0.binding?.keyPath = entry.path }
                        }
                    }
                } label: {
                    Label("Browse system fields", systemImage: "list.bullet.indent")
                        .font(.system(size: 10))
                }
                .menuStyle(.borderlessButton)
                .padding(.leading, 70)
            }
        }
    }

    /// The optional transform.
    ///
    /// Off by default and out of the way, because the large majority of
    /// bindings just show what arrived. When it is on, the field validates as
    /// you type: an expression that cannot parse is a red message here rather
    /// than a widget that quietly renders its fallback on the desktop.
    @ViewBuilder
    private func transformRow(_ b: DataBinding) -> some View {
        Toggle(isOn: Binding(
            get: { b.hasExpression },
            set: { on in
                model.update(element.id, on ? "Add transform" : "Remove transform") {
                    $0.binding?.expression = on ? "value" : nil
                }
            }
        )) {
            Text("Transform the value")
                .font(.system(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.small)

        if b.hasExpression {
            TextField("value", text: bind(\.expression, "Transform").replacingNil(with: ""), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1...4)

            if let problem = parseProblem(b) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("`value` is the field above. Other fields can be named directly.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Menu {
                ForEach(Self.recipes, id: \.expression) { recipe in
                    Button(recipe.label) {
                        model.update(element.id, "Transform") { $0.binding?.expression = recipe.expression }
                    }
                }
            } label: {
                Label("Examples", systemImage: "function")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func parseProblem(_ b: DataBinding) -> String? {
        guard let source = b.expression, b.hasExpression else { return nil }
        do { _ = try ExpressionParser.parse(source); return nil }
        catch { return error.localizedDescription }
    }

    /// Starting points, chosen because each is a thing somebody will actually
    /// want and none of them is obvious from a blank field.
    private static let recipes: [(label: String, expression: String)] = [
        ("Celsius to Fahrenheit", "round(value * 9 / 5 + 32, 1)"),
        ("Round to one decimal", "round(value, 1)"),
        ("Weather code to an SF Symbol",
         "map(value, 0, \"sun.max.fill\", 1, \"cloud.sun.fill\", 2, \"cloud.fill\", 3, \"cloud.fill\", 61, \"cloud.rain.fill\", 95, \"cloud.bolt.fill\", \"cloud.fill\")"),
        ("Word instead of a number", "if(value > 30, \"hot\", if(value > 15, \"mild\", \"cold\"))"),
        ("Highest of a list", "highest(value)"),
        ("Average of a list", "round(avg(value), 1)"),
        ("Difference between two fields",
         "round(field(\"current.temperature_2m\") - field(\"current.apparent_temperature\"), 1)"),
        ("Fall back to another field", "coalesce(value, 0)"),
    ]

    @ViewBuilder
    private func formatRows(_ b: DataBinding) -> some View {
        InspectorRow(label: "Show as") {
            Picker("", selection: bind(\.format.kind, "Format")) {
                ForEach(Format.Kind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
        }

        switch b.format.kind {
        case .date:
            InspectorRow(label: "Style") {
                Picker("", selection: bind(\.format.dateStyle, "Date style")) {
                    ForEach(Format.DateStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }
        case .number, .percent, .bytes:
            InspectorRow(label: "Decimals") {
                NumberField(label: "Decimals", value: Binding(
                    get: { Double(b.format.precision) },
                    set: { v in model.update(element.id, "Decimals") { $0.binding?.format.precision = Int(v) } }
                ), range: 0...6, step: 1, format: "%.0f")
            }
        case .text, .duration:
            EmptyView()
        }

        InspectorRow(label: "Before") {
            TextField("", text: bind(\.format.prefix, "Prefix")).textFieldStyle(.roundedBorder)
        }
        InspectorRow(label: "After") {
            TextField("°", text: bind(\.format.suffix, "Suffix")).textFieldStyle(.roundedBorder)
        }
    }

    private func fallbackRow(_ b: DataBinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            InspectorRow(label: "If missing") {
                TextField("—", text: bind(\.fallback, "Fallback")).textFieldStyle(.roundedBorder)
            }
            Text("Networks fail. A widget that renders blank looks broken; one that renders this looks offline.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the binding evaluates to at this instant.
    private func resolved(_ b: DataBinding) -> some View {
        let value = model.data.value(for: b)
        let raw = model.data.rawValue(for: b)
        let hit = value != nil
        return HStack(spacing: 8) {
            Image(systemName: hit ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(hit ? Palette.accent : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.data.text(for: element))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text(hit
                     ? (b.hasExpression ? "\(raw?.stringValue ?? "null") → \(value!.stringValue)" : "raw: \(value!.stringValue)")
                     : (b.hasExpression ? "the transform produced nothing — showing the fallback"
                                        : "no value at that path — showing the fallback"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(9)
        .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Plumbing

    private func bind<V>(_ keyPath: WritableKeyPath<DataBinding, V>, _ name: String) -> Binding<V> {
        Binding(
            get: {
                let current = model.doc.elements.first { $0.id == element.id }?.binding ?? element.binding!
                return current[keyPath: keyPath]
            },
            set: { value in
                model.update(element.id, name) { $0.binding?[keyPath: keyPath] = value }
            }
        )
    }

    /// A first binding that already resolves to something, chosen to match the
    /// element it is being attached to. Switching a text element to "live" and
    /// getting a dash would teach the wrong lesson about whether this works.
    private static func defaultBinding(for element: Element, in doc: WidgetDoc) -> DataBinding? {
        guard let source = doc.sources.first else { return nil }
        switch element.kind {
        case .arc:
            return DataBinding(sourceID: source.id, keyPath: "battery.percent",
                           format: Format(kind: .percent), fallback: "0")
        case .spark:
            return DataBinding(sourceID: source.id, keyPath: "", format: Format(kind: .text), fallback: "")
        case .symbol:
            return DataBinding(sourceID: source.id, keyPath: "", format: Format(kind: .text), fallback: "questionmark")
        default:
            return DataBinding(sourceID: source.id, keyPath: "date.now",
                           format: Format(kind: .date, dateStyle: .time), fallback: "--:--")
        }
    }
}
