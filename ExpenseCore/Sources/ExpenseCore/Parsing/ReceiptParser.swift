import Foundation

public enum FieldConfidence: String, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct ParsedField<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var confidence: FieldConfidence
    public var evidence: String

    public init(value: Value, confidence: FieldConfidence, evidence: String) {
        self.value = value
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct ParsedReceipt: Equatable, Sendable {
    public var vendor: ParsedField<String>?
    public var date: ParsedField<Date>?
    public var dateAlternates: [ParsedField<Date>]
    public var totalAmount: ParsedField<Decimal>?
    public var currencyCode: ParsedField<String>?
    public var paymentMethod: ParsedField<PaymentMethod>?
    public var rawText: String

    public init(
        vendor: ParsedField<String>? = nil,
        date: ParsedField<Date>? = nil,
        dateAlternates: [ParsedField<Date>] = [],
        totalAmount: ParsedField<Decimal>? = nil,
        currencyCode: ParsedField<String>? = nil,
        paymentMethod: ParsedField<PaymentMethod>? = nil,
        rawText: String
    ) {
        self.vendor = vendor
        self.date = date
        self.dateAlternates = dateAlternates
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.paymentMethod = paymentMethod
        self.rawText = rawText
    }
}

public struct ReceiptParser: Sendable {
    private let referenceDate: Date
    private let defaultCurrencyCode: String
    private let locale: Locale
    private let calendar: Calendar

    public init(referenceDate: Date = Date(), defaultCurrencyCode: String, locale: Locale = .current) {
        self.referenceDate = referenceDate
        self.defaultCurrencyCode = defaultCurrencyCode.uppercased()
        self.locale = locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    public func parse(_ text: String) -> ParsedReceipt {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let vendor = parseVendor(from: lines)
        let dateOptions = parseDateOptions(from: lines, fullText: text)
        let total = parseTotal(from: lines)
        let currency = total.map {
            ParsedField(value: $0.currencyCode, confidence: $0.confidence, evidence: $0.evidence)
        }
        let payment = parsePayment(from: text)

        return ParsedReceipt(
            vendor: vendor,
            date: dateOptions.first,
            dateAlternates: Array(dateOptions.dropFirst()),
            totalAmount: total.map { ParsedField(value: $0.amount, confidence: $0.confidence, evidence: $0.evidence) },
            currencyCode: currency,
            paymentMethod: payment,
            rawText: text
        )
    }

    private func parseVendor(from lines: [String]) -> ParsedField<String>? {
        let candidates = lines.filter { line in
            let normalized = normalize(line)
            guard line.rangeOfCharacter(from: .letters) != nil else { return false }
            guard containsAny(normalized, ReceiptLanguageProfiles.allTotalLabels) == false else { return false }
            guard containsAny(normalized, ReceiptLanguageProfiles.allSubtotalLabels) == false else { return false }
            guard containsAny(normalized, ReceiptLanguageProfiles.allTaxLabels) == false else { return false }
            guard containsAny(normalized, ReceiptLanguageProfiles.allCashHints) == false else { return false }
            guard containsAny(normalized, ReceiptLanguageProfiles.allCardHints) == false else { return false }
            guard containsAny(normalized, ReceiptLanguageProfiles.allVendorSkipKeywords) == false else { return false }
            return ReceiptAmountParser.parse(line, defaultCurrencyCode: defaultCurrencyCode) == nil
        }
        let vendor = candidates.first {
            ReceiptLanguageProfiles.isLikelyLocationHeader($0, in: lines) == false
        } ?? candidates.first
        return vendor.map { ParsedField(value: $0, confidence: .medium, evidence: $0) }
    }

    private func parseDateOptions(from lines: [String], fullText: String) -> [ParsedField<Date>] {
        for line in lines {
            for candidate in dateCandidates(in: line) {
                let dates = parseDateCandidate(candidate, fullText: fullText).filter(isSane)
                if dates.isEmpty == false {
                    return dates.map { ParsedField(value: $0, confidence: .medium, evidence: line) }
                }
            }
        }
        return []
    }

    private func dateCandidates(in line: String) -> [String] {
        let patterns = [
            #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            #"\d{1,2}[./-]\d{1,2}[./-]\d{2,4}"#,
            #"[A-Za-z]{3,9}\s+\d{1,2},\s+\d{4}"#
        ]
        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return regex.matches(in: line, range: range).compactMap { match in
                Range(match.range, in: line).map { String(line[$0]) }
            }
        }
    }

    private func parseDateCandidate(_ candidate: String, fullText: String) -> [Date] {
        var dates: [Date] = []
        for format in relevantDateFormats(for: fullText) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format
            if let date = formatter.date(from: candidate) {
                let normalizedDate = calendar.startOfDay(for: date)
                if dates.contains(normalizedDate) == false {
                    dates.append(normalizedDate)
                }
            }
        }
        return Array(dates.prefix(2))
    }

    private func relevantDateFormats(for text: String) -> [String] {
        var formats: [String] = []
        for profile in ReceiptLanguageProfiles.profiles(relevantTo: text, locale: locale) {
            for format in profile.dateFormats where formats.contains(format) == false {
                formats.append(format)
            }
        }
        return formats
    }

    private func isSane(_ date: Date) -> Bool {
        guard let oldest = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2000, month: 1, day: 1).date else {
            return false
        }
        return date >= oldest && date <= calendar.startOfDay(for: referenceDate)
    }

    private struct TotalCandidate {
        var amount: Decimal
        var currencyCode: String
        var evidence: String
        var confidence: FieldConfidence
        var isLabeledTotal: Bool
    }

    private func parseTotal(from lines: [String]) -> TotalCandidate? {
        var subtotal = Decimal.zero
        var tax = Decimal.zero
        var hasSubtotal = false
        var hasTax = false
        var labeledTotals: [TotalCandidate] = []
        var fallbackAmounts: [TotalCandidate] = []

        for (offset, line) in lines.enumerated() {
            let normalized = normalize(line)
            if dateCandidates(in: line).isEmpty == false {
                continue
            }
            let amounts = ReceiptAmountParser.parseAll(in: line, defaultCurrencyCode: defaultCurrencyCode)
            guard let lastAmount = amounts.last else { continue }

            if ReceiptAmountParser.isLikelyQuantityLine(at: offset, in: lines, defaultCurrencyCode: defaultCurrencyCode)
                || ReceiptAmountParser.isLikelyUnitRateLine(at: offset, in: lines, defaultCurrencyCode: defaultCurrencyCode) {
                continue
            }

            if containsAny(normalized, ReceiptLanguageProfiles.allSubtotalLabels) {
                subtotal += lastAmount.amount
                hasSubtotal = true
                continue
            }

            if containsAny(normalized, ReceiptLanguageProfiles.allTaxLabels) {
                tax += lastAmount.amount
                hasTax = true
                continue
            }

            let followsTotalLabel = offset > 0
                && ReceiptLanguageProfiles.containsApproximateTotalLabel(in: lines[offset - 1])
                && ReceiptAmountParser.isStandaloneMonetaryLine(line, defaultCurrencyCode: defaultCurrencyCode)
            if containsAny(normalized, ReceiptLanguageProfiles.allTotalLabels) || followsTotalLabel {
                labeledTotals.append(
                    TotalCandidate(
                        amount: lastAmount.amount,
                        currencyCode: lastAmount.currencyCode,
                        evidence: line,
                        confidence: .high,
                        isLabeledTotal: true
                    )
                )
            } else if shouldUseFallbackAmount(line: line, normalized: normalized, amount: lastAmount) {
                fallbackAmounts.append(
                    TotalCandidate(
                        amount: lastAmount.amount,
                        currencyCode: lastAmount.currencyCode,
                        evidence: line,
                        confidence: .low,
                        isLabeledTotal: false
                    )
                )
            }
        }

        if let total = labeledTotals.last {
            if hasSubtotal && hasTax && reconciles(total: total.amount, subtotal: subtotal, tax: tax) {
                return TotalCandidate(
                    amount: total.amount,
                    currencyCode: total.currencyCode,
                    evidence: total.evidence,
                    confidence: .high,
                    isLabeledTotal: true
                )
            }
            return total
        }

        return fallbackAmounts.max { $0.amount < $1.amount }
    }

    private func shouldUseFallbackAmount(line: String, normalized: String, amount: ParsedAmount) -> Bool {
        guard isMetadataLine(normalized) == false else {
            return false
        }
        return isPlausibleFallbackAmount(amount, line: line)
    }

    private func isMetadataLine(_ normalized: String) -> Bool {
        ReceiptLanguageProfiles.allMetadataKeywords.contains { normalized.contains($0) }
    }

    private func isPlausibleFallbackAmount(_ amount: ParsedAmount, line: String) -> Bool {
        guard amount.amount > Decimal.zero else {
            return false
        }

        let evidence = amount.evidence
        let digitCount = evidence.filter(\.isNumber).count
        let hasDecimalSeparator = evidence.contains(".") || evidence.contains(",")
        let hasCurrencyMarker = containsCurrencyMarker(in: evidence)

        if digitCount > 7 && hasCurrencyMarker == false {
            return false
        }

        if hasDecimalSeparator == false && hasCurrencyMarker == false && digitCount > 5 {
            return false
        }

        if amount.amount > Decimal(1_000_000) && hasCurrencyMarker == false {
            return false
        }

        return line.rangeOfCharacter(from: .letters) == nil || hasDecimalSeparator || hasCurrencyMarker
    }

    private func containsCurrencyMarker(in value: String) -> Bool {
        let uppercased = value.uppercased()
        if ReceiptLanguageProfiles.allCurrencyCodes.contains(where: { uppercased.contains($0) }) {
            return true
        }
        return ReceiptLanguageProfiles.allCurrencySymbols.keys.contains { value.contains($0) }
    }

    private func reconciles(total: Decimal, subtotal: Decimal, tax: Decimal) -> Bool {
        var difference = total - subtotal - tax
        if difference < Decimal.zero {
            difference *= Decimal(-1)
        }
        return difference <= Decimal(string: "0.02")!
    }

    private func parsePayment(from text: String) -> ParsedField<PaymentMethod>? {
        let normalized = normalize(text)
        if let evidence = firstMatchingHint(in: normalized, hints: ReceiptLanguageProfiles.allCashHints) {
            return ParsedField(value: .cash, confidence: .medium, evidence: evidence)
        }
        if let evidence = firstMatchingHint(in: normalized, hints: ReceiptLanguageProfiles.allCardHints) {
            return ParsedField(value: .card, confidence: .medium, evidence: evidence)
        }
        return nil
    }

    private func firstMatchingHint(in normalized: String, hints: Set<String>) -> String? {
        hints.sorted { $0.count > $1.count }.first { normalized.contains($0) }
    }

    private func containsAny(_ normalized: String, _ candidates: Set<String>) -> Bool {
        candidates.contains { candidate in
            normalized.contains(candidate)
        }
    }

    private func normalize(_ value: String) -> String {
        ReceiptLanguageProfile.normalize(value)
    }
}
