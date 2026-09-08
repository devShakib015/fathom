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
}
