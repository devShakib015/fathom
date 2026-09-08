import Foundation

/// Guesses how a freshly bound field should be displayed.
///
/// The guess is always overridable in the inspector — this only decides what
/// the user sees the instant they drop a field onto an element. Getting it
/// roughly right is the difference between "1757340000" and "18:42", and
/// between "0.62" and "62%", on the first try.
extension Format {

    static func inferred(for value: DataValue, keyPath: String, kind: Element.Kind) -> Format {
        let path = keyPath.lowercased()

        // An arc is a 0…1 dial by definition, so its label is a percentage
        // whatever the endpoint called the field.
        if kind == .arc { return Format(kind: .percent) }

        switch value {
        case .date:
            return Format(kind: .date, dateStyle: .time)

        case .bool:
            return Format(kind: .text)

        case .string(let text):
            // An ISO timestamp is a date even though JSON has no date type,
            // and endpoints return them constantly.
            if DataValue.string(text).dateValue != nil, text.contains("-"), text.count >= 8 {
                return Format(kind: .date, dateStyle: .time)
            }
            return Format(kind: .text)

        case .number(let n):
            if looksLikeBytes(path) { return Format(kind: .bytes) }
            if looksLikeEpoch(path, n) { return Format(kind: .date, dateStyle: .time) }
            if looksLikeDuration(path) { return Format(kind: .duration) }
            if looksLikeProportion(path) { return Format(kind: .percent) }
            return Format(kind: .number, precision: precision(for: n), suffix: unitSuffix(path))

        default:
            return Format(kind: .text)
        }
    }

    // MARK: - Heuristics

    private static func looksLikeBytes(_ path: String) -> Bool {
        ["byte", "size", "bandwidth", "storage", "disk"].contains { path.contains($0) }
    }

    /// A plausible Unix timestamp in a field that says so. Both bounds matter:
    /// "id" fields land in the same numeric range and are not dates.
    private static func looksLikeEpoch(_ path: String, _ n: Double) -> Bool {
        guard ["time", "date", "epoch", "timestamp", "dt", "sunrise", "sunset", "updated"]
            .contains(where: { path.contains($0) }) else { return false }
        return n > 1_000_000_000 && n < 4_000_000_000
    }

    private static func looksLikeDuration(_ path: String) -> Bool {
        ["duration", "elapsed", "remaining", "uptime", "seconds"].contains { path.contains($0) }
    }

    /// A field whose *name* says proportion. The range is deliberately not
    /// checked: endpoints are split between 0…1 and 0…100 for the same
    /// quantity — Open-Meteo returns humidity as 53 — and the percent
    /// formatter already handles both. Names that could plausibly exceed 100
    /// or carry another unit ("level", "load") are left out on purpose.
    private static func looksLikeProportion(_ path: String) -> Bool {
        ["percent", "percentage", "_pct", "fraction", "ratio", "humidity", "cloud", "progress", "battery"]
            .contains { path.contains($0) }
    }

    /// One decimal for values that clearly have one, none for whole numbers.
    /// A temperature of 21.4 should not render as 21, and a count of 7 should
    /// not render as 7.0.
    private static func precision(for n: Double) -> Int {
        n == n.rounded() ? 0 : 1
    }

    /// The degree sign is the one unit worth guessing — it is the single most
    /// common thing a Mac widget shows, and typing it is a nuisance.
    ///
    /// `_c` and `_f` are matched only at the end of the path. As substrings
    /// they fire on `weather_code`, and a WMO condition code rendered as "0°"
    /// is exactly the kind of small wrongness that makes a tool feel careless.
    private static func unitSuffix(_ path: String) -> String {
        let named = ["temperature", "temp", "feels_like", "dewpoint", "apparent"]
            .contains { path.contains($0) }
        let unitSuffixed = path.hasSuffix("_c") || path.hasSuffix("_f")
        return named || unitSuffixed ? "°" : ""
    }
}
