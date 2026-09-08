import SwiftUI

/// The catalog: every layout in every palette, browsable and duplicable.
///
/// Nothing here is stored — entries are generated from templates and themes, so
/// the catalog is always in step with the current schema and adding a palette
/// adds a hundred widgets without adding a byte to the app.
struct GalleryView: View {
    @Environment(Library.self) private var library
    var onAdd: (WidgetDoc) -> Void

    @State private var query = ""
    @State private var category: CatalogTemplate.Category?
    @State private var family: WidgetDoc.Family?
    @State private var themeFilter: String?
    @State private var preview: CatalogEntry?

    private var results: [CatalogEntry] {
        Catalog.search(query, category: category, family: family, theme: themeFilter)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            filters
            Divider().overlay(Palette.hairline)
            grid
        }
        .background(Palette.background)
        .sheet(item: $preview) { entry in
            CatalogPreview(entry: entry) { doc in
                onAdd(doc)
                preview = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Catalog")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                // The arithmetic, not just the total. A number nobody can
                // account for is a number nobody should believe.
                Text("\(Catalog.count) widgets — \(Catalog.composition)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
            }
            Spacer()
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(label: "All", symbol: "square.grid.2x2", isOn: category == nil) {
                    category = nil
                }
                ForEach(CatalogTemplate.Category.allCases, id: \.self) { option in
                    Chip(label: option.rawValue, symbol: option.symbol,
                         isOn: category == option) {
                        category = category == option ? nil : option
                    }
                }

                Divider().frame(height: 16).padding(.horizontal, 4)

                ForEach(WidgetDoc.Family.allCases, id: \.self) { option in
                    Chip(label: option.displayName, symbol: nil, isOn: family == option) {
                        family = family == option ? nil : option
                    }
                }

                Divider().frame(height: 16).padding(.horizontal, 4)

                Menu {
                    Button("Every palette") { themeFilter = nil }
                    Divider()
                    ForEach(Theme.all) { theme in
                        Button(theme.name) { themeFilter = theme.id }
                    }
                } label: {
                    Label(themeFilter.map { Theme.named($0).name } ?? "Palette",
                          systemImage: "paintpalette")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 130)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
        }
    }

    private var grid: some View {
        ScrollView {
            if results.isEmpty {
                ContentUnavailableView("Nothing matches",
                                       systemImage: "magnifyingglass",
                                       description: Text("Try a different word, or clear the filters."))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)],
                          spacing: 18) {
                    ForEach(results) { entry in
                        CatalogCell(entry: entry) { preview = entry }
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct Chip: View {
    let label: String
    let symbol: String?
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
                Text(label).font(.system(size: 11, weight: isOn ? .semibold : .regular))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isOn ? Palette.accent.opacity(0.18) : Palette.surface.opacity(0.6),
                        in: Capsule())
            .overlay(Capsule().stroke(isOn ? Palette.accent.opacity(0.5) : Palette.hairline,
                                      lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Palette.accent : Palette.textDim)
    }
}

private struct CatalogCell: View {
    let entry: CatalogEntry
    var onOpen: () -> Void

    @State private var thumbnails = CatalogThumbnails.shared

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.surface.opacity(0.5))
                    if let data = thumbnails.thumbnail(for: entry), let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(10)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text("\(entry.themeName) · \(entry.family.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { thumbnails.request(entry) }
    }
}

/// A larger look before adding, with the sources it will need spelled out.
private struct CatalogPreview: View {
    let entry: CatalogEntry
    var onAdd: (WidgetDoc) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var data = ResolvedData()
    @State private var doc: WidgetDoc?

    var body: some View {
        VStack(spacing: 0) {
            if let doc {
                ZStack {
                    LinearGradient(colors: [Palette.surface, Palette.background],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    ZStack {
                        doc.background.swatch
                        WidgetCanvas(doc: doc, data: data)
                    }
                    .frame(width: doc.family.referenceSize.width,
                           height: doc.family.referenceSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius,
                                                style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                }
                .frame(height: doc.family.referenceSize.height + 90)

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text("\(entry.themeName) · \(entry.family.displayName) · \(entry.category.rawValue)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textDim)

                    if !doc.declaredHosts.isEmpty {
                        Label("Contacts \(doc.declaredHosts.joined(separator: ", "))",
                              systemImage: "globe")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accentAlt)
                    }
                    if entry.needs.contains(.calendar) || entry.needs.contains(.reminders) {
                        Label("Needs permission to read your \(entry.needs.contains(.calendar) ? "calendar" : "reminders")",
                              systemImage: "lock")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accentAlt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider().overlay(Palette.hairline)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add to my widgets") {
                    if let doc { onAdd(doc) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
            .padding(16)
        }
        .frame(width: 520)
        .background(Palette.background)
        .task {
            let built = entry.document()
            doc = built
            data = await DataResolver.resolve(built)
        }
    }
}
