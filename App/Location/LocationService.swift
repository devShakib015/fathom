import AppKit
import CoreLocation
import Observation

/// Finds out where this Mac is, and writes it somewhere the widget extension
/// can read.
///
/// App-side only. See `Place` for why the extension is never allowed to ask
/// this question itself.
///
/// The refresh is deliberately unhurried. A location that is an hour old is
/// still the right city, and `CLLocationManager` on a Mac is answering from
/// wifi geolocation rather than a GPS chip, so asking it repeatedly buys
/// nothing but wakeups.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var place: Place? = PlaceStore.read()
    private(set) var status: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?
    private(set) var isResolving = false

    @ObservationIgnored private let manager = CLLocationManager()
    /// Held, not made on the spot.
    ///
    /// `try? await CLGeocoder().reverseGeocodeLocation(fix)` reads fine and
    /// fails silently: the geocoder is a temporary, and nothing keeps it alive
    /// across the suspension point, so the request can be cancelled before it
    /// answers. Measured — the first real grant on this Mac wrote a place with
    /// correct coordinates and no city at all.
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var timer: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        status = manager.authorizationStatus
    }

    var isAuthorised: Bool {
        status == .authorizedAlways || status == .authorized
    }

    /// Whether a grant this Mac made to an *earlier build* has been lost.
    ///
    /// Fathom ships ad-hoc signed, and an ad-hoc signature is a fresh identity
    /// on every build. macOS keys privacy grants to that identity, so every
    /// update starts over at "not determined" — while the location the previous
    /// build resolved is still sitting in the shared store, still perfectly
    /// accurate. Saying "Not asked yet" over the top of a stored place is
    /// technically true and completely baffling.
    var wasGrantedToAnEarlierBuild: Bool {
        status == .notDetermined && place != nil
    }

    /// Human-readable state, for the one row of UI this deserves.
    var summary: String {
        switch status {
        case .notDetermined:
            if let place {
                "\(place.label), from a previous version — grant again to update it"
            } else {
                "Not asked yet"
            }
        case .restricted: "Blocked by this Mac's settings"
        case .denied: "Denied — System Settings ▸ Privacy & Security ▸ Location Services"
        default:
            if let place { "\(place.label) · \(Self.relative(place.resolvedAt))" }
            else if isResolving { "Locating…" }
            else { lastError ?? "Waiting for a fix" }
        }
    }

    // MARK: - Lifecycle

    func start() {
        status = manager.authorizationStatus
        guard isAuthorised else { return }
        resolve()
        timer?.cancel()
        // An hour. Long enough that this is not a battery item, short enough
        // that a laptop opened in a new city catches up before the day is out.
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                await MainActor.run { self?.resolve() }
            }
        }
    }

    /// Asks. Only ever called from a button the user pressed — Fathom does not
    /// raise a location prompt on first launch, because a widget builder that
    /// asks where you are before you have built anything has not earned it.
    func request() {
        lastError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            resolve()
        }
    }

    func stop() {
        timer?.cancel(); timer = nil
        PlaceStore.clear()
        place = nil
    }

    // MARK: - Resolving

    private func resolve() {
        guard isAuthorised, !isResolving else { return }
        isResolving = true
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let new = manager.authorizationStatus
        Task { @MainActor in
            self.status = new
            if self.isAuthorised { self.start() } else { self.isResolving = false }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in await self.record(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.isResolving = false
            self.lastError = error.localizedDescription
        }
    }

    private func record(_ fix: CLLocation) async {
        var place = Place(latitude: fix.coordinate.latitude,
                          longitude: fix.coordinate.longitude,
                          city: nil, region: nil, country: nil,
                          countryCode: nil, timeZone: TimeZone.current.identifier,
                          resolvedAt: Date(), isAuthorised: true)

        // Written before the name is looked up, so a geocode that fails or
        // never returns cannot cost the user the fix they just granted. The
        // coordinate is the part every weather endpoint actually needs.
        PlaceStore.write(place)
        self.place = place

        // The name is a bonus: if this fails the place stays completely usable
        // and `label` falls back to the coordinates.
        if let mark = try? await geocoder.reverseGeocodeLocation(fix).first {
            place.city = mark.locality ?? mark.subAdministrativeArea
            place.region = mark.administrativeArea
            place.country = mark.country
            place.countryCode = mark.isoCountryCode
            if let zone = mark.timeZone { place.timeZone = zone.identifier }
        }

        PlaceStore.write(place)
        self.place = place
        self.isResolving = false
        self.lastError = nil
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
