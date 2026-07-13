import Foundation

public enum AmountInputParser {
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else { return nil }
        guard token.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }

        let separatorCharacters = token.filter { $0 == "." || $0 == "," }
        guard separatorCharacters.isEmpty == false else {
            return decimal(from: token)
        }

        let dotCount = separatorCharacters.filter { $0 == "." }.count
        let commaCount = separatorCharacters.filter { $0 == "," }.count

        if dotCount > 0 && commaCount > 0 {
            return parseMixedSeparators(token)
        }

        let separator: Character = dotCount > 0 ? "." : ","
        let count = dotCount > 0 ? dotCount : commaCount
        if count > 1 {
            return parseGrouped(token, separator: separator)
        }

        return parseSingleSeparator(token, separator: separator, locale: locale)
    }

    private static func parseMixedSeparators(_ token: String) -> Decimal? {
        guard let lastDot = token.lastIndex(of: "."),
              let lastComma = token.lastIndex(of: ",") else {
            return nil
        }

        let decimalSeparator: Character = lastDot > lastComma ? "." : ","
        let groupingSeparator: Character = decimalSeparator == "." ? "," : "."
        guard token.filter({ $0 == decimalSeparator }).count == 1 else { return nil }

        let decimalIndex = token.lastIndex(of: decimalSeparator)!
        let integerPart = String(token[..<decimalIndex])
        let fractionPart = String(token[token.index(after: decimalIndex)...])
        guard fractionPart.isEmpty == false, fractionPart.allSatisfy(\.isNumber) else { return nil }
        guard groupingIsValid(integerPart, separator: groupingSeparator) else { return nil }

        let integerDigits = integerPart.filter(\.isNumber)
        return decimal(from: "\(integerDigits).\(fractionPart)")
    }

    private static func parseGrouped(_ token: String, separator: Character) -> Decimal? {
        guard groupingIsValid(token, separator: separator) else { return nil }
        return decimal(from: String(token.filter(\.isNumber)))
    }

    private static func parseSingleSeparator(_ token: String, separator: Character, locale: Locale) -> Decimal? {
        guard let index = token.firstIndex(of: separator) else { return nil }
        let before = String(token[..<index])
        let after = String(token[token.index(after: index)...])
        guard before.allSatisfy(\.isNumber), after.allSatisfy(\.isNumber) else { return nil }

        if String(separator) == localeDecimalSeparator(locale) {
            return decimal(from: "\(before.isEmpty ? "0" : before).\(after)")
        }

        if after.count == 3, before.isEmpty == false {
            return decimal(from: before + after)
        }

        if (1...2).contains(after.count) {
            return decimal(from: "\(before.isEmpty ? "0" : before).\(after)")
        }

        return nil
    }

    private static func groupingIsValid(_ token: String, separator: Character) -> Bool {
        let groups = token.split(separator: separator, omittingEmptySubsequences: false)
        guard let first = groups.first, first.isEmpty == false, first.count <= 3 else {
            return false
        }
        guard first.allSatisfy(\.isNumber) else { return false }
        return groups.dropFirst().allSatisfy { group in
            group.count == 3 && group.allSatisfy(\.isNumber)
        }
    }

    private static func decimal(from normalized: String) -> Decimal? {
        Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func localeDecimalSeparator(_ locale: Locale) -> String {
        locale.decimalSeparator ?? Locale(identifier: "en_US_POSIX").decimalSeparator ?? "."
    }
}
