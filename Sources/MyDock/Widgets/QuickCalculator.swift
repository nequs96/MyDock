import Foundation

/// A bounded arithmetic parser. Expressions never execute code or invoke a shell.
enum QuickCalculator {
    enum CalculationError: LocalizedError {
        case invalidExpression, divisionByZero, outOfRange
        var errorDescription: String? {
            switch self {
            case .invalidExpression: "Enter a complete expression using numbers, +, −, ×, ÷, %, and parentheses."
            case .divisionByZero: "Cannot divide by zero."
            case .outOfRange: "This result is outside the supported range."
            }
        }
    }
    /// The decimal key and accepted separator: a comma in comma-decimal locales, otherwise a point.
    static var localDecimalSeparator: String { Locale.current.decimalSeparator == "," ? "," : "." }

    /// A point is always accepted; with a comma separator the comma is accepted too
    /// (the calculator has no grouping input, so this is unambiguous).
    static func calculate(_ expression: String, decimalSeparator: String = QuickCalculator.localDecimalSeparator) throws -> Double {
        guard !expression.isEmpty, expression.count <= 256 else { throw CalculationError.invalidExpression }
        var normalized = expression.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-")
        if decimalSeparator == "," { normalized = normalized.replacingOccurrences(of: ",", with: ".") }
        var parser = Parser(input: Array(normalized.filter { !$0.isWhitespace }))
        let value = try parser.sum()
        guard parser.index == parser.input.count else { throw CalculationError.invalidExpression }
        guard value.isFinite else { throw CalculationError.outOfRange }
        return value
    }
    private struct Parser {
        var input: [Character]
        var index = 0
        var current: Character? { index < input.count ? input[index] : nil }
        mutating func consume(_ token: Character) -> Bool {
            guard current == token else { return false }
            index += 1; return true
        }
        mutating func sum() throws -> Double {
            var value = try product().value
            while let token = current, token == "+" || token == "-" {
                index += 1
                let next = try product()
                // As on a handheld calculator, 50 + 10% adds ten percent of 50; 200 × 15% stays 30.
                let operand = next.isPercent ? value * next.value : next.value
                value = token == "+" ? value + operand : value - operand
            }
            return value
        }
        /// `isPercent` is true only when the term is a single percentage, such as `10%`.
        mutating func product() throws -> (value: Double, isPercent: Bool) {
            var (value, isPercent) = try atom()
            while let token = current, token == "*" || token == "/" {
                index += 1
                let next = try atom().value
                if token == "/", next == 0 { throw CalculationError.divisionByZero }
                value = token == "*" ? value * next : value / next
                isPercent = false
            }
            return (value, isPercent)
        }
        mutating func atom() throws -> (value: Double, isPercent: Bool) {
            if consume("+") { return try atom() }
            if consume("-") { let operand = try atom(); return (-operand.value, operand.isPercent) }
            var value: Double
            if consume("(") {
                value = try sum()
                guard consume(")") else { throw CalculationError.invalidExpression }
            } else {
                let start = index
                while let c = current, c.isASCII && (c.isNumber || c == ".") { index += 1 }
                guard index > start, let number = Double(String(input[start..<index])) else { throw CalculationError.invalidExpression }
                value = number
            }
            let isPercent = consume("%")
            if isPercent { value /= 100 }
            guard value.isFinite else { throw CalculationError.outOfRange }
            return (value, isPercent)
        }
    }
}
