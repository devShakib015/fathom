import SwiftUI

/// The data sources panel: add a URL, fetch it, and browse what came back.
///
/// This is where the reload finding cashes out. A widget bound to a JSON
/// endpoint on a 64-second floor is a different category of object from
/// anything an iOS widget builder can offer, and none of that is visible until
/// somebody can paste their own URL and see their own numbers.
struct SourcesInspector: View {
    @Bindable var model: EditorModel
    /// The element a dragged field should bind to, if one is selected.
    var onBind: (UUID, String, DataValue) -> Void

    @State private var newURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection(title: "Data sources") {
                ForEach(model.doc.sources) { source in
                    SourceRow(model: model, source: source)
                }
                addRow
            }

            if let source = model.doc.sources.first(where: { $0.kind == .json }) {
                Divider().overlay(Palette.hairline)
                TreeBrowser(model: model, source: source, onBind: onBind)
            }
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TextField("https://api.example.com/data.json", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(URL(string: newURL)?.host == nil)
            }
            Text("Fathom fetches this only when you ask, and when a widget using it reloads. Nothing else leaves your Mac.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func add() {
        let trimmed = newURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let host = url.host else { return }
        model.addSource(DataSource(name: host, kind: .json, url: trimmed))
        newURL = ""
        Task { await model.resolve() }
    }
}

private struct SourceRow: View {
    @Bindable var model: EditorModel
    let source: DataSource

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: source.kind == .system ? "cpu" : "globe")
                .foregroundStyle(Palette.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(status)
                    .font(.system(size: 9))
                    .foregroundStyle(model.data.failures[source.id] != nil ? .orange : Palette.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if source.kind == .json {
                Button {
                    model.removeSource(source.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.textDim)
                .help("Remove this source and unbind anything using it")
            }
        }
        .padding(.vertical, 3)
    }

    private var status: String {
        if let failure = model.data.failures[source.id] { return failure }
        if source.kind == .system { return "Local, never leaves this Mac" }
        if model.data.trees[source.id] != nil { return model.data.isStale ? "Cached" : source.host ?? "" }
        return source.host ?? "No URL"
    }
}

/// The parsed response, as an outline you can drag fields out of.
///
/// Key order is the endpoint's own, not alphabetical — the tree is how somebody
/// understands an unfamiliar API, and re-sorting it makes a familiar response
/// look foreign.
private struct TreeBrowser: View {
    @Bindable var model: EditorModel
    let source: DataSource
    var onBind: (UUID, String, DataValue) -> Void

    @State private var expanded: Set<String> = [""]

    private var root: DataValue? { model.data.trees[source.id] }

    var body: some View {
        InspectorSection(title: "Fields") {
            if let root {
                Text(model.focusedElement == nil
                     ? "Select an element, then click a field to bind it."
                     : "Click a field to bind it to \(model.focusedElement!.displayName).")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    TreeNode(label: source.name, path: "", value: root, depth: 0,
                             expanded: $expanded, model: model, onBind: onBind)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if model.isResolving {
                ProgressView().controlSize(.small)
            } else {
                Text(model.data.failures[source.id] ?? "Not fetched yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row of the tree, and its children when open.
///
/// Written as an explicit recursive view rather than an `OutlineGroup` because
/// each row needs its own key path — the thing being dragged onto an element is
/// the path, not the value — and the path is only knowable on the way down.
private struct TreeNode: View {
    let label: String
    let path: String
    let value: DataValue
    let depth: Int
    @Binding var expanded: Set<String>
    @Bindable var model: EditorModel
    var onBind: (UUID, String, DataValue) -> Void

    private var isOpen: Bool { expanded.contains(path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if isOpen {
                ForEach(children, id: \.path) { child in
                    TreeNode(label: child.label, path: child.path, value: child.value,
                             depth: depth + 1, expanded: $expanded, model: model, onBind: onBind)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 4) {
            Group {
                if value.isLeaf {
                    Color.clear.frame(width: 10)
                } else {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Palette.textDim)
                        .frame(width: 10)
                }
            }

            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(value.isLeaf ? Palette.text : Palette.textDim)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(value.isLeaf ? value.stringValue : value.typeLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(value.isLeaf ? Palette.accent : Palette.textDim.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, CGFloat(depth) * 11 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if value.isLeaf {
                guard let element = model.focusedElement else { return }
                onBind(element.id, path, value)
            } else {
                if isOpen { expanded.remove(path) } else { expanded.insert(path) }
            }
        }
        // Dragging carries the path; dropping is handled by the canvas.
        .draggable(path) {
            Text(path.isEmpty ? label : path)
                .font(.system(size: 10, design: .monospaced))
                .padding(6)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
        }
        .background(hoverBackground)
    }

    private var hoverBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(value.isLeaf && model.focusedElement != nil
                  ? Palette.accent.opacity(0.06)
                  : .clear)
            .padding(.horizontal, 4)
    }

    private var children: [(label: String, path: String, value: DataValue)] {
        switch value {
        case .object(let pairs):
            return pairs.map { (label: $0.key,
                                path: path.isEmpty ? $0.key : "\(path).\($0.key)",
                                value: $0.value) }
        case .array(let items):
            // Long arrays are truncated in the browser, not in the data: an
            // endpoint returning 500 hourly readings should not produce 500
            // rows nobody will scroll through.
            return items.prefix(24).enumerated().map { index, item in
                (label: "[\(index)]", path: "\(path)[\(index)]", value: item)
            }
        default:
            return []
        }
    }
}
