import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(OverlayController.self) private var overlays
    @Environment(RuleEngine.self) private var rules
    @Environment(MenuBarController.self) private var menuBar
    @Environment(IslandController.self) private var island
    @Environment(SummonController.self) private var summon
    @Environment(WallpaperController.self) private var wallpaper
    @State private var editor: EditorModel?
    @State private var destination: Destination = .editor
    @State private var importing: DocumentTransfer.Inspection?

    /// What the detail pane is showing. Rules are not documents, so they get a
    /// destination rather than being wedged into the widget list.
    enum Destination { case editor, gallery, rules }

    var body: some View {
        @Bindable var library = library

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } detail: {
            switch destination {
            case .gallery:
                GalleryView { doc in
                    library.add(doc)
                    destination = .editor
                }
            case .rules:
                RulesView()
            case .editor:
                detail
            }
        }
        .background(Palette.background)
        .sheet(item: $importing) { inspection in
            ImportSheet(inspection: inspection) { doc in
                library.add(doc)
                destination = .editor
            }
        }
        .onChange(of: library.selection, initial: true) { _, _ in
            openSelected()
            if library.selection != nil { destination = .editor }
        }
        // Refresh every document's thumbnail and resolved values once at
        // launch, not just the selected one — the library grid will want them,
        // and it is the only way to see that a document nobody has opened
        // still resolves.
        .task { await library.exportAllPreviews() }
        // An edit has to reach the overlays too, or the canvas and the screen
        // disagree until the next refresh.
        .onChange(of: editor?.doc) { _, new in
            if let new {
                overlays.documentChanged(new.id)
                menuBar.documentChanged(new.id)
                island.documentChanged(new.id)
                summon.documentChanged(new.id)
                wallpaper.documentChanged(new.id)
            }
        }
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
                // Grouped by what each design *is*, because family decides
                // where it can go. A flat list of ten made a menu bar strip and
                // a large dashboard look like the same kind of thing.
                ForEach(DocumentGroup.allCases) { group in
                    let documents = library.documents.filter { group.contains($0.family) }
                    if !documents.isEmpty {
                        Section {
                            ForEach(documents) { doc in
                                DocumentRow(doc: doc, placement: placement(of: doc))
                                    .tag(doc.id)
                                    .contextMenu { menu(for: doc) }
                            }
                        } header: {
                            Text(group.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.textDim)
                                .textCase(.uppercase)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().overlay(Palette.hairline)
            galleryButton
            rulesButton
            newButton
            containerFooter
        }
    }

    @ViewBuilder private func menu(for doc: WidgetDoc) -> some View {
        Button("Duplicate") { library.duplicate(doc) }
        Button("Share…") { Sharing.export(doc) }
        Button("Show on desktop") { library.makeActive(doc) }
        if library.slot(holding: doc) != nil {
            Button("Take off the desktop") { library.remove(doc) }
        }
        Divider()
        Button("Delete", role: .destructive) { library.delete(doc) }
    }

    /// Where this design is live right now, across every surface.
    ///
    /// The sidebar used to answer "what is it called and what size is it",
    /// which the icon and the section header already say. The question a
    /// library of ten designs actually raises is which of them are *doing*
    /// something, and until now nothing on screen answered it.
    private func placement(of doc: WidgetDoc) -> LivePlacement? {
        if let slot = library.slot(holding: doc) {
            return LivePlacement(symbol: "display",
                             label: slot.index == 1 ? nil : "\(slot.index)",
                             help: "On the desktop in \(slot.displayName)")
        }
        if overlays.overlays.contains(where: { $0.documentID == doc.id && $0.isEnabled }) {
            return LivePlacement(symbol: "rectangle.on.rectangle", label: nil, help: "On screen as an overlay")
        }
        if menuBar.items.contains(where: { $0.documentID == doc.id && $0.isEnabled }) {
            return LivePlacement(symbol: "menubar.rectangle", label: nil, help: "In the menu bar")
        }
        if island.island?.documentID == doc.id, island.island?.isEnabled == true {
            return LivePlacement(symbol: "capsule.fill", label: nil, help: "Under the notch")
        }
        if let summonConfig = summon.summon, summonConfig.documentID == doc.id, summonConfig.isEnabled {
            return LivePlacement(symbol: "command", label: nil,
                             help: "Summoned with \(summonConfig.hotKey.displayName)")
        }
        if wallpaper.wallpaper?.documentID == doc.id, wallpaper.wallpaper?.isEnabled == true {
            return LivePlacement(symbol: "photo.fill", label: nil, help: "Drawn into the desktop picture")
        }
        return nil
    }

    /// The catalog is a destination, not a menu item — it is the on-ramp the
    /// library was always meant to be, and burying it under a plus button
    /// would make the app look like it ships three widgets.
    private var galleryButton: some View {
        Button {
            destination = destination == .gallery ? .editor : .gallery
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
            .background(destination == .gallery ? Palette.accent.opacity(0.16) : Palette.surface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(destination == .gallery ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == .gallery ? Palette.accent : Palette.text)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Rules watch data and act on it. They belong beside the catalog rather
    /// than inside a document, because a rule can watch something no widget
    /// shows.
    private var rulesButton: some View {
        Button {
            destination = destination == .rules ? .editor : .rules
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rules")
                        .font(.system(size: 11, weight: .medium))
                    Text(rulesSubtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textDim)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(destination == .rules ? Palette.accent.opacity(0.16) : Palette.surface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(destination == .rules ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == .rules ? Palette.accent : Palette.text)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var rulesSubtitle: String {
        let active = rules.rules.filter(\.isEnabled).count
        return active == 0 ? "nothing being watched"
             : active == 1 ? "1 being watched" : "\(active) being watched"
    }

    private var newButton: some View {
        Menu {
            ForEach(WidgetDoc.Family.allCases, id: \.self) { family in
                Button(family.displayName) { library.create(family: family) }
            }
            Divider()
            Button("Open a widget someone sent…") {
                importing = Sharing.chooseFile()
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
    /// Storage diagnosis, shown only when there is something to diagnose.
    ///
    /// This existed because the failure was invisible without it — an extension that
    /// resolves the shared store and is then denied it looks exactly like an
    /// extension that is working. That reasoning holds only for the failure
    /// case. When the store is fine, a line of developer output pinned to the
    /// bottom of the sidebar is telling the user something they cannot act on
    /// and did not ask, in a UI they look at every day.
    @ViewBuilder private var containerFooter: some View {
        let storage = StoreDiagnosis.current()
        if !storage.usable {
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(Palette.hairline)
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(storage.summary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
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

/// What holds a design right now, and the badge that says so.
/// Named for what it reports, and to stay clear of the editor's own `Placement`.
struct LivePlacement {
    let symbol: String
    /// Only when there is more than one of something — the slot number.
    let label: String?
    let help: String
}

/// The families, grouped the way a person thinks about them.
enum DocumentGroup: String, CaseIterable, Identifiable {
    case widgets, menuBar, island

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widgets: "Widgets"
        case .menuBar: "Menu bar"
        case .island: "Island"
        }
    }

    func contains(_ family: WidgetDoc.Family) -> Bool {
        switch self {
        case .widgets: family.widgetFamily != nil
        case .menuBar: family == .menuBar
        case .island: family == .island
        }
    }
}

private struct DocumentRow: View {
    let doc: WidgetDoc
    let placement: LivePlacement?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: familySymbol)
                .font(.system(size: 11))
                .foregroundStyle(placement == nil ? Palette.textDim : Palette.accent)
                .frame(width: 16)

            // One line, at a contrast you can actually read. The size used to
            // sit underneath every name in grey, doubling the height of every
            // row to repeat what the icon and the section header both said.
            Text(doc.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.text)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let placement {
                HStack(spacing: 2) {
                    Image(systemName: placement.symbol).font(.system(size: 9))
                    if let label = placement.label {
                        Text(label).font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(Palette.accent)
                .help(placement.help)
            } else if doc.family.widgetFamily != nil {
                // Size only where it distinguishes anything: inside Widgets.
                // Abbreviated, because the full word costs a third of the row
                // to say what the icon beside the name already shows.
                Text(sizeLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textDim.opacity(0.8))
                    .help(doc.family.displayName)
            }
        }
        .padding(.vertical, 1)
    }

    private var sizeLabel: String {
        switch doc.family {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        default: ""
        }
    }

    private var familySymbol: String {
        switch doc.family {
        case .small: "square"
        case .medium: "rectangle"
        case .large: "square.grid.2x2"
        case .extraLarge: "rectangle.split.2x1"
        case .menuBar: "menubar.rectangle"
        case .island: "capsule"
        }
    }
}

