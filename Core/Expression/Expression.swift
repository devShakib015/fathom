import Foundation

/// A small expression language for transforming a bound value before it
/// renders.
///
/// This is the thing that separates "show `weather_code`" from "show a sun when
/// it is zero". Section 4 of the brief put expressions out of v1 and called
/// them a second product; the owner has since asked for as much flexibility as
/// the platform allows, and this is where most of that flexibility actually
/// lives. A widget is still data — the extension interprets an expression, it
/// does not compile one — so nothing about the forced architecture changes.
///
/// The language is deliberately small and total: no loops, no recursion, no
/// user-defined functions, no side effects. Every expression terminates, which
/// matters when the evaluator runs inside a widget extension that the system
/// will kill if it takes too long.
///
///     value * 9 / 5 + 32
///     round(value, 1)
///     if(value > 30, "hot", "mild")
///     map(value, 0, "sun.max.fill", 1, "cloud.sun.fill", "cloud.fill")
///     field("current.temperature_2m") - field("current.dew_point_2m")
indirect enum Expression: Hashable, Sendable {
    /// A constant written into the expression.
    case literal(DataValue)
    /// The value at the binding's own key path — the common case, so it gets
    /// the shortest possible spelling.
    case value
    /// Any other path in the same source.
    case field(Expression)
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    case call(String, [Expression])

    enum UnaryOperator: String, Hashable, Sendable {
        case not = "!"
        case negate = "-"
    }

    enum BinaryOperator: String, Hashable, Sendable {
        case add = "+", subtract = "-", multiply = "*", divide = "/", remainder = "%"
        case equal = "==", notEqual = "!=", less = "<", lessOrEqual = "<=" 
        case greater = ">", greaterOrEqual = ">="
        case and = "&&", or = "||"

        /// Binding power. Higher binds tighter.
        var precedence: Int {
            switch self {
            case .or: 1
            case .and: 2
            case .equal, .notEqual: 3
            case .less, .lessOrEqual, .greater, .greaterOrEqual: 4
            case .add, .subtract: 5
            case .multiply, .divide, .remainder: 6
            }
        }
    }
}

// MARK: - Errors

enum ExpressionError: LocalizedError, Hashable {
    case unexpectedCharacter(Character, at: Int)
    case unterminatedString
    case unexpectedToken(String)
    case unexpectedEnd
    case unknownFunction(String)
    case wrongArgumentCount(String, expected: String, got: Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedCharacter(let c, let i): "Unexpected “\(c)” at character \(i + 1)."
        case .unterminatedString: "A quoted string is missing its closing quote."
        case .unexpectedToken(let t): "Unexpected “\(t)”."
        case .unexpectedEnd: "The expression ends too early."
        case .unknownFunction(let name): "There is no function called “\(name)”."
        case .wrongArgumentCount(let name, let expected, let got):
            "\(name) takes \(expected), not \(got)."
        }
    }
}

// MARK: - Lexer

/// Turns source text into tokens. Hand-written rather than regex-driven so the
/// error messages can point at a character position, which is the difference
/// between a usable inspector field and a red outline.
struct ExpressionLexer {
    enum Token: Hashable {
        case number(Double)
        case string(String)
        case identifier(String)
        case op(String)
        case openParen, closeParen, comma

        var description: String {
            switch self {
            case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
            case .string(let s): "\"\(s)\""
            case .identifier(let s): s
            case .op(let s): s
            case .openParen: "("
            case .closeParen: ")"
            case .comma: ","
            }
        }
    }

