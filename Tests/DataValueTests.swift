import Testing
import Foundation

/// Parsing an endpoint, and finding things in it.
@Suite("Data values")
struct DataValueTests {

    @Test("objects keep the endpoint's own key order")
    func keyOrder() throws {
        // Alphabetising a response makes a familiar API look foreign in the
        // tree browser, which is the main way anyone understands an unfamiliar
        // one. The order is recovered by scanning the raw bytes.
        let json = #"{"zulu":1,"alpha":2,"mike":3}"#.data(using: .utf8)!
        guard case .object(let pairs) = try DataValue.parse(json) else {
            Issue.record("expected an object"); return
        }
        #expect(pairs.map(\.key) == ["zulu", "alpha", "mike"])
    }

    @Test("key paths walk objects and arrays, forgivingly")
    func keyPaths() throws {
        let tree = try DataValue.parse(#"{"a":{"b":[10,20,30]}}"#.data(using: .utf8)!)
        #expect(tree[path: "a.b[1]"]?.stringValue == "20")
        // Dotted indices are accepted too; nobody should be punished for
        // writing list.0 when they meant list[0].
        #expect(tree[path: "a.b.1"]?.stringValue == "20")
        #expect(tree[path: "a.b[9]"] == nil)
        #expect(tree[path: "a.missing"] == nil)
    }

    @Test("booleans stay booleans rather than becoming ones and zeroes")
    func booleans() throws {
        let tree = try DataValue.parse(#"{"a":true,"b":1,"c":false}"#.data(using: .utf8)!)
        #expect(tree[path: "a"]?.stringValue == "true")
        #expect(tree[path: "b"]?.stringValue == "1")
        #expect(tree[path: "c"]?.typeLabel == "true/false")
    }

    @Test("dates parse in the shapes endpoints actually send")
    func dateShapes() {
        // ISO8601DateFormatter insists on seconds; Open-Meteo and plenty of
        // others send minute precision, and binding one of those to a text
        // element used to render the raw string.
        let shapes = ["2026-09-08T17:30", "2026-09-08", "2026-09-08T17:30:00",
                      "2026-09-08T17:30:00Z", "2026-09-08T17:30:00.123Z",
                      "2026-09-08 17:30:00", "2026-09-08T17:30:00+04:00"]
        for shape in shapes {
            #expect(DataValue.string(shape).dateValue != nil, "\(shape) should parse")
        }
        #expect(DataValue.string("not a date").dateValue == nil)
        #expect(DataValue.string("").dateValue == nil)
    }

    @Test("leaves are collected with their paths, arrays sampled once")
    func leaves() throws {
        let tree = try DataValue.parse(#"{"a":{"b":1},"list":[{"x":2},{"x":3}]}"#.data(using: .utf8)!)
        let paths = tree.leaves().map(\.path)
        #expect(paths.contains("a.b"))
        #expect(paths.contains("list[0].x"))
        // Knowing list[0] exists says everything list[43] would.
        #expect(!paths.contains("list[1].x"))
    }

    @Test("a fragment or malformed body does not crash the parser")
    func robustness() throws {
        #expect(try DataValue.parse("42".data(using: .utf8)!).doubleValue == 42)
        #expect(throws: (any Error).self) {
            try DataValue.parse("{not json".data(using: .utf8)!)
        }
    }

    @Test("a response nested deep enough to blow the stack is truncated, not fatal")
    func deepNestingIsBounded() {
        // Reasoned about first and got it wrong: JSONSerialization refuses about
        // a thousand levels and accepts five hundred, which was read as meaning
        // the recursion could not be driven deep enough to matter. It could —
        // five hundred frames of `convert` crashed the whole test process, and
        // the depth comes from whatever an endpoint returns.
        let deep = String(repeating: "[", count: 400) + String(repeating: "]", count: 400)
        let parsed = try? DataValue.parse(Data(deep.utf8))
        #expect(parsed != nil)

        // Past the limit the branch is null rather than the process being gone.
        var value = parsed
        for _ in 0..<DataValue.maximumDepth {
            guard case .array(let items)? = value else { break }
            value = items.first
        }
        #expect(value == .null || value == nil)
    }

    @Test("an ordinary depth is untouched by the limit")
    func normalDepthSurvives() {
        // Real endpoints nest five to eight levels; the limit must be invisible
        // to them or it has traded one silent failure for another.
        let json = #"{"a":{"b":{"c":{"d":{"e":{"f":{"g":{"h":42}}}}}}}}"#
        let parsed = try? DataValue.parse(Data(json.utf8))
        #expect(parsed?[path: "a.b.c.d.e.f.g.h"] == .number(42))
    }

    @Test("the response ceiling is generous but finite")
    func responseCeiling() {
        // A widget extension has a hard memory ceiling, and exceeding it gets
        // the extension killed and replaced by a blank placeholder with nothing
        // to explain why. Image downloads have been capped from the beginning;
        // JSON bodies were not capped at all.
        #expect(DataResolver.maximumResponseBytes >= 4 * 1024 * 1024)
        #expect(DataResolver.maximumResponseBytes <= ImageStore.maximumDownloadBytes)
    }

}

/// How a resolved value becomes the string an element draws.
@Suite("Formatting")
struct FormatterTests {

    @Test("percent accepts both conventions endpoints use")
    func percentRanges() {
        // 0…1 and 0…100 are both common for the same quantity, so the
        // formatter takes either rather than making the user know which.
        let format = Format(kind: .percent)
        #expect(ValueFormatter.string(.number(0.53), format: format, fallback: "—") == "53%")
        #expect(ValueFormatter.string(.number(53), format: format, fallback: "—") == "53%")
    }

    @Test("bytes use decimal units, as the Finder does")
    func bytes() {
        let format = Format(kind: .bytes)
        #expect(ValueFormatter.string(.number(241_300_000_000), format: format, fallback: "—") == "241 GB")
        #expect(ValueFormatter.string(.number(512), format: format, fallback: "—") == "512 B")
    }

    @Test("a missing value renders the fallback, never blank")
    func fallback() {
        #expect(ValueFormatter.string(nil, format: Format(kind: .text), fallback: "offline") == "offline")
        #expect(ValueFormatter.string(.null, format: Format(kind: .number), fallback: "—") == "—")
    }

    @Test("prefix and suffix wrap the value, not the fallback")
    func affixes() {
        let format = Format(kind: .number, precision: 1, prefix: "up to ", suffix: "°")
        #expect(ValueFormatter.string(.number(21.44), format: format, fallback: "—") == "up to 21.4°")
        #expect(ValueFormatter.string(nil, format: format, fallback: "—") == "—")
    }

    @Test("a series is read from an array, a literal, or a single number")
    func series() {
        #expect(SeriesReader.series(from: .array([.number(1), .number(2)])) == [1, 2])
        #expect(SeriesReader.literal("12, 15,13") == [12, 15, 13])
        #expect(SeriesReader.series(from: .number(7)) == [7])
        #expect(SeriesReader.series(from: nil).isEmpty)
    }
}

/// Guessing a format from a field's type and name.
@Suite("Format inference")
struct InferenceTests {

    func inferred(_ value: DataValue, _ path: String, _ kind: Element.Kind = .text) -> String {
        let format = Format.inferred(for: value, keyPath: path, kind: kind)
        return ValueFormatter.string(value, format: format, fallback: "—")
    }

    @Test("a unit suffix is only added for fields that mean temperature")
    func degreeSuffix() {
        #expect(inferred(.number(21.4), "main.temp") == "21.4°")
        #expect(inferred(.number(36.7), "current.temperature_2m") == "36.7°")
        // _c matched inside _code and turned a WMO condition into "0°".
        #expect(inferred(.number(0), "current.weather_code") == "0")
        #expect(inferred(.number(3), "user.id") == "3")
    }

    @Test("proportions are decided by name, since the range is not reliable")
    func proportions() {
        #expect(inferred(.number(0.62), "battery.percent") == "62%")
        #expect(inferred(.number(53), "current.relative_humidity_2m") == "53%")
    }

    @Test("plausible epochs in time-named fields become clocks")
    func epochs() {
        let asDate = Format.inferred(for: .number(1_757_340_000), keyPath: "current.dt", kind: .text)
        #expect(asDate.kind == .date)
        // The same magnitude in an id field is not a date.
        let asNumber = Format.inferred(for: .number(1_757_340_000), keyPath: "user.id", kind: .text)
        #expect(asNumber.kind == .number)
    }

    @Test("an arc is a proportion whatever the field is called")
    func arcs() {
        #expect(Format.inferred(for: .number(0.4), keyPath: "anything", kind: .arc).kind == .percent)
    }

}
