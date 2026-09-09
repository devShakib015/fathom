import SwiftUI

/// One chooser for every place a design can appear, instead of five stacked
/// panels of explanation.
///
/// Each surface arrived as its own block with its own paragraph, which was
/// reasonable when there was one of them and unusable at five: the Design tab
/// became a column taller than the screen, and the last surface added sat below
/// the fold where it could not be reached at all. Worse, the column answered
/// the question nobody asks — "what could this design do?" — while burying the
/// one everybody asks, which is where it is showing right now.
///
/// So: a row of five, lit when this design is live there, and the settings for
/// exactly one of them underneath.
struct SurfacesSection: View {
    @Environment(OverlayController.self) private var overlays
    @Environment(MenuBarController.self) private var menuBar
    @Environment(IslandController.self) private var island
    @Environment(SummonController.self) private var summon
    @Environment(WallpaperController.self) private var wallpaper
    let doc: WidgetDoc

    @State private var showing: Surface?

    enum Surface: String, CaseIterable, Identifiable {
        case overlay, menuBar, islandStrip, summon, wallpaper

        var id: String { rawValue }

        var label: String {
            switch self {
            case .overlay: "Overlay"
            case .menuBar: "Menu bar"
            case .islandStrip: "Island"
            case .summon: "Summon"
            case .wallpaper: "Wallpaper"
            }
        }

        var symbol: String {
            switch self {
            case .overlay: "rectangle.on.rectangle"
            case .menuBar: "menubar.rectangle"
            case .islandStrip: "capsule.fill"
            case .summon: "command"
            case .wallpaper: "photo.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection(title: "Shows on") {
                // Wraps rather than compresses: five chips do not fit one
                // inspector row, and an HStack would break the labels mid-word.
                WrapLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(Surface.allCases) { surface in
                        chip(surface)
                    }
                }

                if showing == nil {
                    Text(liveSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let showing {
                Divider().overlay(Palette.hairline)
                detail(for: showing)
            }
        }
    }

    @ViewBuilder private func detail(for surface: Surface) -> some View {
        switch surface {
        case .overlay: OverlaysSection(doc: doc)
        case .menuBar: MenuBarSection(doc: doc)
        case .islandStrip: IslandSection(doc: doc)
        case .summon: SummonSection(doc: doc)
        case .wallpaper: WallpaperSection(doc: doc)
        }
    }

    private func chip(_ surface: Surface) -> some View {
        let live = isLive(surface)
        let open = showing == surface
        return Button {
            showing = open ? nil : surface
        } label: {
            HStack(spacing: 4) {
                Image(systemName: surface.symbol).font(.system(size: 9))
                Text(surface.label).font(.system(size: 10, weight: .medium))
            }
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(open ? Palette.accent.opacity(0.22)
                               : live ? Palette.accent.opacity(0.12)
                                      : Palette.hairline.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(open ? Palette.accent.opacity(0.55) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(live || open ? Palette.accent : Palette.textDim)
        .help(live ? "\(surface.label) — showing now" : surface.label)
    }

    private func isLive(_ surface: Surface) -> Bool {
        switch surface {
        case .overlay:
            overlays.overlays.contains { $0.documentID == doc.id && $0.isEnabled }
        case .menuBar:
            menuBar.items.contains { $0.documentID == doc.id && $0.isEnabled }
        case .islandStrip:
            island.island?.documentID == doc.id && island.island?.isEnabled == true
        case .summon:
            summon.summon?.documentID == doc.id && summon.summon?.isEnabled == true
        case .wallpaper:
            wallpaper.wallpaper?.documentID == doc.id && wallpaper.wallpaper?.isEnabled == true
        }
    }

    private var liveSummary: String {
        let live = Surface.allCases.filter(isLive).map(\.label)
        switch live.count {
        case 0: return "Not showing anywhere yet. Pick a surface to put it somewhere."
        case 1: return "Showing on \(live[0])."
        default: return "Showing on \(live.dropLast().joined(separator: ", ")) and \(live.last!)."
        }
    }
}
