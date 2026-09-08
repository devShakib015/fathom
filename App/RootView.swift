import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(Library.self) private var library
    @State private var editor: EditorModel?
    @State private var showingGallery = false

    var body: some View {
        @Bindable var library = library

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } detail: {
            if showingGallery {
                GalleryView { doc in
                    library.add(doc)
                    showingGallery = false
                }
            } else {
                detail
            }
        }
        .background(Palette.background)
        .onChange(of: library.selection, initial: true) { _, _ in
            openSelected()
            if library.selection != nil { showingGallery = false }
        }
        // Refresh every document's thumbnail and resolved values once at
        // launch, not just the selected one — the library grid will want them,
        // and it is the only way to see that a document nobody has opened
        // still resolves.
        .task { await library.exportAllPreviews() }
    }

    /// One editing session per document. Rebuilt on selection so undo history
    /// belongs to the document it was made in rather than leaking between them.
    private func openSelected() {
        guard let doc = library.selected else { editor = nil; return }
        if editor?.doc.id != doc.id { editor = EditorModel(doc: doc) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var library = library

        return VStack(spacing: 0) {
            List(selection: $library.selection) {
                Section("Widgets") {
                    ForEach(library.documents) { doc in
                        DocumentRow(doc: doc, slot: library.slot(holding: doc))
                            .tag(doc.id)
                            .contextMenu {
                                Button("Duplicate") { library.duplicate(doc) }
                                Button("Show on desktop") { library.makeActive(doc) }
                                if library.slot(holding: doc) != nil {
                                    Button("Take off the desktop") { library.remove(doc) }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { library.delete(doc) }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().overlay(Palette.hairline)
            galleryButton
            newButton
            containerFooter
        }
    }

    /// The catalog is a destination, not a menu item — it is the on-ramp the
    /// library was always meant to be, and burying it under a plus button
    /// would make the app look like it ships three widgets.
    private var galleryButton: some View {
        Button {
            showingGallery.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Browse the catalog")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(Catalog.count) ready to use")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textDim)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(showingGallery ? Palette.accent.opacity(0.16) : Palette.surface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(showingGallery ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(showingGallery ? Palette.accent : Palette.text)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var newButton: some View {
        Menu {
            ForEach(WidgetDoc.Family.allCases, id: \.self) { family in
                Button(family.displayName) { library.create(family: family) }
            }
        } label: {
            Label("New widget", systemImage: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Whether the shared store is genuinely usable, not merely resolvable.
    /// If this ever says otherwise, every widget on the machine is rendering
    /// fallbacks and nothing else on the system will mention it.
    private var containerFooter: some View {
        let storage = StoreDiagnosis.current()
        return VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: 6) {
                Image(systemName: storage.usable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(storage.usable ? Palette.accent : .orange)
                Text(storage.summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
            }
            Text(storage.containerPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.textDim.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let editor {
            VStack(spacing: 0) {
                header(editor)
                Divider().overlay(Palette.hairline)
                EditorView(model: editor)
            }
            .background(Palette.background)
            // Publishes the open document to the menu bar. Scene-scoped, so
            // Delete and Select All work without the canvas having to win a
            // focus fight with every text field in the inspector.
            .focusedSceneValue(\.editor, editor)
        } else {
            ContentUnavailableView("No widget selected",
                                   systemImage: "square.dashed",
                                   description: Text("Pick one on the left, or make a new one."))
                .background(Palette.background)
        }
    }

    private func header(_ editor: EditorModel) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.doc.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(subtitle(editor))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
            }
            Spacer()
            if editor.isResolving { ProgressView().controlSize(.small) }
            Button { Task { await editor.resolve() } } label: {
                Label("Refresh data", systemImage: "arrow.clockwise")
            }
            // A menu rather than a button, because a size can hold several
            // designs at once and "which one of the three" is the question the
            // moment there is more than one.
            Menu {
                ForEach(WidgetSlot.all(for: editor.doc.family)) { slot in
                    Button {
                        library.makeActive(editor.doc, slot: slot)
                        editor.pushToDesktop()
                    } label: {
                        let occupant = library.occupant(of: slot)
                        if occupant?.id == editor.doc.id {
                            Label("\(slot.displayName) — this widget", systemImage: "checkmark")
                        } else if let occupant {
                            Text("\(slot.displayName) — replace “\(occupant.name)”")
                        } else {
                            Text("\(slot.displayName) — empty")
                        }
                    }
                }
                if library.slot(holding: editor.doc) != nil {
                    Divider()
                    Button("Take off the desktop") { library.remove(editor.doc) }
                }
            } label: {
                Label(slotLabel(editor), systemImage: "menubar.dock.rectangle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 190)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func slotLabel(_ editor: EditorModel) -> String {
        if let slot = library.slot(holding: editor.doc) {
            return "On the desktop · \(slot.displayName)"
        }
        return "Show on desktop"
    }

    private func subtitle(_ editor: EditorModel) -> String {
        let hosts = editor.doc.declaredHosts
        let network = hosts.isEmpty ? "no network" : hosts.joined(separator: ", ")
        return "\(editor.doc.family.displayName) · \(editor.doc.elements.count) elements · \(network)"
    }
}

private struct DocumentRow: View {
    let doc: WidgetDoc
    let slot: WidgetSlot?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: familySymbol)
                .foregroundStyle(Palette.textDim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(doc.family.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
            }
            Spacer(minLength: 4)
            if let slot {
                // The slot number, not just a dot: with several widgets of one
                // size on the desktop, which is which is the only useful thing
                // this indicator can say.
                Text(slot.index == 1 ? "●" : "\(slot.index)")
                    .font(.system(size: slot.index == 1 ? 8 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 12, height: 12)
                    .background(slot.index == 1 ? .clear : Palette.accent.opacity(0.16), in: Circle())
                    .help("On the desktop in \(slot.displayName)")
            }
        }
        .padding(.vertical, 2)
    }

    private var familySymbol: String {
        switch doc.family {
        case .small: "square"
        case .medium: "rectangle"
        case .large: "square.grid.2x2"
        case .extraLarge: "rectangle.split.2x1"
        }
    }
}
