import Foundation

/// Text with expressions in it: `Only {bytes(disk.free)} left.`
///
/// An alert that says "running low on space" is worth less than one that says
/// how much is left, and the value that triggered the rule is exactly the value
/// worth quoting. The braces reuse the same evaluator as everything else, so
/// there is no second language to learn or maintain.
enum TextTemplate {

    static func render(_ template: String,
                       tree: DataValue?,
                       now: Date = Date()) -> String {
        guard template.contains("{") else { return template }

        var out = ""
        var expression = ""
        var depth = 0

        for character in template {
            switch character {
            case "{":
                depth += 1
                if depth == 1 { continue }
                expression.append(character)
            case "}":
                depth -= 1
                if depth == 0 {
                    out += evaluate(expression, tree: tree, now: now)
                    expression = ""
                } else if depth > 0 {
                    expression.append(character)
                } else {
                    // A stray closing brace is a typo, not an error worth
                    // failing an alert over.
                    depth = 0
                    out.append(character)
                }
            default:
                depth > 0 ? expression.append(character) : out.append(character)
            }
        }
        // An unclosed brace keeps whatever was typed after it, rather than
        // silently eating the rest of the sentence.
        if depth > 0 { out += "{" + expression }
        return out
    }

    private static func evaluate(_ source: String, tree: DataValue?, now: Date) -> String {
        guard let program = try? ExpressionParser.parse(source) else { return "?" }
        let value = ExpressionEvaluator(tree: tree, ownValue: nil, now: now).evaluate(program)
        return value == .null ? "—" : value.stringValue
    }
}
