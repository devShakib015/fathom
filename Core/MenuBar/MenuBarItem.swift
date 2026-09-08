import Foundation

/// A document drawn into the menu bar.
///
/// Fathom's second host after the overlay, and the first that is not a window
/// at all. Same documents, same interpreter, same bindings — only the surface
/// changes, which is the whole argument for a format that describes a design
/// rather than a widget.
///
/// Like an overlay it is outside WidgetKit, and therefore outside the
/// sixty-four second floor. Unlike an overlay it has a shape imposed on it: the
/// menu bar is 22 points tall and that is not negotiable, which is exactly why
/// the menu bar is a family and an overlay is not.
struct MenuBarItem: Codable, Identifiable, Hashable {
    var id: UUID
    var documentID: UUID
    /// Width in points. The height is the menu bar's, always.
    var width: Double
    /// Shown in a popover when the item is clicked. nil means clicking does
    /// nothing, which is a fair choice for a status readout.
    var popoverDocumentID: UUID?
    var refresh: TimeInterval
    var isEnabled: Bool

    static let minimumWidth: Double = 24
    static let maximumWidth: Double = 480
    static let refreshFloor: TimeInterval = 1
    static let defaultRefresh: TimeInterval = 5

    init(documentID: UUID, width: Double = 160) {
        self.id = UUID()
        self.documentID = documentID
        self.width = min(max(width, MenuBarItem.minimumWidth), MenuBarItem.maximumWidth)
        self.popoverDocumentID = nil
        self.refresh = MenuBarItem.defaultRefresh
        self.isEnabled = true
    }

    enum CodingKeys: String, CodingKey {
        case id, documentID, width, popoverDocumentID, refresh, isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 160
        popoverDocumentID = try c.decodeIfPresent(UUID.self, forKey: .popoverDocumentID)
        refresh = max(try c.decodeIfPresent(TimeInterval.self, forKey: .refresh)
                      ?? MenuBarItem.defaultRefresh, MenuBarItem.refreshFloor)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

struct MenuBarStore {
    static let shared = MenuBarStore()

    private var url: URL? { SharedStore.container?.appendingPathComponent("menubar.json") }

    func all() -> [MenuBarItem] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MenuBarItem].self, from: data)) ?? []
    }

    func save(_ items: [MenuBarItem]) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(items).write(to: url, options: .atomic)
    }

    func removeAll(forDocument documentID: UUID) {
        save(all().filter { $0.documentID != documentID && $0.popoverDocumentID != documentID })
    }
}
