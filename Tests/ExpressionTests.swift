import Testing
import Foundation

/// The expression language.
///
/// This is the highest-risk code in Fathom to break quietly: an evaluator that
/// starts returning the wrong number does not crash, it just renders something
/// plausible on somebody's desktop every sixty-four seconds forever.
@Suite("Expressions")
struct ExpressionTests {

    /// A response shaped like the ones people actually bind to: nested objects,
    /// parallel arrays, a minute-precision timestamp, a boolean-as-integer.
    static let sample = """
        {
          "latitude": 25.2,
          "timezone": "Asia/Dubai",
          "current": {
            "time": "2026-09-08T17:30",
            "temperature_2m": 36.7,
            "relative_humidity_2m": 53,
            "is_day": 1,
            "weather_code": 0
          },
          "daily": {
            "time": ["2026-09-08", "2026-09-09", "2026-09-10"],
            "temperature_2m_max": [40.8, 41.9, 38.6]
          }
        }
        """.data(using: .utf8)!

    func evaluate(_ source: String, ownPath: String = "current.temperature_2m") throws -> String {
        let tree = try DataValue.parse(Self.sample)
        let program = try ExpressionParser.parse(source)
        return ExpressionEvaluator(tree: tree, ownValue: tree[path: ownPath])
            .evaluate(program).stringValue
    }

    @Test("arithmetic respects precedence and parentheses")
    func arithmetic() throws {
        #expect(try evaluate("2 + 3 * 4") == "14")
        #expect(try evaluate("(2 + 3) * 4") == "20")
        #expect(try evaluate("10 % 3") == "1")
        #expect(try evaluate("round(value * 9 / 5 + 32, 1)") == "98.1")
        #expect(try evaluate("-value + 40") == "3.3")
    }

    @Test("dividing by zero yields nothing, not infinity")
    func divisionByZero() throws {
        // An element showing "inf" is a bug report; one showing its fallback is
        // not, so the evaluator has to produce null rather than a float.
        #expect(try evaluate("1 / 0") == "")
        #expect(try evaluate("1 % 0") == "")
    }

    @Test("fields can be named bare or quoted, and a miss is null")
    func fieldAccess() throws {
        #expect(try evaluate("current.relative_humidity_2m") == "53")
        #expect(try evaluate("field(\"current.relative_humidity_2m\")") == "53")
        #expect(try evaluate("first(daily.temperature_2m_max)") == "40.8")
        #expect(try evaluate("nothing.here") == "")
        #expect(try evaluate("current.temperature_2m.deeper") == "")
    }

    @Test("lookup tables map a code to a name")
    func lookupTables() throws {
        let table = "map(current.weather_code, 0, \"sun.max.fill\", 1, \"cloud.fill\", \"unknown\")"
        #expect(try evaluate(table) == "sun.max.fill")
        #expect(try evaluate("map(99, 0, \"a\", 1, \"b\", \"fallback\")") == "fallback")
        // An odd argument count means no default was given.
        #expect(try evaluate("map(99, 0, \"a\", 1, \"b\")") == "")
    }

    @Test("logic short-circuits so a missing field cannot poison the test")
    func shortCircuit() throws {
        #expect(try evaluate("isnull(missing.path) || missing.path > 5") == "true")
        #expect(try evaluate("count(daily.time) > 0 && highest(daily.temperature_2m_max) > 40") == "true")
    }

    @Test("equality is loose across quoting, because endpoints are")
    func looseEquality() throws {
        #expect(try evaluate("current.weather_code == \"0\"") == "true")
        #expect(try evaluate("current.is_day == 1") == "true")
    }

    @Test("array functions")
    func arrays() throws {
        #expect(try evaluate("count(daily.temperature_2m_max)") == "3")
        #expect(try evaluate("highest(daily.temperature_2m_max)") == "41.9")
        #expect(try evaluate("lowest(daily.temperature_2m_max)") == "38.6")
        #expect(try evaluate("at(daily.time, 1)") == "2026-09-09")
        #expect(try evaluate("join(slice(daily.time, 0, 2), \" / \")") == "2026-09-08 / 2026-09-09")
    }

    @Test("index and total resolve inside a repeated scope")
    func repeatedScope() throws {
        let tree = try DataValue.parse(Self.sample)
        let program = try ExpressionParser.parse("at(field(\"daily.temperature_2m_max\"), index)")
        let value = ExpressionEvaluator(tree: tree, ownValue: nil,
                                        item: .string("2026-09-09"), index: 1, total: 3)
            .evaluate(program)
        #expect(value.stringValue == "41.9")
    }

