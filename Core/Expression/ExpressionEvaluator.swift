import Foundation

/// Evaluates a parsed expression against a source's value tree.
///
/// Total by construction: every function is finite, there is no recursion a
/// user can reach, and a failed lookup produces `null` rather than an error.
/// That last choice is deliberate — an endpoint changing shape should make a
/// widget fall back to its `fallback` string, not make it fail to render.
struct ExpressionEvaluator {
    /// The tree the binding's source resolved to.
    let tree: DataValue?
    /// The value at the binding's own key path, i.e. what `value` means.
    let ownValue: DataValue?
    /// Inside a repeater: the item being drawn, its position, and how many
    /// there are. All nil outside one, where the identifiers evaluate to null.
    let item: DataValue?
    let index: Int?
    let total: Int?
    let now: Date

    init(tree: DataValue?,
         ownValue: DataValue?,
         item: DataValue? = nil,
         index: Int? = nil,
         total: Int? = nil,
         now: Date = Date()) {
        self.tree = tree
        self.ownValue = ownValue
        self.item = item
        self.index = index
        self.total = total
        self.now = now
    }

    func evaluate(_ expression: Expression) -> DataValue {
        switch expression {
        case .literal(let v):
            return v

        case .value:
            return ownValue ?? .null

        case .item:
            return item ?? .null

        case .index:
            return index.map { .number(Double($0)) } ?? .null

        case .count:
            return total.map { .number(Double($0)) } ?? .null

        case .field(let pathExpression):
            let path = evaluate(pathExpression).stringValue
            return tree?[path: path] ?? .null

        case .unary(let op, let operand):
            let v = evaluate(operand)
            switch op {
            case .negate: return .number(-(v.doubleValue ?? 0))
            case .not: return .bool(!truthy(v))
            }

        case .binary(let op, let lhs, let rhs):
            return evaluateBinary(op, lhs, rhs)

        case .call(let name, let arguments):
            return evaluateCall(name, arguments.map(evaluate))
        }
    }

    // MARK: - Operators

    private func evaluateBinary(_ op: Expression.BinaryOperator, _ lhs: Expression, _ rhs: Expression) -> DataValue {
        // Short-circuit before evaluating the right side, so
        // `field("a") != null && field("a") > 5` is safe to write.
        if op == .and { return truthy(evaluate(lhs)) ? .bool(truthy(evaluate(rhs))) : .bool(false) }
        if op == .or { return truthy(evaluate(lhs)) ? .bool(true) : .bool(truthy(evaluate(rhs))) }

        let a = evaluate(lhs), b = evaluate(rhs)

        switch op {
        case .add:
            // "+" concatenates when either side is text, which is what anyone
            // writing `"in " + value` expects, and adds otherwise.
            if case .string = a { return .string(a.stringValue + b.stringValue) }
            if case .string = b { return .string(a.stringValue + b.stringValue) }
            return .number((a.doubleValue ?? 0) + (b.doubleValue ?? 0))
        case .subtract: return .number((a.doubleValue ?? 0) - (b.doubleValue ?? 0))
        case .multiply: return .number((a.doubleValue ?? 0) * (b.doubleValue ?? 0))
        case .divide:
            let divisor = b.doubleValue ?? 0
            // Dividing by zero yields null rather than infinity: an element
            // showing "inf" is a bug report, one showing its fallback is not.
            return divisor == 0 ? .null : .number((a.doubleValue ?? 0) / divisor)
        case .remainder:
            let divisor = b.doubleValue ?? 0
            return divisor == 0 ? .null : .number((a.doubleValue ?? 0).truncatingRemainder(dividingBy: divisor))
        case .equal: return .bool(looseEquals(a, b))
        case .notEqual: return .bool(!looseEquals(a, b))
        case .less: return compare(a, b) { $0 < $1 }
        case .lessOrEqual: return compare(a, b) { $0 <= $1 }
        case .greater: return compare(a, b) { $0 > $1 }
        case .greaterOrEqual: return compare(a, b) { $0 >= $1 }
        case .and, .or: return .bool(false)   // handled above
        }
    }

    /// `1 == "1"` is true. Endpoints are inconsistent about quoting numbers and
    /// a user should not have to know which side of that line their API fell on.
    private func looseEquals(_ a: DataValue, _ b: DataValue) -> Bool {
        if case .null = a, case .null = b { return true }
        if let x = a.doubleValue, let y = b.doubleValue { return x == y }
        return a.stringValue == b.stringValue
    }

    private func compare(_ a: DataValue, _ b: DataValue, _ test: (Double, Double) -> Bool) -> DataValue {
        guard let x = a.doubleValue, let y = b.doubleValue else {
            return .bool(test(0, 0) && a.stringValue == b.stringValue)
        }
        return .bool(test(x, y))
    }

    private func truthy(_ v: DataValue) -> Bool {
        switch v {
        case .bool(let b): b
        case .number(let n): n != 0
        case .string(let s): !s.isEmpty
        case .null: false
        case .array(let items): !items.isEmpty
        case .object(let pairs): !pairs.isEmpty
        case .date: true
        }
    }

