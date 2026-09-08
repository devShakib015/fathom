import Foundation

/// A document shown in a window Fathom owns, rather than one WidgetKit owns.
///
/// **An overlay is a host, not a family.** It references any document and gives
/// it a size and a place on screen, so every one of the catalog's entries can
/// become an overlay without a single change to the document format, the
/// renderer, the editor or the catalog. Adding a family case would have rippled
/// through every exhaustive switch in the project to buy nothing.
///
/// What it buys instead is everything WidgetKit refuses:
///
/// - No sixty-four second floor. Nothing is asking WidgetKit for a timeline, so
///   the interval is whatever the overlay says. **The measured floor is a fact
///   about WidgetKit and does not apply here**, and copy must not pretend
///   otherwise.
/// - No slots, no families, no re-adding after a rebuild.
/// - Any size, anywhere, on any display.
/// - Interaction, eventually — the thing WidgetKit made impossible.
struct Overlay: Codable, Identifiable, Hashable {
    var id: UUID
    var documentID: UUID
    /// Size in points. Defaults to the document's own reference size, but an
    /// overlay is free-form and can be any shape the document tolerates.
    var width: Double
    var height: Double
    /// Position as a fraction of the screen's visible frame, measured from the
    /// top-left. Stored as a fraction so an overlay lands in the same place
    /// after a resolution change or a display swap, rather than off-screen.
    var x: Double
    var y: Double
    /// Which screen, by index in `NSScreen.screens`. Falls back to the main
    /// screen when that display is gone.
    var screenIndex: Int
    var level: Level
    /// Passes clicks through to whatever is underneath. Off by default: an
    /// overlay you cannot drag is one you cannot put anywhere.
    var clickThrough: Bool
    var opacity: Double
    /// Seconds between refreshes. Free of the widget floor, but not free of
    /// sense — see `refreshFloor`.
    var refresh: TimeInterval
    var isEnabled: Bool

    /// One second is the fastest anything a person reads should move, and it is
    /// already sixty times what WidgetKit allows. Below that is a battery
    /// complaint rather than a feature.
    static let refreshFloor: TimeInterval = 1
    static let defaultRefresh: TimeInterval = 5

    enum Level: String, Codable, CaseIterable, Hashable {
        /// Above the wallpaper, below everything else. Furniture on the
        /// desktop: visible when windows are out of the way, never in the way.
        case desktop
        /// Above ordinary windows. For a clock or a countdown you want to keep
        /// no matter what you are doing.
        case floating

        var displayName: String {
            switch self {
            case .desktop: "On the desktop"
            case .floating: "Always in front"
            }
        }

        var explanation: String {
            switch self {
            case .desktop: "Sits above the wallpaper and behind your windows."
            case .floating: "Stays above everything, including full-screen apps."
            }
        }
    }

    init(documentID: UUID, size: CGSize, refresh: TimeInterval = Overlay.defaultRefresh) {
        self.id = UUID()
        self.documentID = documentID
        self.width = size.width
        self.height = size.height
        // Placed a little in from the top-right, which is where a first widget
        // belongs on almost every desktop and out of the way of icons.
        self.x = 0.72
        self.y = 0.08
        self.screenIndex = 0
        self.level = .desktop
        self.clickThrough = false
        self.opacity = 1
        self.refresh = max(refresh, Overlay.refreshFloor)
        self.isEnabled = true
    }

    var size: CGSize { CGSize(width: width, height: height) }

    /// Older overlay files predate any field added later.
    enum CodingKeys: String, CodingKey {
        case id, documentID, width, height, x, y, screenIndex, level, clickThrough, opacity, refresh, isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        screenIndex = try c.decodeIfPresent(Int.self, forKey: .screenIndex) ?? 0
        level = try c.decodeIfPresent(Level.self, forKey: .level) ?? .desktop
        clickThrough = try c.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? false
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        refresh = max(try c.decodeIfPresent(TimeInterval.self, forKey: .refresh) ?? Overlay.defaultRefresh,
                      Overlay.refreshFloor)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// Overlays on disk, beside the documents they show.
///
/// The widget extension never reads this file — overlays are the app's own
/// surface, and nothing about them should reach a process that has no business
/// drawing windows.
struct OverlayStore {
    static let shared = OverlayStore()

    private var url: URL? {
        SharedStore.container?.appendingPathComponent("overlays.json")
    }

    func all() -> [Overlay] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Overlay].self, from: data)) ?? []
    }

    func save(_ overlays: [Overlay]) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(overlays).write(to: url, options: .atomic)
    }

    func upsert(_ overlay: Overlay) {
        var overlays = all()
        if let index = overlays.firstIndex(where: { $0.id == overlay.id }) {
            overlays[index] = overlay
        } else {
            overlays.append(overlay)
        }
        save(overlays)
    }

    func remove(_ id: UUID) {
        save(all().filter { $0.id != id })
    }

    /// Overlays showing a document that no longer exists would be windows
    /// nothing can fill, so they go when it does.
    func removeAll(forDocument documentID: UUID) {
        save(all().filter { $0.documentID != documentID })
    }
}
