import Foundation

/// A resolved value from a data source: JSON, plus a date case the system
/// source needs and no JSON endpoint can produce.
///
/// This is what a key path walks and what the editor's tree browser shows, so
/// it has to keep the shape of the original document — an endpoint that
/// returns `{"list":[{"main":{"temp":21}}]}` has to look like that on screen,
/// because the user is about to drag `list[0].main.temp` out of it.
indirect enum DataValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case null
    case array([DataValue])
    case object([(key: String, value: DataValue)])

    // Objects keep insertion order. A dictionary would sort the user's
    // endpoint into alphabetical nonsense, and the order a JSON body arrives
    // in is usually the order its author thought was sensible.

    static func == (a: DataValue, b: DataValue) -> Bool {
        switch (a, b) {
        case let (.string(x), .string(y)): x == y
        case let (.number(x), .number(y)): x == y
        case let (.bool(x), .bool(y)): x == y
        case let (.date(x), .date(y)): x == y
        case (.null, .null): true
        case let (.array(x), .array(y)): x == y
        case let (.object(x), .object(y)):
            x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let v): hasher.combine(0); hasher.combine(v)
        case .number(let v): hasher.combine(1); hasher.combine(v)
        case .bool(let v): hasher.combine(2); hasher.combine(v)
        case .date(let v): hasher.combine(3); hasher.combine(v)
        case .null: hasher.combine(4)
        case .array(let v): hasher.combine(5); hasher.combine(v)
        case .object(let v):
            hasher.combine(6)
            for (k, val) in v { hasher.combine(k); hasher.combine(val) }
        }
    }

    /// Build an object in the order given, which is almost always the order
    /// that reads best. Named `ordered` rather than overloading `object` so
    /// there is never a question of which one a call site meant.
    static func ordered(_ pairs: [(String, DataValue)]) -> DataValue {
        .object(pairs.map { (key: $0.0, value: $0.1) })
    }

    // MARK: - Reading

    var doubleValue: Double? {
        switch self {
        case .number(let v): v
        case .bool(let v): v ? 1 : 0
        case .string(let v): Double(v)
        case .date(let v): v.timeIntervalSince1970
        default: nil
        }
    }

    var dateValue: Date? {
        switch self {
        case .date(let v): v
        case .number(let v): Date(timeIntervalSince1970: v)
        case .string(let v): DataValue.isoParsers.lazy.compactMap { $0.date(from: v) }.first
        default: nil
        }
    }

    /// The plain string form, used when a binding's format is `.text` and as
    /// the leaf preview in the editor's tree.
    var stringValue: String {
        switch self {
        case .string(let v): v
        case .number(let v): v == v.rounded() && abs(v) < 1e15
            ? String(Int64(v))
            : String(format: "%g", v)
        case .bool(let v): v ? "true" : "false"
        case .date(let v): v.formatted(date: .abbreviated, time: .shortened)
        case .null: ""
        case .array(let v): "[\(v.count)]"
        case .object(let v): "{\(v.count)}"
        }
    }

    var isLeaf: Bool {
        switch self {
        case .array, .object: false
        default: true
        }
    }

    /// A short type label for the tree browser: `string`, `number`, `3 items`.
    var typeLabel: String {
        switch self {
        case .string: "text"
        case .number: "number"
        case .bool: "true/false"
        case .date: "date"
        case .null: "null"
        case .array(let v): v.count == 1 ? "1 item" : "\(v.count) items"
        case .object(let v): v.count == 1 ? "1 field" : "\(v.count) fields"
        }
    }

    private static let isoParsers: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        // Endpoints routinely omit the zone: "2026-09-08T18:42" is common.
        let local = ISO8601DateFormatter()
        local.formatOptions = [.withFullDate, .withDashSeparatorInDate,
                               .withTime, .withColonSeparatorInTime]
        local.timeZone = .current
        return [withFraction, plain, local]
    }()
}

// MARK: - Key paths

extension DataValue {
    /// Walks `a.b[0].c`. Returns nil rather than throwing: a missing path is
    /// the normal case when an endpoint changes shape, and the binding's
    /// fallback is what should render.
    subscript(path path: String) -> DataValue? {
        var current: DataValue = self
        for step in KeyPath.parse(path) {
            switch (step, current) {
            case let (.key(name), .object(pairs)):
                guard let hit = pairs.first(where: { $0.key == name }) else { return nil }
                current = hit.value
            case let (.index(i), .array(items)):
                guard items.indices.contains(i) else { return nil }
                current = items[i]
            default:
                return nil
            }
        }
        return current
    }

    enum KeyPath {
        case key(String)
        case index(Int)