    static func tokenize(_ source: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(source)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace { i += 1; continue }

            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var text = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    text.append(chars[i]); i += 1
                }
                tokens.append(.number(Double(text) ?? 0))
                continue
            }

            if c == "\"" || c == "'" {
                let quote = c
                i += 1
                var text = ""
                var closed = false
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count {
                        text.append(chars[i + 1]); i += 2; continue
                    }
                    if chars[i] == quote { closed = true; i += 1; break }
                    text.append(chars[i]); i += 1
                }
                guard closed else { throw ExpressionError.unterminatedString }
                tokens.append(.string(text))
                continue
            }

            if c.isLetter || c == "_" {
                var text = ""
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "." {
                    text.append(chars[i]); i += 1
                }
                tokens.append(.identifier(text))
                continue
            }

            switch c {
            case "(": tokens.append(.openParen); i += 1; continue
            case ")": tokens.append(.closeParen); i += 1; continue
            case ",": tokens.append(.comma); i += 1; continue
            default: break
            }

            // Two-character operators first, so "<=" is never read as "<" then "=".
            if i + 1 < chars.count {
                let pair = String([c, chars[i + 1]])
                if ["==", "!=", "<=", ">=", "&&", "||"].contains(pair) {
                    tokens.append(.op(pair)); i += 2; continue
                }
            }
            if "+-*/%<>!".contains(c) {
                tokens.append(.op(String(c))); i += 1; continue
            }

            throw ExpressionError.unexpectedCharacter(c, at: i)
        }
        return tokens
    }
}

// MARK: - Parser

/// Precedence-climbing parser. Small enough to read in one sitting, which is
/// the point: a language nobody can audit has no business running inside a
/// widget that renders somebody's data every 64 seconds.
struct ExpressionParser {
    private var tokens: [ExpressionLexer.Token]
    private var index = 0

    private init(tokens: [ExpressionLexer.Token]) { self.tokens = tokens }

    static func parse(_ source: String) throws -> Expression {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .value }
        var parser = ExpressionParser(tokens: try ExpressionLexer.tokenize(trimmed))
        let expression = try parser.parseExpression(minimumPrecedence: 0)
        if let leftover = parser.peek() {
            throw ExpressionError.unexpectedToken(leftover.description)
        }
        return expression
    }

    private func peek() -> ExpressionLexer.Token? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func advance() -> ExpressionLexer.Token? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    private mutating func parseExpression(minimumPrecedence: Int) throws -> Expression {
        var left = try parseUnary()

        while case .op(let symbol)? = peek(),
              let binary = Expression.BinaryOperator(rawValue: symbol),
              binary.precedence >= minimumPrecedence {
            _ = advance()
            // Left-associative: the right side binds one level tighter.
            let right = try parseExpression(minimumPrecedence: binary.precedence + 1)
            left = .binary(binary, left, right)
        }
        return left
    }

    private mutating func parseUnary() throws -> Expression {
        if case .op(let symbol)? = peek(), symbol == "-" || symbol == "!" {
            _ = advance()
            let operand = try parseUnary()
            return .unary(symbol == "-" ? .negate : .not, operand)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Expression {
        guard let token = advance() else { throw ExpressionError.unexpectedEnd }

        switch token {
        case .number(let n):
            return .literal(.number(n))

        case .string(let s):
            return .literal(.string(s))

        case .openParen:
            let inner = try parseExpression(minimumPrecedence: 0)
            guard case .closeParen? = peek() else { throw ExpressionError.unexpectedEnd }
            _ = advance()
            return inner

        case .identifier(let name):
            // A bare `value`, `true`, `false` or `null`; anything else followed
            // by "(" is a call, and anything else on its own is a field path,
            // so `current.temperature_2m` works without quotes or ceremony.
            if case .openParen? = peek() {
                _ = advance()
                var arguments: [Expression] = []
                if case .closeParen? = peek() {
                    _ = advance()
                } else {
                    while true {
                        arguments.append(try parseExpression(minimumPrecedence: 0))
                        switch advance() {
                        case .comma?: continue
                        case .closeParen?: break
                        case let other?: throw ExpressionError.unexpectedToken(other.description)
                        case nil: throw ExpressionError.unexpectedEnd
                        }
                        break
                    }
                }
                if name == "field", arguments.count == 1 { return .field(arguments[0]) }
                return .call(name, arguments)
            }

            switch name {
            case "value": return .value
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            case "null": return .literal(.null)
            default: return .field(.literal(.string(name)))
            }

        case .op(let symbol):
            throw ExpressionError.unexpectedToken(symbol)

        case .closeParen:
            throw ExpressionError.unexpectedToken(")")

        case .comma:
            throw ExpressionError.unexpectedToken(",")
        }
    }
}
