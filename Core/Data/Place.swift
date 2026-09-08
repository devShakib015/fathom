import Foundation

/// Where this Mac is, as last resolved by the app.
///
/// Deliberately a *stored record* rather than something the widget extension
/// asks CoreLocation for itself. Three reasons, in order of how much they cost
/// to learn the hard way:
///
/// 1. The extension is a brand new short-lived process on every reload. Asking
///    for a fresh fix sixty-four seconds apart, forever, is a battery cost with
///    no matching benefit — a Mac that has moved far enough to change the
///    weather has usually also been closed and reopened.
/// 2. Authorisation belongs to the app the user actually interacts with. A
///    permission prompt raised by a widget extension is a prompt raised by
///    something with no window, no context and nothing to explain itself with.
/// 3. `SharedStore` already exists as the app-to-extension channel, and one
///    channel that is understood beats two that are nearly the same.
///
/// So the app resolves and writes; the extension only ever reads. The record
/// carries its own timestamp so a widget can say how stale the place is, and
/// `isAuthorised` so a document can show something honest when permission was
/// never given rather than silently pretending to be at latitude zero.
struct Place: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Locality, e.g. "Dhaka". Nil until reverse geocoding succeeds — which it
    /// may never do, since that is a network call and this is a coordinate.
    var city: String?
    var region: String?
    var country: String?
    var countryCode: String?
    var timeZone: String?
    var resolvedAt: Date
    var isAuthorised: Bool

    /// The best single label for this place, never empty.
    var label: String {
        city ?? region ?? country ?? String(format: "%.2f, %.2f", latitude, longitude)
    }

    /// Somewhere to stand before the user has said yes.
    ///
    /// Not a real place and marked as such: `isAuthorised` false is what the
    /// templates key their "turn on location" copy off. The coordinates are
    /// Greenwich because a null island at 0,0 renders as a plausible-looking
    /// ocean forecast, and a wrong answer that looks right is worse than one
    /// that looks wrong.
    static let unknown = Place(latitude: 51.4779, longitude: -0.0015,
                               city: nil, region: nil, country: nil,
                               countryCode: nil, timeZone: nil,
                               resolvedAt: .distantPast, isAuthorised: false)

    var age: TimeInterval { Date().timeIntervalSince(resolvedAt) }
}

/// The one file both sides agree on.
enum PlaceStore {
    private static var url: URL? {
        SharedStore.directory("Location")?.appendingPathComponent("place.json")
    }

    static func read() -> Place? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Place.self, from: data)
    }

    static func write(_ place: Place) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let url, let data = try? encoder.encode(place) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// What a widget should draw with: the real place if there is one, and an
    /// honest stand-in if there is not.
    static var current: Place { read() ?? .unknown }
}
