import Foundation

/// Turns a resolved `DataValue` into the string an element draws.
///
/// Formatting lives here rather than in the renderer because the editor has to
/// show exactly what the widget will show — a preview that formats differently
/// from the extension is worse than no preview.
enum ValueFormatter {

    static func string(_ value: DataValue?, format: Format, fallback: String) -> String {
        guard let value, value != .null else { return fallback }
        let body = core(value, format: format)
        guard let body else { return fallback }
        return format.prefix + body + format.suffix
    }

    private static func core(_ value: DataValue, format: Format) -> String? {
        switch format.kind {
        case .text:
            return value.stringValue

        case .number:
            guard let n = value.doubleValue else { return nil }
            return decimal(n, precision: format.precision)

        case .percent:
            guard let n = value.doubleValue else { return nil }
            // A 0…1 fraction is the convention everywhere in Fathom, but
            // endpoints that already return 0…100 are common enough that
            // silently showing "8500%" would be the wrong kind of literal.
            let scaled = n > 1.0001 ? n : n * 100
            return decimal(scaled, precision: format.precision) + "%"

        case .date:
            guard let date = value.dateValue else { return nil }
            return dateString(date, style: format.dateStyle)

        case .duration:
            guard let seconds = value.doubleValue, seconds >= 0 else { return nil }
            return duration(seconds)

        case .bytes:
            guard let n = value.doubleValue else { return nil }
            return bytes(n, precision: format.precision)
        }
    }

    private static func decimal(_ n: Double, precision: Int) -> String {
        let clamped = min(max(precision, 0), 6)
        return String(format: "%.\(clamped)f", n)
    }

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    private static func bytes(_ n: Double, precision: Int) -> String {
        // Decimal units, because that is what the Finder shows and a widget
        // that disagrees with the Finder about free space reads as broken.
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = abs(n)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let digits = precision > 0 ? precision : (unit >= 3 && value < 100 ? 1 : 0)
        return "\(String(format: "%.\(min(digits, 6))f", value)) \(units[unit])"
    }

    private static func dateString(_ date: Date, style: Format.DateStyle) -> String {
        switch style {
        case .time:
            return date.formatted(.dateTime.hour().minute())
        case .timeWithSeconds:
            return date.formatted(.dateTime.hour().minute().second())
        case .hour:
            return date.formatted(.dateTime.hour())
        case .minute:
            return String(format: "%02d", Calendar.current.component(.minute, from: date))
        case .weekday:
            return date.formatted(.dateTime.weekday(.wide))
        case .shortWeekday:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .day:
            return String(Calendar.current.component(.day, from: date))
        case .month:
            return date.formatted(.dateTime.month(.wide))
        case .shortMonth:
            return date.formatted(.dateTime.month(.abbreviated))
        case .monthDay:
            return date.formatted(.dateTime.day().month(.abbreviated))
        case .fullDate:
            return date.formatted(.dateTime.day().month(.wide).year())
        case .relative:
            return date.formatted(.relative(presentation: .named))
        }
    }
}

/// A list of numbers pulled out of a value, for the sparkline.
///
/// Accepts an array of numbers, an array of objects with a single numeric
/// field, or a comma-separated literal — an endpoint that returns
/// `daily.temperature_2m_max` as `[19, 22, 24]` and a user typing
/// `19,22,24` into the inspector should both work without explanation.
enum SeriesReader {
    static func series(from value: DataValue?) -> [Double] {
        guard let value else { return [] }
        switch value {
        case .array(let items):
            return items.compactMap(\.doubleValue)
        case .string(let s):
            return literal(s)
        case .number(let n):
            return [n]
        default:
            return []
        }
    }

    static func literal(_ text: String) -> [Double] {
        text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}
