import Foundation

/// A palette a layout can be dressed in.
///
/// Themes are the multiplier that turns a manageable number of designed
/// layouts into a large catalog. That only works if each one is a genuinely
/// different look rather than a hue rotation — a catalog padded with
/// near-duplicates is worse than a small one, because every entry costs the
/// person scrolling past it.
struct Theme: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let accent: String
    let accentAlt: String
    let text: String
    let dim: String
    /// nil means Liquid Glass — the desktop shows through. A theme with
    /// colours here paints its own ground instead.
    let surface: String?
    let surfaceEnd: String?

    var background: Background {
        guard let surface else { return Background(kind: .glass) }
        if let surfaceEnd {
            return Background(kind: .gradient,
                              color: ColorSpec(surface),
                              gradientEnd: ColorSpec(surfaceEnd),
                              angle: 145)
        }
        return Background(kind: .color, color: ColorSpec(surface))
    }

    var accentSpec: ColorSpec { ColorSpec(accent) }
    var accentAltSpec: ColorSpec { ColorSpec(accentAlt) }
    var textSpec: ColorSpec { ColorSpec(text) }
    var dimSpec: ColorSpec { ColorSpec(dim) }
    func accent(_ opacity: Double) -> ColorSpec { ColorSpec(accent, opacity: opacity) }
    func dim(_ opacity: Double) -> ColorSpec { ColorSpec(dim, opacity: opacity) }

    static let all: [Theme] = [
        // The house palette first: everything else is measured against it.
        Theme(id: "mint", name: "Mint", accent: "#3DDC97", accentAlt: "#4FC3E8",
              text: "#E8F2EE", dim: "#9BB3AB", surface: nil, surfaceEnd: nil),
        Theme(id: "mint-deep", name: "Mint on ink", accent: "#3DDC97", accentAlt: "#4FC3E8",
              text: "#E8F2EE", dim: "#8AA49C", surface: "#101E1A", surfaceEnd: "#060B0A"),
        Theme(id: "graphite", name: "Graphite", accent: "#C9D4D0", accentAlt: "#8FA09B",
              text: "#F2F5F4", dim: "#8B9793", surface: "#1C1F1E", surfaceEnd: "#0E1010"),
        Theme(id: "mono", name: "Mono", accent: "#FFFFFF", accentAlt: "#BFBFBF",
              text: "#FFFFFF", dim: "#8E8E8E", surface: "#000000", surfaceEnd: nil),
        Theme(id: "ember", name: "Ember", accent: "#FF8A4C", accentAlt: "#FFC24B",
              text: "#FFF1E6", dim: "#B8907A", surface: "#231510", surfaceEnd: "#120A07"),
        Theme(id: "cobalt", name: "Cobalt", accent: "#5B8DEF", accentAlt: "#63D2FF",
              text: "#E9EFFB", dim: "#93A4C4", surface: "#121A2B", surfaceEnd: "#080C15"),
        Theme(id: "orchid", name: "Orchid", accent: "#C084FC", accentAlt: "#F472B6",
              text: "#F3E9FB", dim: "#A98FBC", surface: "#1D1428", surfaceEnd: "#0E0914"),
        Theme(id: "rose", name: "Rose", accent: "#FB7185", accentAlt: "#FDA4AF",
              text: "#FDECEF", dim: "#C08A93", surface: "#26141A", surfaceEnd: "#140A0D"),
        Theme(id: "forest", name: "Forest", accent: "#4ADE80", accentAlt: "#A3E635",
              text: "#ECFDF3", dim: "#8FB79C", surface: "#0F1E15", surfaceEnd: "#07100B"),
        Theme(id: "ice", name: "Ice", accent: "#67E8F9", accentAlt: "#A5F3FC",
              text: "#ECFEFF", dim: "#8FB6BD", surface: "#0D1B1F", surfaceEnd: "#060E10"),
        Theme(id: "citrus", name: "Citrus", accent: "#FACC15", accentAlt: "#A3E635",
              text: "#FEFCE8", dim: "#B7AC7A", surface: "#1E1B0C", surfaceEnd: "#100E06"),
        Theme(id: "slate", name: "Slate", accent: "#94A3B8", accentAlt: "#CBD5E1",
              text: "#F1F5F9", dim: "#7A8899", surface: "#161C24", surfaceEnd: "#0B0E13"),
        Theme(id: "sand", name: "Sand", accent: "#E7C69B", accentAlt: "#D9A066",
              text: "#F7EFE3", dim: "#B3A18B", surface: "#221C15", surfaceEnd: "#120E0A"),
        Theme(id: "teal", name: "Teal", accent: "#2DD4BF", accentAlt: "#38BDF8",
              text: "#E6FFFB", dim: "#87A9A4", surface: "#0C1E1D", surfaceEnd: "#061110"),
        Theme(id: "violet-glass", name: "Violet glass", accent: "#A78BFA", accentAlt: "#818CF8",
              text: "#EFEAFF", dim: "#A196C4", surface: nil, surfaceEnd: nil),
        Theme(id: "amber-glass", name: "Amber glass", accent: "#FBBF24", accentAlt: "#FB923C",
              text: "#FFF7E6", dim: "#BCA980", surface: nil, surfaceEnd: nil),
        Theme(id: "crimson", name: "Crimson", accent: "#EF4444", accentAlt: "#F97316",
              text: "#FEECEC", dim: "#B98A8A", surface: "#231011", surfaceEnd: "#130809"),
        Theme(id: "lagoon", name: "Lagoon", accent: "#22D3EE", accentAlt: "#34D399",
              text: "#E8FEFF", dim: "#84AAB2", surface: "#08191E", surfaceEnd: "#040D10"),
        Theme(id: "paper", name: "Paper", accent: "#111827", accentAlt: "#4B5563",
              text: "#111827", dim: "#6B7280", surface: "#F5F3EE", surfaceEnd: "#E7E3DA"),
        Theme(id: "daylight", name: "Daylight", accent: "#2563EB", accentAlt: "#0EA5E9",
              text: "#0F172A", dim: "#64748B", surface: "#FFFFFF", surfaceEnd: "#E2E8F0"),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }
}
