import Foundation

/// Pure state machine & inline math evaluator for the zero-lag custom food keypad (§6).
/// - Pre-selects the remembered serving quantity (`isPreselected == true`).
/// - First digit (`0–9` or `.`) overwrites the remembered value in 1 tap (`"150"` -> `"2"`).
/// - Supports inline `+` and `×` kitchen-scale math (`"140+65"` -> `205`, `"1.5×2"` -> `3`) and `"00"` (`1` + `00` -> `100`).
public struct InlineQuantityCalculator: Sendable, Equatable {
    public enum Key: String, Sendable {
        case zero = "0"
        case doubleZero = "00"
        case one = "1"
        case two = "2"
        case three = "3"
        case four = "4"
        case five = "5"
        case six = "6"
        case seven = "7"
        case eight = "8"
        case nine = "9"
        case decimal = "."
        case plus = "+"
        case minus = "-"
        case multiply = "×"
        case equals = "="
        case backspace = "⌫"
    }

    public private(set) var expression: String
    public private(set) var isPreselected: Bool

    public init(initialText: String = "1", isPreselected: Bool = true) {
        let cleaned = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expression = cleaned.isEmpty ? "1" : cleaned
        self.isPreselected = isPreselected
    }

    public mutating func reset(to text: String, preselected: Bool = true) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expression = cleaned.isEmpty ? "1" : cleaned
        self.isPreselected = preselected
    }

    public mutating func tap(_ key: Key) {
        switch key {
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
            let digit = key.rawValue
            if isPreselected {
                expression = digit
                isPreselected = false
                return
            }
            let token = lastNumericToken(in: expression)
            if token == "0" {
                expression.removeLast()
                expression.append(digit)
            } else if expression.count < 16 {
                expression.append(digit)
            }

        case .doubleZero:
            if isPreselected {
                expression = "0"
                isPreselected = false
                return
            }
            let token = lastNumericToken(in: expression)
            if token.isEmpty {
                expression.append("0")
            } else if token == "0" {
                return
            } else if expression.count <= 14 {
                expression.append("00")
            }

        case .decimal:
            if isPreselected {
                expression = "0."
                isPreselected = false
                return
            }
            let token = lastNumericToken(in: expression)
            guard !token.contains(".") else { return }
            if token.isEmpty {
                expression.append("0.")
            } else if expression.count < 16 {
                expression.append(".")
            }

        case .plus, .minus, .multiply:
            let op = key.rawValue
            isPreselected = false
            guard !expression.isEmpty else { return }
            if let last = expression.last, last == "+" || last == "-" || last == "×" {
                expression.removeLast()
                expression.append(op)
            } else if let last = expression.last, last == "." {
                expression.append("0")
                expression.append(op)
            } else if expression.count < 15 {
                expression.append(op)
            }

        case .equals:
            let val = evaluatedValue
            expression = Self.formatClean(val)
            isPreselected = false

        case .backspace:
            if isPreselected {
                isPreselected = false
            }
            if !expression.isEmpty {
                expression.removeLast()
            }
            if expression.isEmpty {
                expression = "0"
            }
        }
    }

    public var hasOperator: Bool {
        expression.contains("+") || expression.contains("-") || expression.contains("×")
    }

    /// Evaluates `+`, `-`, and `×` with standard kitchen-scale container tare math (`250-70` -> `180`).
    /// Trailing operators (`"140+"`) evaluate cleanly to the completed prefix (`140.0`).
    public var evaluatedValue: Double {
        Self.evaluate(expression)
    }

    public static func evaluate(_ raw: String) -> Double {
        var sanitized = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "−", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let last = sanitized.last, last == "+" || last == "-" || last == "×" || last == "." {
            sanitized.removeLast()
        }
        guard !sanitized.isEmpty else { return 0 }

        // Tokenize additions and subtractions: replace '-' with '+-'
        var normalized = ""
        var prevChar: Character? = nil
        for ch in sanitized {
            if ch == "-" {
                if let p = prevChar, p != "+" && p != "-" && p != "×" {
                    normalized.append("+")
                }
            }
            normalized.append(ch)
            prevChar = ch
        }

        let additiveTerms = normalized.split(separator: "+", omittingEmptySubsequences: true)
        guard !additiveTerms.isEmpty else { return 0 }

        var sum = 0.0
        for term in additiveTerms {
            let factors = term.split(separator: "×", omittingEmptySubsequences: true)
            guard !factors.isEmpty else { continue }
            var product = 1.0
            for factor in factors {
                product *= (Double(factor) ?? 0.0)
            }
            sum += product
        }
        return max(0.0, sum)
    }

    public static func formatClean(_ val: Double) -> String {
        if abs(val.rounded() - val) < 0.015 {
            return String(Int(val.rounded()))
        }
        let oneDec = (val * 10).rounded() / 10.0
        if abs(oneDec - val) < 0.015 {
            return String(format: "%.1f", oneDec)
        }
        return String(format: "%.2f", val)
    }

    private func lastNumericToken(in text: String) -> String {
        if let idx = text.lastIndex(where: { $0 == "+" || $0 == "×" }) {
            return String(text[text.index(after: idx)...])
        }
        return text
    }
}