    @Test("outside a repeater the scope identifiers are null, not zero")
    func scopeOutsideRepeater() throws {
        // Zero would silently index the first row of everything.
        #expect(try evaluate("index") == "")
        #expect(try evaluate("total") == "")
    }

    @Test("malformed expressions are reported, never silently accepted")
    func parseErrors() {
        for bad in ["1 +", "(1 + 2", "\"unterminated", "1 @ 2", "value 5"] {
            #expect(throws: (any Error).self) { try ExpressionParser.parse(bad) }
        }
    }

    @Test("an empty expression means the value itself")
    func emptyExpression() throws {
        #expect(try evaluate("") == "36.7")
    }

    @Test("a NaN or absurd count cannot crash the evaluator")
    func trappingConversions() throws {
        // `Int(someDouble)` terminates the process on NaN or an out-of-range
        // magnitude — not throws, terminates. Confirmed with SIGTRAP. Both are
        // reachable by someone other than the person running Fathom: an
        // endpoint can send 1e30, and a document carrying an expression is a
        // thing people share. Reaching the assertion at all is the test.
        _ = try evaluate("fixed(1.5, 0/0)")
        _ = try evaluate("fixed(1.5, pow(10, 30))")
        _ = try evaluate("fixed(1.5, 0 - pow(10, 30))")
        _ = try evaluate("left(\"hello\", pow(10, 30))")
        _ = try evaluate("right(\"hello\", 0/0)")
        _ = try evaluate("percent(0.5, pow(10, 30))")
        _ = try evaluate("round(1.23456, pow(10, 30))")
        _ = try evaluate("at(daily.temperature_2m_max, 0/0)")
        _ = try evaluate("slice(daily.temperature_2m_max, 0/0, pow(10, 30))")
        #expect(Bool(true))
    }

    @Test("pow stays total, like the rest of the language")
    func powIsTotal() throws {
        // pow(-1, 0.5) is NaN — the one arithmetic function that makes one from
        // finite inputs. Division already returns null rather than infinity;
        // this now matches.
        #expect(try evaluate("pow(-1, 0.5)") == "")
        #expect(try evaluate("pow(2, 3)") == "8")
        #expect(try evaluate("pow(10, 400)") == "")   // overflows to infinity
    }

    @Test("the safe conversion clamps rather than trapping")
    func safeConversion() {
        #expect(Double.nan.asInt == 0)
        #expect(Double.infinity.asInt > 0)
        #expect((-Double.infinity).asInt < 0)
        #expect((1e30).asInt > 0)
        #expect((1e30).asInt == 9_007_199_254_740_992)
        #expect((42.7).asInt == 42)
    }
}

/// Text with expressions embedded in it.
@Suite("Templates")
struct TemplateTests {

    static func tree() throws -> DataValue {
        try DataValue.parse(#"{"disk":{"free":4200000000,"usedFraction":0.91}}"#.data(using: .utf8)!)
    }

    @Test("expressions inside braces are replaced, the rest is left alone")
    func interpolation() throws {
        let rendered = TextTemplate.render("Only {bytes(disk.free)} left.", tree: try Self.tree())
        #expect(rendered == "Only 4.2 GB left.")
    }

    @Test("formatting functions produce finished strings")
    func formatters() throws {
        let tree = try Self.tree()
        #expect(TextTemplate.render("{percent(disk.usedFraction)}", tree: tree) == "91%")
        #expect(TextTemplate.render("{fixed(disk.usedFraction, 2)}", tree: tree) == "0.91")
    }

    @Test("text with no braces is returned untouched")
    func passthrough() throws {
        #expect(TextTemplate.render("Nothing to do here", tree: try Self.tree()) == "Nothing to do here")
    }

    @Test("a broken or unclosed expression degrades rather than failing")
    func malformed() throws {
        let tree = try Self.tree()
        // An alert is not worth losing over a typo in its own text.
        #expect(TextTemplate.render("{1 +}", tree: tree) == "?")
        #expect(TextTemplate.render("half {open", tree: tree) == "half {open")
        #expect(TextTemplate.render("{missing.path}", tree: tree) == "—")
    }
}
