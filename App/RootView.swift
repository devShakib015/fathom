import SwiftUI
import WidgetKit

struct RootView: View {
    @Environment(Library.self) private var library
    @State private var data = ResolvedData()
    @State private var isResolving = false

    var body: some View {
        @Bindable var library = library

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
        } detail: {
            detail
        }
        .background(Palette.background)
        .task { await refresh(); await library.exportAllPreviews() }
        .onChange(of: library.selection) { _, _ in Task { await refresh() } }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var library = library

        return List(selection: $library.selection) {
            Section("Widgets") {
                ForEach(library.documents) { doc in
                    DocumentRow(doc: doc, isActive: library.activeID(for: doc.family) == doc.id)
                        .tag(doc.id)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { containerFooter }
    }

    /// The shared container path, in the window rather than in a log.
    ///
    /// This is the single most useful thing to be able to see: if the App
    /// Group entitlement did not survive signing, every widget on the machine
    /// silently renders its fallbacks and nothing anywhere reports an error.
    private var containerFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: 6) {
                Image(systemName: AppGroup.container == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(AppGroup.container == nil ? .orange : Palette.accent)
                Text(AppGroup.container == nil ? "Shared container missing" : "Shared container ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textDim)
            }
            Text(library.containerPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.textDim.opacity(0.7))
                .lineLimit(2)
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
        if let doc = library.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header(doc)
                    WidgetStage(doc: doc, data: data)
                    FactsPanel(doc: doc, data: data, isResolving: isResolving)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.background)
        } else {
            ContentUnavailableView("No widgets yet",
                                   systemImage: "square.dashed",
                                   description: Text("Fathom could not read the shared container."))
                .background(Palette.background)
        }
    }

    private func header(_ doc: WidgetDoc) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(doc.family.displayName) · \(doc.elements.count) elements · refreshes every \(Int(doc.minimumRefresh)) s")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textDim)
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                library.makeActive(doc)
            } label: {
                Label("Show on desktop", systemImage: "menubar.dock.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
        }
    }

    private func refresh() async {
        guard let doc = library.selected else { return }
        isResolving = true
        data = await DataResolver.resolve(doc)
        isResolving = false
        PreviewExporter.write(doc, data: data)
    }
}

private struct DocumentRow: View {
    let doc: WidgetDoc
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: familySymbol)
                .foregroundStyle(Palette.textDim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.name)
                    .font(.system(size: 12, weight: .medium))
                Text(doc.family.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
            }
            Spacer(minLength: 4)
            if isActive {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                    .help("Currently placed for this size")
            }
        }
        .padding(.vertical, 2)
    }

    private var familySymbol: String {
        switch doc.family {
        case .small: "square"
        case .medium: "rectangle"
        case .large: "rectangle.portrait"
        case .extraLarge: "rectangle.split.2x1"
        }
    }
}
