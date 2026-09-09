import Foundation

/// A document you call up with a keystroke, and that leaves when you are done.
///
/// The fourth host, and the first one that is not always somewhere. An overlay
/// occupies desktop, the menu bar occupies the menu bar, the island occupies the
/// notch — each of them is a standing claim on screen space. A summon claims
/// nothing until asked and gives it all back afterwards, which makes it the
/// right home for the documents that are too big or too detailed to leave out:
/// a full system dashboard, a week of calendar, a wall of numbers.
///
/// It is a host rather than a family, for the same reason as `Overlay`: it
/// imposes no shape, so every one of the catalogue's entries can be summoned
/// without touching the document format, the renderer or the editor.
struct Summon: Codable, Hashable {
    var documentID: UUID
    var hotKey: HotKey
    var isEnabled: Bool
    var placement: Placement
    /// Scale applied to the document's reference size. A summoned document is
    /// read rather than glanced at, so it earns more room than a widget.
    var scale: Double
    /// Seconds between refreshes while it is on screen. Nothing refreshes while
    /// it is hidden — a panel nobody is looking at costs nothing.
    var refresh: TimeInterval
    /// Disappears when you click elsewhere or switch app. On by default: the
    /// whole point is that it goes away.
    var dismissOnBlur: Bool
    /// Dim the screen behind it, the way Spotlight does not and Mission Control
    /// does. Off by default because it is a strong effect for a small panel.
    var dimsBackground: Bool

    static let refreshFloor: TimeInterval = 1
    static let defaultRefresh: TimeInterval = 2

    init(documentID: UUID) {
        self.documentID = documentID
        self.hotKey = .default
        self.isEnabled = true
        self.placement = .centre
        self.scale = 2
        self.refresh = Summon.defaultRefresh
        self.dismissOnBlur = true
        self.dimsBackground = false
    }

    enum Placement: String, Codable, CaseIterable, Hashable {
        case centre
        case underCursor
        case topRight

        var displayName: String {
            switch self {
            case .centre: "Centre of the screen"
            case .underCursor: "Where the pointer is"
            case .topRight: "Top right"
            }
        }

        /// Which screen it should appear on.
        ///
        /// Always the one the pointer is on, for every placement. A panel
        /// summoned by a keystroke has to appear where the person's attention
        /// already is, and on a multi-display Mac the pointer is the only
        /// honest evidence of that — the "main" screen is where the menu bar
        /// lives, which may be a display they are not looking at.
        var followsPointer: Bool { true }
    }

    enum CodingKeys: String, CodingKey {
        case documentID, hotKey, isEnabled, placement, scale
        case refresh, dismissOnBlur, dimsBackground
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        hotKey = try c.decodeIfPresent(HotKey.self, forKey: .hotKey) ?? .default
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        placement = try c.decodeIfPresent(Placement.self, forKey: .placement) ?? .centre
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 2
        refresh = try c.decodeIfPresent(TimeInterval.self, forKey: .refresh) ?? Summon.defaultRefresh
        dismissOnBlur = try c.decodeIfPresent(Bool.self, forKey: .dismissOnBlur) ?? true
        dimsBackground = try c.decodeIfPresent(Bool.self, forKey: .dimsBackground) ?? false
    }
}

struct SummonStore {
    static let shared = SummonStore()

    private var url: URL? { SharedStore.container?.appendingPathComponent("summon.json") }

    func load() -> Summon? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Summon.self, from: data)
    }

    func save(_ summon: Summon?) {
        guard let url else { return }
        guard let summon else { try? FileManager.default.removeItem(at: url); return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(summon).write(to: url, options: .atomic)
    }

    func clearIfUses(_ documentID: UUID) {
        guard let summon = load(), summon.documentID == documentID else { return }
        save(nil)
    }
}