    // MARK: - Functions

    private func evaluateCall(_ name: String, _ args: [DataValue]) -> DataValue {
        func number(_ i: Int) -> Double { i < args.count ? (args[i].doubleValue ?? 0) : 0 }
        func text(_ i: Int) -> String { i < args.count ? args[i].stringValue : "" }
        func list(_ i: Int) -> [Double] {
            guard i < args.count, case .array(let items) = args[i] else { return [] }
            return items.compactMap(\.doubleValue)
        }

        switch name {
        case "if":
            guard args.count >= 2 else { return .null }
            return truthy(args[0]) ? args[1] : (args.count > 2 ? args[2] : .null)

        case "map":
            // map(x, k1, v1, k2, v2, …, default) — a lookup table, which is how
            // a WMO weather code becomes an SF Symbol without a scripting
            // language. An odd trailing argument is the default.
            guard let subject = args.first else { return .null }
            var i = 1
            while i + 1 < args.count {
                if looseEquals(subject, args[i]) { return args[i + 1] }
                i += 2
            }
            return args.count % 2 == 0 ? args[args.count - 1] : .null

        case "coalesce":
            for arg in args where !isNull(arg) { return arg }
            return .null

        case "round":
            let places = args.count > 1 ? max(0, min(Int(number(1)), 6)) : 0
            let factor = pow(10.0, Double(places))
            return .number((number(0) * factor).rounded() / factor)
        case "floor": return .number(number(0).rounded(.down))
        case "ceil": return .number(number(0).rounded(.up))
        case "abs": return .number(Swift.abs(number(0)))
        case "min": return .number(args.compactMap(\.doubleValue).min() ?? 0)
        case "max": return .number(args.compactMap(\.doubleValue).max() ?? 0)
        case "clamp": return .number(Swift.min(Swift.max(number(0), number(1)), number(2)))
        case "pow": return .number(pow(number(0), number(1)))
        case "sqrt": return .number(number(0) < 0 ? 0 : number(0).squareRoot())

        case "sum": return .number(list(0).reduce(0, +))
        case "avg":
            let values = list(0)
            return values.isEmpty ? .null : .number(values.reduce(0, +) / Double(values.count))
        case "lowest": return list(0).min().map { .number($0) } ?? .null
        case "highest": return list(0).max().map { .number($0) } ?? .null
        case "count":
            guard let first = args.first else { return .number(0) }
            switch first {
            case .array(let items): return .number(Double(items.count))
            case .object(let pairs): return .number(Double(pairs.count))
            case .string(let s): return .number(Double(s.count))
            default: return .number(first == .null ? 0 : 1)
            }
        case "at":
            guard case .array(let items)? = args.first else { return .null }
            let i = Int(number(1))
            return items.indices.contains(i) ? items[i] : .null
        case "first":
            guard case .array(let items)? = args.first else { return .null }
            return items.first ?? .null
        case "last":
            guard case .array(let items)? = args.first else { return .null }
            return items.last ?? .null
        case "slice":
            guard case .array(let items)? = args.first else { return .null }
            let start = Swift.max(0, Int(number(1)))
            let end = args.count > 2 ? Swift.min(items.count, Int(number(2))) : items.count
            return start < end ? .array(Array(items[start..<end])) : .array([])
        case "join":
            guard case .array(let items)? = args.first else { return .string("") }
            return .string(items.map(\.stringValue).joined(separator: args.count > 1 ? text(1) : ", "))

        case "upper": return .string(text(0).uppercased())
        case "lower": return .string(text(0).lowercased())
        case "trim": return .string(text(0).trimmingCharacters(in: .whitespacesAndNewlines))
        case "contains": return .bool(text(0).localizedCaseInsensitiveContains(text(1)))
        case "replace": return .string(text(0).replacingOccurrences(of: text(1), with: text(2)))
        case "left": return .string(String(text(0).prefix(Swift.max(0, Int(number(1))))))
        case "right": return .string(String(text(0).suffix(Swift.max(0, Int(number(1))))))
        case "length": return .number(Double(text(0).count))

        case "num": return args.first?.doubleValue.map { .number($0) } ?? .null
        case "str": return .string(text(0))
        case "date": return args.first?.dateValue.map { .date($0) } ?? .null
        case "now": return .date(now)

        case "isnull": return .bool(isNull(args.first ?? .null))

        default:
            // An unknown function evaluates to null rather than throwing. The
            // inspector validates names as you type; at render time a typo
            // should show the fallback, not stop the widget.
            return .null
        }
    }

    private func isNull(_ v: DataValue) -> Bool {
        if case .null = v { return true }
        return false
    }

    /// Every function the language knows, for the inspector's help and for
    /// validating a name before the widget ever runs.
    static let functionNames = [
        "if", "map", "coalesce", "round", "floor", "ceil", "abs", "min", "max",
        "clamp", "pow", "sqrt", "sum", "avg", "lowest", "highest", "count", "at",
        "first", "last", "slice", "join", "upper", "lower", "trim", "contains",
        "replace", "left", "right", "length", "num", "str", "date", "now",
        "isnull", "field",
    ]
}
