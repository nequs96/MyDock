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
    static func calculate(_ expression: String) throws -> Double {
        guard !expression.isEmpty, expression.count <= 256 else { throw CalculationError.invalidExpression }
        var parser = Parser(input: Array(expression.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-").filter { !$0.isWhitespace }))
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
            var value = try product()
            while let token = current, token == "+" || token == "-" {
                index += 1
                let next = try product()
                value = token == "+" ? value + next : value - next
            }
            return value
        }
        mutating func product() throws -> Double {
            var value = try atom()
            while let token = current, token == "*" || token == "/" {
                index += 1
                let next = try atom()
                if token == "/", next == 0 { throw CalculationError.divisionByZero }
                value = token == "*" ? value * next : value / next
            }
            return value
        }
        mutating func atom() throws -> Double {
            if consume("+") { return try atom() }
            if consume("-") { return try -atom() }
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
            if consume("%") { value /= 100 }
            guard value.isFinite else { throw CalculationError.outOfRange }
            return value
        }
    }
}
