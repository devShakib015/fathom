import SwiftUI
import EventKit

/// The data sources panel: add a source, fetch it, and browse what came back.
///
/// This is where the reload finding cashes out. A widget bound to a live source
/// on a 64-second floor is a different category of object from anything an iOS
/// widget builder can offer, and none of that is visible until somebody can
/// point it at their own data and see their own numbers.
struct SourcesInspector: View {
    @Bindable var model: EditorModel
    /// Binds a field to an element: element, source, key path, sample value.
    var onBind: (UUID, UUID, String, DataValue) -> Void

    @State private var newURL: String = ""
    @State private var browsing: UUID?
    @State private var permissionDenied: DataSource.Kind?

    private var browsedSource: DataSource? {
        model.doc.sources.first { $0.id == browsing } ?? model.doc.sources.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection(title: "Data sources") {
                ForEach(model.doc.sources) { source in
                    SourceRow(model: model, source: source,
                              isBrowsing: browsedSource?.id == source.id) {
                        browsing = source.id
                    }
                }
                addControls
                if let denied = permissionDenied {
                    Label("macOS refused \(denied.displayName.lowercased()) access. Grant it in System Settings ▸ Privacy & Security.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let source = browsedSource {
                Divider().overlay(Palette.hairline)
                TreeBrowser(model: model, source: source, onBind: onBind)
            }
        }
    }

    // MARK: - Adding

    private var addControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("https://api.example.com/data.json", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit(addEndpoint)
                Button("Add", action: addEndpoint)
                    .disabled(URL(string: newURL)?.host == nil)
            }

            HStack(spacing: 6) {
                ForEach(DataSource.Kind.allCases.filter { $0 != .json }, id: \.self) { kind in
                    Button {
                        add(kind)
                    } label: {
                        Label(kind.displayName, systemImage: kind.symbol)
                            .font(.system(size: 10))
                    }
                    .disabled(model.doc.sources.contains { $0.kind == kind })
                }
            }

            Text("Endpoints are fetched only when you ask and when a widget using them reloads. Calendar and reminders are read on this Mac and never sent anywhere.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addEndpoint() {
        let trimmed = newURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let host = url.host else { return }
        let source = DataSource(name: host, kind: .json, url: trimmed)
        model.addSource(source)
        browsing = source.id
        newURL = ""
        Task { await model.resolve() }
    }

    /// Asks for permission before adding, not after.
    ///
    /// A source that appears in the list and then reports "no access" looks
    /// like a bug; asking first means the only sources on screen are ones that
    /// can actually be read.
    private func add(_ kind: DataSource.Kind) {
        Task { @MainActor in
            permissionDenied = nil
            if kind.needsPermission {
                let entity: EKEntityType = kind == .calendar ? .event : .reminder
                let granted = await CalendarSource.requestAccess(to: entity)
                guard granted else { permissionDenied = kind; return }
            }
            let source = DataSource(name: kind.displayName, kind: kind)
            model.addSource(source)
            browsing = source.id
            await model.resolve()
        }
    }
}

private struct SourceRow: View {
    @Bindable var model: EditorModel
    let source: DataSource
    let isBrowsing: Bool
    var onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: source.kind.symbol)
                .foregroundStyle(isBrowsing ? Palette.accent : Palette.textDim)
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
            if source.kind != .system {
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(isBrowsing ? Palette.accent.opacity(0.09) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }

    private var status: String {
        if let failure = model.data.failures[source.id] { return failure }
        switch source.kind {
        case .system, .calendar, .reminders:
            return "Read on this Mac, never sent anywhere"
        case .json:
            if model.data.trees[source.id] != nil {
                return model.data.isStale ? "Cached" : source.host ?? ""
            }
            return source.host ?? "No URL"
        }
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
    var onBind: (UUID, UUID, String, DataValue) -> Void

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

                if source.kind == .json { SuggestFieldsRow(root: root) }

                VStack(alignment: .leading, spacing: 0) {
                    TreeNode(label: source.name, path: "", value: root, depth: 0,
                             expanded: $expanded, model: model, sourceID: source.id, onBind: onBind)
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
    let sourceID: UUID
    var onBind: (UUID, UUID, String, DataValue) -> Void

    private var isOpen: Bool { expanded.contains(path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if isOpen {
                ForEach(children, id: \.path) { child in
                    TreeNode(label: child.label, path: child.path, value: child.value,
                             depth: depth + 1, expanded: $expanded, model: model,
                             sourceID: sourceID, onBind: onBind)
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
                onBind(element.id, sourceID, path, value)
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


/// Asks the on-device model which of an endpoint's fields are worth showing.
///
/// An unfamiliar API can return two hundred leaves, most of them identifiers,
/// timing metadata and internal codes. Picking the six a person would glance at
/// is exactly the kind of judgement a small model is good at, and getting it
/// wrong costs nothing — these are suggestions next to the tree, not changes to
/// the document.
private struct SuggestFieldsRow: View {
    let root: DataValue

    @State private var suggestions: [Intelligence.FieldSuggestion] = []
    @State private var isThinking = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    suggest()
                } label: {
                    Label(isThinking ? "Reading the endpoint…" : "Which fields are useful?",
                          systemImage: "sparkles")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Intelligence.status.isReady ? Palette.accent : Palette.textDim)
                .disabled(!Intelligence.status.isReady || isThinking)
                if isThinking { ProgressView().controlSize(.mini) }
            }

            if let problem {
                Text(problem)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(suggestions, id: \.path) { suggestion in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.textDim)
                    Text(suggestion.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text(suggestion.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }

    private func suggest() {
        guard !isThinking else { return }
        isThinking = true
        problem = nil
        let leaves = root.leaves()
        Task { @MainActor in
            defer { isThinking = false }
            do {
                // Only paths that actually exist survive: a suggested field
                // that resolves to nothing would be worse than no suggestion.
                let proposed = try await Intelligence.suggestFields(from: leaves)
                let known = Set(leaves.map(\.path))
                suggestions = proposed.filter { known.contains($0.path) }
                if suggestions.isEmpty { problem = "Nothing it suggested matched a real field." }
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
