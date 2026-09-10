import SwiftUI

/// Choosing what a widget shows, in words rather than key paths.
///
/// The only way to bind something was to open a tree of the raw data and click
/// a node — `battery` ▸ `percent`, `disk` ▸ `usedFraction`. Those are the names
/// the data uses. They are correct, they are what gets stored, and they are no
/// help at all to somebody deciding what to put on a widget.
///
/// Every one of these fields already carried a written description; nothing was
/// showing it. This lists those descriptions, grouped and searchable, and binds
/// the key path behind them. The raw tree is still there for anyone who wants
/// it — it is the only way to reach a field a web endpoint invented — but it is
/// no longer the front door.
struct FieldPicker: View {
    @Bindable var model: EditorModel
    let source: DataSource
    var onBind: (UUID, UUID, String, DataValue) -> Void

    @State private var query = ""

    /// The label, split into what it is and any qualifier after the comma.
    /// "Charge, 0…1" reads badly as one line and well as two.
    private func split(_ label: String) -> (name: String, hint: String) {
        guard let comma = label.firstIndex(of: ",") else { return (label, "") }
        return (String(label[label.startIndex..<comma]),
                String(label[label.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
    }

    private var groups: [(name: String, fields: [(path: String, label: String)])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var order: [String] = []
        var buckets: [String: [(path: String, label: String)]] = [:]

        for field in source.schema {
            if !needle.isEmpty,
               !field.label.lowercased().contains(needle),
               !field.path.lowercased().contains(needle) { continue }
            let root = field.path.split(separator: ".").first.map(String.init) ?? field.path
            let group = DataSource.groupName(forRoot: root)
            if buckets[group] == nil { order.append(group) }
            buckets[group, default: []].append(field)
        }
        return order.map { (name: $0, fields: buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Search — battery, time, free space…", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if groups.isEmpty {
                        Text("Nothing matches “\(query)”.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textDim)
                    }
                    ForEach(groups, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.textDim)
                            ForEach(group.fields, id: \.path) { field in
                                fieldRow(field)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)
        }
    }

    private func fieldRow(_ field: (path: String, label: String)) -> some View {
        let parts = split(field.label)
        let enabled = model.focusedElement != nil
        return Button {
            guard let element = model.focusedElement else { return }
            onBind(element.id, source.id, field.path,
                   model.data.trees[source.id]?[path: field.path] ?? .null)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(parts.name)
                        .font(.system(size: 11))
                        .foregroundStyle(enabled ? Palette.text : Palette.textDim)
                    if !parts.hint.isEmpty {
                        Text(parts.hint)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textDim.opacity(0.8))
                    }
                }
                Spacer(minLength: 4)
                // What it says right now, so the choice is made by looking at
                // the answer rather than at the name of the question.
                Text(sample(field.path))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.accent.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? "Show this on \(model.focusedElement!.displayName)  ·  \(field.path)"
                      : "Pick something on the widget first")
    }

    private func sample(_ path: String) -> String {
        guard let value = model.data.trees[source.id]?[path: path] else { return "" }
        let text = ValueFormatter.string(value,
                                         format: Format.inferred(for: value, keyPath: path, kind: .text),
                                         fallback: "")
        return text.count > 18 ? String(text.prefix(18)) + "…" : text
    }
}