        /// Splits on dots, then peels `[n]` subscripts off each component.
        /// Deliberately forgiving — a user typing a path by hand should not
        /// be punished for `list.0.temp` when they meant `list[0].temp`.
        static func parse(_ path: String) -> [KeyPath] {
            var out: [KeyPath] = []
            for component in path.split(separator: ".", omittingEmptySubsequences: true) {
                var name = ""
                var digits = ""
                var inBracket = false
                for ch in component {
                    if ch == "[" {
                        if !name.isEmpty { out.append(.key(name)); name = "" }
                        inBracket = true
                    } else if ch == "]" {
                        if let i = Int(digits) { out.append(.index(i)) }
                        digits = ""
                        inBracket = false
                    } else if inBracket {
                        digits.append(ch)
                    } else {
                        name.append(ch)
                    }
                }
                if !name.isEmpty {
                    if let i = Int(name) { out.append(.index(i)) } else { out.append(.key(name)) }
                }
            }
            return out
        }

        /// Renders a path back to the canonical `a.b[0].c` spelling.
        static func render(_ steps: [KeyPath]) -> String {
            steps.reduce(into: "") { acc, step in
                switch step {
                case .key(let k): acc += acc.isEmpty ? k : ".\(k)"
                case .index(let i): acc += "[\(i)]"
                }
            }
        }
    }
}

// MARK: - JSON

extension DataValue {
    /// Parses a response body. Uses `JSONSerialization` with
    /// `.mutableContainers` off and then rebuilds ordered objects from the
    /// raw bytes, so the tree the user browses is in the endpoint's order.
    static func parse(_ data: Data) throws -> DataValue {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let order = KeyOrder(data: data)
        return convert(any, order: order, path: "")
    }

    private static func convert(_ any: Any, order: KeyOrder, path: String) -> DataValue {
        switch any {
        case let v as [Any]:
            return .array(v.enumerated().map { convert($1, order: order, path: "\(path)[\($0)]") })
        case let v as [String: Any]:
            let keys = order.keys(at: path) ?? v.keys.sorted()
            let seen = Set(keys)
            let extras = v.keys.filter { !seen.contains($0) }.sorted()
            return .object((keys + extras).compactMap { key in
                guard let child = v[key] else { return nil }
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                return (key: key, value: convert(child, order: order, path: childPath))
            })
        case let v as NSNumber:
            // NSNumber does not distinguish 1 from true, but the underlying
            // ObjC type does, and a widget showing "1" where the endpoint
            // said `true` is a small lie that compounds.
            if CFGetTypeID(v) == CFBooleanGetTypeID() { return .bool(v.boolValue) }
            return .number(v.doubleValue)
        case let v as String:
            return .string(v)
        case is NSNull:
            return .null
        default:
            return .string(String(describing: any))
        }
    }
}

/// Recovers the original key order of every object in a JSON body.
///
/// `JSONSerialization` hands back dictionaries, which are unordered, and the
/// tree browser is the main way a user understands an unfamiliar endpoint —
/// showing them alphabetised keys makes a familiar response look foreign.
private struct KeyOrder {
    private var byPath: [String: [String]] = [:]

    init(data: Data) {
        var scanner = Scanner(bytes: [UInt8](data))
        scanner.scan(path: "", into: &byPath)
    }

    func keys(at path: String) -> [String]? { byPath[path] }

    private struct Scanner {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func scan(path: String, into map: inout [String: [String]]) {
            skipWhitespace()
            guard i < bytes.count else { return }
            switch bytes[i] {
            case UInt8(ascii: "{"):
                i += 1
                var order: [String] = []
                while true {
                    skipWhitespace()
                    guard i < bytes.count else { break }
                    if bytes[i] == UInt8(ascii: "}") { i += 1; break }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    guard bytes[i] == UInt8(ascii: "\""), let key = readString() else { i += 1; continue }
                    order.append(key)
                    skipWhitespace()
                    if i < bytes.count, bytes[i] == UInt8(ascii: ":") { i += 1 }
                    scan(path: path.isEmpty ? key : "\(path).\(key)", into: &map)
                }
                map[path] = order
            case UInt8(ascii: "["):
                i += 1
                var index = 0
                while true {
                    skipWhitespace()
                    guard i < bytes.count else { break }
                    if bytes[i] == UInt8(ascii: "]") { i += 1; break }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    scan(path: "\(path)[\(index)]", into: &map)
                    index += 1
                }
            case UInt8(ascii: "\""):
                _ = readString()
            default:
                while i < bytes.count,
                      bytes[i] != UInt8(ascii: ","),
                      bytes[i] != UInt8(ascii: "}"),
                      bytes[i] != UInt8(ascii: "]") { i += 1 }
            }
        }

        mutating func skipWhitespace() {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D { i += 1 }
        }

        mutating func readString() -> String? {
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { return nil }
            i += 1
            var out: [UInt8] = []
            while i < bytes.count {
                let b = bytes[i]
                if b == UInt8(ascii: "\\") {
                    // Escapes are not unescaped here: this only has to match
                    // the keys JSONSerialization produced, and both sides see
                    // the same bytes for ordinary keys. Exotic escaped keys
                    // fall through to the alphabetical extras list.
                    i += 2
                    continue
                }
                if b == UInt8(ascii: "\"") { i += 1; return String(decoding: out, as: UTF8.self) }
                out.append(b)
                i += 1
            }
            return nil
        }
    }
}
