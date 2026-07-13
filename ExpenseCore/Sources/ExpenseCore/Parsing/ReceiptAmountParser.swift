import Foundation

public struct ParsedAmount: Equatable, Sendable {
    public var amount: Decimal
    public var currencyCode: String
    public var evidence: String

    public init(amount: Decimal, currencyCode: String, evidence: String) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.evidence = evidence
    }
}

public enum ReceiptAmountParser {
    private static var amountPattern: String {
        let currencyCodes = ReceiptLanguageProfiles.allCurrencyCodes
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let currencySymbols = ReceiptLanguageProfiles.allCurrencySymbols.keys
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "")
        return #"(?i)(?<![A-Za-z0-9])(?:(\#(currencyCodes))\s*)?([\#(currencySymbols)]?\s*\d[\d,.]*)(?:\s*(\#(currencyCodes)|[\#(currencySymbols)]))?(?![A-Za-z0-9,.])"#
    }

    public static func parse(_ text: String, defaultCurrencyCode: String) -> ParsedAmount? {
        parseAll(in: text, defaultCurrencyCode: defaultCurrencyCode).first
    }

    public static func parseAll(in text: String, defaultCurrencyCode: String) -> [ParsedAmount] {
        guard let regex = try? NSRegularExpression(pattern: amountPattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let evidence = String(text[Range(match.range, in: text)!]).trimmingCharacters(in: .whitespacesAndNewlines)
            let codeBefore = string(at: 1, in: text, match: match)
            guard let numberToken = string(at: 2, in: text, match: match) else {
                return nil
            }
            let codeAfter = string(at: 3, in: text, match: match)
            guard let amount = decimal(from: numberToken) else {
                return nil
            }
            let currencyCode = currencyCode(
                codeBefore: codeBefore,
                token: numberToken,
                codeAfter: codeAfter,
                defaultCurrencyCode: defaultCurrencyCode
            )
            return ParsedAmount(amount: amount, currencyCode: currencyCode, evidence: evidence)
        }
    }

    static func isPureAmountLine(_ line: String, defaultCurrencyCode: String) -> Bool {
        guard parse(line, defaultCurrencyCode: defaultCurrencyCode) != nil else { return false }
        return line.rangeOfCharacter(from: .letters) == nil
    }

    static func isStandaloneMonetaryLine(_ line: String, defaultCurrencyCode: String) -> Bool {
        let amounts = parseAll(in: line, defaultCurrencyCode: defaultCurrencyCode)
        guard amounts.count == 1, let evidence = amounts.first?.evidence else { return false }
        let residual = line.replacingOccurrences(of: evidence, with: "")
        let letters = residual.filter(\.isLetter).uppercased()
        return letters.isEmpty
            || letters == "RS"
            || ReceiptLanguageProfiles.allCurrencyCodes.contains(letters)
    }

    static func isLikelyQuantityLine(at offset: Int, in lines: [String], defaultCurrencyCode: String) -> Bool {
        guard lines.indices.contains(offset + 1) else { return false }
        return isPureAmountLine(lines[offset], defaultCurrencyCode: defaultCurrencyCode)
            && lines[offset + 1].contains("%")
    }

    static func isLikelyUnitRateLine(at offset: Int, in lines: [String], defaultCurrencyCode: String) -> Bool {
        guard offset > 0, lines.indices.contains(offset + 1) else { return false }
        return lines[offset - 1].contains("%")
            && isPureAmountLine(lines[offset + 1], defaultCurrencyCode: defaultCurrencyCode)
    }

    private static func string(at index: Int, in text: String, match: NSTextCheckingResult) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currencyCode(codeBefore: String?, token: String, codeAfter: String?, defaultCurrencyCode: String) -> String {
        for candidate in [codeBefore, codeAfter] {
            guard let candidate, !candidate.isEmpty else { continue }
            let upper = candidate.uppercased()
            if ReceiptLanguageProfiles.allCurrencyCodes.contains(upper) {
                return upper
            }
            if let symbolCode = ReceiptLanguageProfiles.allCurrencySymbols[candidate] {
                return symbolCode
            }
        }

        for (symbol, code) in ReceiptLanguageProfiles.allCurrencySymbols where token.contains(symbol) {
            return code
        }

        return defaultCurrencyCode.uppercased()
    }

    private static func decimal(from rawToken: String) -> Decimal? {
        var token = rawToken
        for symbol in ReceiptLanguageProfiles.allCurrencySymbols.keys {
            token = token.replacingOccurrences(of: symbol, with: "")
        }
        for code in ReceiptLanguageProfiles.allCurrencyCodes {
            token = token.replacingOccurrences(of: code, with: "", options: [.caseInsensitive])
        }
        token = token.replacingOccurrences(of: " ", with: "")

        let comma = token.lastIndex(of: ",")
        let dot = token.lastIndex(of: ".")
        let decimalSeparator: Character?
        if let comma, let dot {
            decimalSeparator = comma > dot ? "," : "."
        } else if let comma {
            decimalSeparator = isDecimalSeparator(comma, in: token) ? "," : nil
        } else if let dot {
            decimalSeparator = isDecimalSeparator(dot, in: token) ? "." : nil
        } else {
            decimalSeparator = nil
        }

        var normalized = ""
        for character in token {
            if character.isNumber {
                normalized.append(character)
            } else if let decimalSeparator, character == decimalSeparator {
                normalized.append(".")
            }
        }

        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isDecimalSeparator(_ index: String.Index, in token: String) -> Bool {
        let digitsAfterSeparator = token[token.index(after: index)..<token.endIndex].filter(\.isNumber).count
        return (1...2).contains(digitsAfterSeparator)
    }
}
