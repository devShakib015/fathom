import Foundation

/// Points an element at a value inside a data source.
///
/// Every binding carries a `fallback`. Networks fail, endpoints change shape,
/// and a widget that renders an empty string when the fetch failed looks
/// broken rather than offline — which is a much worse thing for a widget
/// sitting on someone's desktop to look like.
struct DataBinding: Codable, Hashable {
    var sourceID: UUID
    /// Dot path into the source's value tree. Array elements are indexed with
    /// brackets: `daily.temperature_2m_max[0]`, `list[2].main.temp`.
    var keyPath: String
    /// An optional transform applied to the value at `keyPath` before it is
    /// formatted, written in the small language in `Core/Expression`.
    ///
    /// nil, or empty, means show the value as it arrived — which is what the
    /// overwhelming majority of bindings want, so it stays the default and the
    /// inspector keeps it out of the way until asked for. When present, the
    /// key path's own value is spelled `value` inside the expression.
    var expression: String?
    var format: Format
    var fallback: String

    init(sourceID: UUID,
         keyPath: String,
         expression: String? = nil,
         format: Format = Format(kind: .text),
         fallback: String = "—") {
        self.sourceID = sourceID
        self.keyPath = keyPath
        self.expression = expression
        self.format = format
        self.fallback = fallback
    }

    var hasExpression: Bool {
        !(expression ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// How a resolved value becomes a string.
///
/// Modelled as a struct with a `kind` discriminator rather than an enum with
/// associated values, so the JSON is flat and legible and a new kind can be
/// added later without invalidating documents written by an older build.
/// `prefix` and `suffix` are here because "23" and "23°" are different
/// widgets and the alternative is asking users to place a second text element
/// next to every number.
struct Format: Codable, Hashable {
    var kind: Kind
    var precision: Int
    var dateStyle: DateStyle
    var prefix: String
    var suffix: String

    init(kind: Kind,
         precision: Int = 0,
         dateStyle: DateStyle = .time,
         prefix: String = "",
         suffix: String = "") {
        self.kind = kind
        self.precision = precision
        self.dateStyle = dateStyle
        self.prefix = prefix
        self.suffix = suffix
    }

    enum Kind: String, Codable, CaseIterable {
        case text
        case number
        /// A 0…1 fraction shown as 0–100 %.
        case percent
        case date
        /// Seconds shown as `2h 14m`.
        case duration
        /// A byte count shown as `241.3 GB`.
        case bytes

        var displayName: String {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .percent: "Percent"
            case .date: "Date & time"
            case .duration: "Duration"
            case .bytes: "File size"
            }
        }
    }

    enum DateStyle: String, Codable, CaseIterable {
        case time           // 18:42
        case timeWithSeconds
        case hour           // 18
        case minute         // 42
        case weekday        // Monday
        case shortWeekday   // Mon
        case day            // 8
        case month          // September
        case shortMonth     // Sep
        case monthDay       // 8 Sep
        case fullDate       // 8 September 2026
        case relative       // in 3 hours

        var displayName: String {
            switch self {
            case .time: "18:42"
            case .timeWithSeconds: "18:42:07"
            case .hour: "18"
            case .minute: "42"
            case .weekday: "Monday"
            case .shortWeekday: "Mon"
            case .day: "8"
            case .month: "September"
            case .shortMonth: "Sep"
            case .monthDay: "8 Sep"
            case .fullDate: "8 September 2026"
            case .relative: "in 3 hours"
            }
        }
    }
}
