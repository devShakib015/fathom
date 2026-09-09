import Foundation

/// A document drawn onto the desktop picture itself.
///
/// The fifth host, and the only one that is not a window. Everything else
/// Fathom draws sits *on* the desktop; this one becomes it. That buys the one
/// thing no window can have — it is behind everything, always, and costs no
/// compositing at all once written — and it costs the thing every window has:
/// it cannot move, cannot be clicked, and updates only as often as the picture
/// is rewritten.
///
/// A host, not a family, like `Overlay` and `Summon`: any document can be a
/// wallpaper, so the whole catalogue is available without touching the format.
struct Wallpaper: Codable, Hashable {
    var documentID: UUID
    var screenIndex: Int
    var isEnabled: Bool
    /// Multiplier on the document's reference size. A wallpaper is looked at
    /// from across a room, so the useful range starts well above 1.
    var scale: Double
    var position: Position
    /// Seconds between rewrites. Not free like an overlay: each one renders a
    /// screen-sized image and asks the window server to swap the desktop
    /// picture, so the floor is higher than a window's.
    var refresh: TimeInterval
    /// What fills the screen behind the design. The document's own backdrop,
    /// extended — so a gradient design gives a gradient desktop.
    var extendsBackdrop: Bool

    /// Thirty seconds. Below that the cost stops being worth it: rewriting a
    /// 6K PNG and swapping the desktop picture is not what a per-second clock
    /// should be built on — that is what an overlay is for.
    static let refreshFloor: TimeInterval = 30
    static let defaultRefresh: TimeInterval = 60

    init(documentID: UUID) {
        self.documentID = documentID
        self.screenIndex = 0
        self.isEnabled = true
        self.scale = 3
        self.position = .centre
        self.refresh = Wallpaper.defaultRefresh
        self.extendsBackdrop = true
    }

    enum Position: String, Codable, CaseIterable, Hashable {
        case centre, topLeading, topTrailing, bottomLeading, bottomTrailing

        var displayName: String {
            switch self {
            case .centre: "Centre"
            case .topLeading: "Top left"
            case .topTrailing: "Top right"
            case .bottomLeading: "Bottom left"
            case .bottomTrailing: "Bottom right"
            }
        }

        var alignment: (x: Double, y: Double) {
            switch self {
            case .centre: (0.5, 0.5)
            case .topLeading: (0.18, 0.22)
            case .topTrailing: (0.82, 0.22)
            case .bottomLeading: (0.18, 0.78)
            case .bottomTrailing: (0.82, 0.78)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case documentID, screenIndex, isEnabled, scale, position, refresh, extendsBackdrop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        screenIndex = try c.decodeIfPresent(Int.self, forKey: .screenIndex) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 3
        position = try c.decodeIfPresent(Position.self, forKey: .position) ?? .centre
        refresh = try c.decodeIfPresent(TimeInterval.self, forKey: .refresh) ?? Wallpaper.defaultRefresh
        extendsBackdrop = try c.decodeIfPresent(Bool.self, forKey: .extendsBackdrop) ?? true
    }
}

struct WallpaperStore {
    static let shared = WallpaperStore()

    private var url: URL? { SharedStore.container?.appendingPathComponent("wallpaper.json") }
    /// Where the user's own desktop picture was before Fathom touched it.
    ///
    /// Written before the first change and never overwritten while a wallpaper
    /// is active, because replacing somebody's desktop picture without being
    /// able to give it back is not a feature, it is damage.
    private var originalURL: URL? {
        SharedStore.container?.appendingPathComponent("wallpaper-original.txt")
    }

    func load() -> Wallpaper? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Wallpaper.self, from: data)
    }

    func save(_ wallpaper: Wallpaper?) {
        guard let url else { return }
        guard let wallpaper else { try? FileManager.default.removeItem(at: url); return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(wallpaper).write(to: url, options: .atomic)
    }

    /// Records the current desktop picture, but only if it can actually be
    /// given back.
    ///
    /// macOS keeps showing a wallpaper whose file has been deleted — it holds
    /// the image, not the path — so `desktopImageURL` can name a file that is
    /// not there. Recording that path anyway produces the worst outcome
    /// available: an app that offers to restore your wallpaper and then cannot,
    /// after it has already replaced it. Measured the hard way on 9 Sep 2026.
    ///
    /// Returns whether the original is recoverable, so the caller can warn
    /// *before* changing anything rather than apologise afterwards.
    @discardableResult
    func rememberOriginal(_ path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        guard let originalURL else { return false }
        if !FileManager.default.fileExists(atPath: originalURL.path) {
            try? Data(path.path.utf8).write(to: originalURL, options: .atomic)
        }
        return true
    }

    /// The remembered original, only if the file is still on disk. A path
    /// whose file has since gone is not an original, it is a false promise.
    func original() -> URL? {
        guard let originalURL, let data = try? Data(contentsOf: originalURL),
              let path = String(data: data, encoding: .utf8), !path.isEmpty,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    func forgetOriginal() {
        guard let originalURL else { return }
        try? FileManager.default.removeItem(at: originalURL)
    }

    func clearIfUses(_ documentID: UUID) {
        guard let wallpaper = load(), wallpaper.documentID == documentID else { return }
        save(nil)
    }
}
