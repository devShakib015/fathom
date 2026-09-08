import Testing
import Foundation

/// What a URL becomes once the user's location is folded into it.
///
/// This is the seam where a shared design stops being about its author and
/// starts being about whoever opened it, so a mistake here is not a rendering
/// bug — it is every weather widget in the catalogue quietly reporting a city
/// nobody in the conversation lives in.
@Suite("Location")
struct LocationTests {

    private let dhaka = Place(latitude: 23.777176, longitude: 90.399452,
                              city: "Dhaka", region: "Dhaka Division",
                              country: "Bangladesh", countryCode: "BD",
                              timeZone: "Asia/Dhaka",
                              resolvedAt: Date(), isAuthorised: true)

    @Test("coordinates replace their tokens")
    func coordinates() {
        let url = DataSource.fill(
            "https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}",
            with: dhaka)
        #expect(url == "https://api.open-meteo.com/v1/forecast?latitude=23.7772&longitude=90.3995")
    }

    @Test("four decimal places, not fifteen")
    func precision() {
        // About eleven metres. Enough for any weather endpoint, and not a
        // record of which desk somebody sits at.
        let url = DataSource.fill("x={latitude}", with: dhaka)
        #expect(url == "x=23.7772")
    }

    @Test("short aliases work too")
    func aliases() {
        #expect(DataSource.fill("{lat},{lon}", with: dhaka) == "23.7772,90.3995")
        #expect(DataSource.fill("{lng}", with: dhaka) == "90.3995")
    }

    @Test("names are percent-encoded, so a space cannot break the URL")
    func encoding() {
        var place = dhaka
        place.city = "New York"
        #expect(DataSource.fill("?q={city}", with: place) == "?q=New%20York")
    }

    @Test("an unknown token is left exactly as it was")
    func unknownToken() {
        // A user's own endpoint is allowed to contain braces.
        #expect(DataSource.fill("/v1/{id}/data", with: dhaka) == "/v1/{id}/data")
    }

    @Test("the host is answerable before location is ever granted")
    func hostWithTokens() {
        // The sharing sheet promises to say what a document will contact. That
        // promise cannot depend on a permission the reader has not given.
        let source = DataSource(name: "Weather", kind: .json,
                                url: "https://api.open-meteo.com/v1/forecast?latitude={latitude}")
        #expect(source.host == "api.open-meteo.com")
        #expect(source.usesLocation)
    }

    @Test("a source with no tokens does not claim to need location")
    func plainSource() {
        let source = DataSource(name: "Plain", kind: .json,
                                url: "https://example.com/a.json")
        #expect(!source.usesLocation)
        #expect(source.host == "example.com")
    }

    @Test("a document saved before location gets its coordinates migrated")
    func migration() {
        // The widgets already on someone's desktop are the ones that matter;
        // fixing only the templates would leave them pointed at Dubai forever.
        let old = DataSource(name: "Open-Meteo", kind: .json,
                             url: "https://api.open-meteo.com/v1/forecast?latitude=25.2048&longitude=55.2708&current=temperature_2m")
        #expect(old.migrated.url ==
                "https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}&current=temperature_2m")
        #expect(old.migrated.usesLocation)
    }

    @Test("coordinates the user chose themselves are left alone")
    func migrationIsNarrow() {
        // Only the exact shipped placeholder is rewritten. Anything else is a
        // decision somebody made.
        let mine = DataSource(name: "Open-Meteo", kind: .json,
                              url: "https://api.open-meteo.com/v1/forecast?latitude=23.8103&longitude=90.4125")
        #expect(mine.migrated.url == mine.url)
        #expect(!mine.migrated.usesLocation)
    }

    @Test("the unknown place is marked unauthorised and still renders")
    func unknownPlace() {
        let place = Place.unknown
        #expect(!place.isAuthorised)
        // Never empty: a widget bound to place.label shows something.
        #expect(!place.label.isEmpty)
    }

    @Test("a place round-trips through JSON, to the second")
    func roundTrip() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(Place.self, from: try encoder.encode(dhaka))

        #expect(back.latitude == dhaka.latitude)
        #expect(back.longitude == dhaka.longitude)
        #expect(back.city == dhaka.city)
        #expect(back.region == dhaka.region)
        #expect(back.country == dhaka.country)
        #expect(back.countryCode == dhaka.countryCode)
        #expect(back.timeZone == dhaka.timeZone)
        #expect(back.isAuthorised == dhaka.isAuthorised)

        // ISO8601 stores whole seconds, so the timestamp comes back rounded.
        // Deliberately not worth fixing: this stamp exists to answer "how old
        // is this place", and nothing about a city changes in a millisecond.
        #expect(abs(back.resolvedAt.timeIntervalSince(dhaka.resolvedAt)) < 1)
    }

    @Test("label falls back through region and country to coordinates")
    func labelFallback() {
        var place = dhaka
        #expect(place.label == "Dhaka")
        place.city = nil
        #expect(place.label == "Dhaka Division")
        place.region = nil
        #expect(place.label == "Bangladesh")
        place.country = nil
        #expect(place.label == "23.78, 90.40")
    }
}
