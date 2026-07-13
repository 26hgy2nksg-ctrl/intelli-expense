import Foundation

public struct ReceiptPromptEvidence: Equatable, Sendable {
    public var promptText: String
    public var vendorCandidates: [ReceiptVendorEvidenceCandidate]
    public var amountCandidates: [ReceiptAmountEvidenceCandidate]
    public var parserLines: [String]
    public var tailLines: [String]
    public var tokenCount: Int?

    public init(
        promptText: String,
        vendorCandidates: [ReceiptVendorEvidenceCandidate],
        amountCandidates: [ReceiptAmountEvidenceCandidate],
        parserLines: [String],
        tailLines: [String],
        tokenCount: Int? = nil
    ) {
        self.promptText = promptText
        self.vendorCandidates = vendorCandidates
        self.amountCandidates = amountCandidates
        self.parserLines = parserLines
        self.tailLines = tailLines
        self.tokenCount = tokenCount
    }
}

public struct ReceiptVendorEvidenceCandidate: Equatable, Sendable {
    public var id: String
    public var text: String
    public var evidence: String

    public init(id: String, text: String, evidence: String) {
        self.id = id
        self.text = text
        self.evidence = evidence
    }
}

public enum ReceiptAmountEvidenceRole: String, Equatable, Sendable {
    case finalTotal
    case parserSupportedTotal
    case fallbackAmount
    case subtotal
    case tax
    case payment
    case quantity
    case unitRate
    case identifier
    case date
    case other

    public var supportsModelTotalByDefault: Bool {
        switch self {
        case .finalTotal, .parserSupportedTotal:
            true
        case .fallbackAmount, .subtotal, .tax, .payment, .quantity, .unitRate, .identifier, .date, .other:
            false
        }
    }

    var promptLabel: String {
        switch self {
        case .finalTotal:
            "final payable total"
        case .parserSupportedTotal:
            "parser-supported total"
        case .fallbackAmount:
            "fallback amount"
        case .subtotal:
            "subtotal"
        case .tax:
            "tax"
        case .payment:
            "payment/card number"
        case .quantity:
            "item quantity"
        case .unitRate:
            "item unit rate"
        case .identifier:
            "identifier"
        case .date:
            "date"
        case .other:
            "other amount"
        }
    }

    var promptPriority: Int {
        switch self {
        case .finalTotal:
            0
        case .parserSupportedTotal:
            1
        case .fallbackAmount:
            2
        case .subtotal:
            3
        case .tax:
            4
        case .payment:
            5
        case .quantity:
            6
        case .unitRate:
            7
        case .identifier:
            8
        case .date:
            9
        case .other:
            10
        }
    }
}

public struct ReceiptAmountEvidenceCandidate: Equatable, Sendable {
    public var id: String
    public var amount: Decimal
    public var currencyCode: String
    public var evidence: String
    public var role: ReceiptAmountEvidenceRole
    public var supportsModelTotal: Bool

    public init(
        id: String,
        amount: Decimal,
        currencyCode: String,
        evidence: String,
        role: ReceiptAmountEvidenceRole,
        supportsModelTotal: Bool
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.evidence = evidence
        self.role = role
        self.supportsModelTotal = supportsModelTotal
    }
}

public struct ReceiptPromptEvidenceBuilder: Sendable {
    public static let defaultCharacterBudget = 4_000

    public var characterBudget: Int
    public var defaultCurrencyCode: String

    public init(characterBudget: Int = Self.defaultCharacterBudget, defaultCurrencyCode: String = "USD") {
        self.characterBudget = max(200, characterBudget)
        self.defaultCurrencyCode = defaultCurrencyCode.uppercased()
    }

    public func build(rawText: String, deterministicReceipt: ParsedReceipt?) -> ReceiptPromptEvidence {
        build(
            rawText: rawText,
            deterministicReceipt: deterministicReceipt,
            budget: characterBudget,
            measure: { $0.count },
            recordsTokenCount: false
        )
    }

    public func build(
        rawText: String,
        deterministicReceipt: ParsedReceipt?,
        tokenBudget: Int,
        tokenCounter: (String) -> Int
    ) -> ReceiptPromptEvidence {
        build(
            rawText: rawText,
            deterministicReceipt: deterministicReceipt,
            budget: max(1, tokenBudget),
            measure: tokenCounter,
            recordsTokenCount: true
        )
    }

    private func build(
        rawText: String,
        deterministicReceipt: ParsedReceipt?,
        budget: Int,
        measure: (String) -> Int,
        recordsTokenCount: Bool
    ) -> ReceiptPromptEvidence {
        let lines = indexedLines(from: rawText)
        let vendors = vendorCandidates(from: lines)
        let amounts = amountCandidates(from: lines, deterministicReceipt: deterministicReceipt)
        let parserLines = parserEvidenceLines(for: deterministicReceipt)
        let tailLines = Array(lines.suffix(6).map(\.text))
        let promptText = makePromptText(
            vendors: vendors,
            amounts: amounts,
            parserLines: parserLines,
            tailLines: tailLines,
            budget: budget,
            measure: measure
        )

        return ReceiptPromptEvidence(
            promptText: promptText,
            vendorCandidates: vendors,
            amountCandidates: amounts,
            parserLines: parserLines,
            tailLines: tailLines,
            tokenCount: recordsTokenCount ? measure(promptText) : nil
        )
    }

    private struct IndexedLine {
        var index: Int
        var text: String
        var normalized: String
    }

    private func indexedLines(from rawText: String) -> [IndexedLine] {
        rawText
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else { return nil }
                return IndexedLine(index: index, text: trimmed, normalized: ReceiptLanguageProfile.normalize(trimmed))
            }
    }

    private func vendorCandidates(from lines: [IndexedLine]) -> [ReceiptVendorEvidenceCandidate] {
        var candidates: [ReceiptVendorEvidenceCandidate] = []
        var seen = Set<String>()

        for offset in lines.indices.prefix(14) {
            let line = lines[offset]
            if shouldStopVendorScan(at: offset, in: lines, alreadyFoundCandidate: candidates.isEmpty == false) {
                break
            }
            guard isMerchantLikeVendorLine(line, at: offset, in: lines) else {
                continue
            }
            if candidates.isEmpty == false, isLikelyLegalEntityLine(line, at: offset, in: lines) {
                continue
            }

            let key = compactIdentifier(line.text)
            guard seen.insert(key).inserted else { continue }
            candidates.append(
                ReceiptVendorEvidenceCandidate(
                    id: "V\(candidates.count + 1)",
                    text: line.text,
                    evidence: line.text
                )
            )
            if candidates.count >= 3 {
                break
            }
        }

        let sourceLines = lines.map(\.text)
        return candidates
            .enumerated()
            .sorted { lhs, rhs in
                let lhsIsLocation = ReceiptLanguageProfiles.isLikelyLocationHeader(lhs.element.text, in: sourceLines)
                let rhsIsLocation = ReceiptLanguageProfiles.isLikelyLocationHeader(rhs.element.text, in: sourceLines)
                if lhsIsLocation != rhsIsLocation {
                    return lhsIsLocation == false
                }
                return lhs.offset < rhs.offset
            }
            .enumerated()
            .map { index, pair in
                var candidate = pair.element
                candidate.id = "V\(index + 1)"
                return candidate
            }
    }

    private func shouldStopVendorScan(at offset: Int, in lines: [IndexedLine], alreadyFoundCandidate: Bool) -> Bool {
        guard alreadyFoundCandidate else { return false }
        let line = lines[offset]
        return looksLikeDateLine(line.text)
            || containsAny(line.normalized, ReceiptLanguageProfiles.allMetadataKeywords)
            || containsAny(line.normalized, ReceiptLanguageProfiles.allVendorSkipKeywords)
            || ReceiptAmountParser.parse(line.text, defaultCurrencyCode: defaultCurrencyCode) != nil
    }

    private func isMerchantLikeVendorLine(_ line: IndexedLine, at offset: Int, in lines: [IndexedLine]) -> Bool {
        guard line.text.rangeOfCharacter(from: .letters) != nil else { return false }
        guard isPureAmountLine(line.text) == false else { return false }
        guard looksLikeDateLine(line.text) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allTotalLabels) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allSubtotalLabels) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allTaxLabels) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allCashHints) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allCardHints) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allMetadataKeywords) == false else { return false }
        guard containsAny(line.normalized, ReceiptLanguageProfiles.allVendorSkipKeywords) == false else { return false }

        return true
    }

    private func isLikelyLegalEntityLine(_ line: IndexedLine, at offset: Int, in lines: [IndexedLine]) -> Bool {
        let legalSignals = ["limited", "ltd", "private", "pvt", "llc", "inc", "services"]
        if legalSignals.contains(where: { line.normalized.contains($0) }) {
            return true
        }
        if lines.indices.contains(offset + 1), lines[offset + 1].normalized.contains("limited") {
            return true
        }
        if offset > 0, lines[offset - 1].normalized.contains("services"), line.normalized.contains("limited") {
            return true
        }
        return false
    }

    private func isPureAmountLine(_ value: String) -> Bool {
        guard ReceiptAmountParser.parse(value, defaultCurrencyCode: defaultCurrencyCode) != nil else {
            return false
        }
        let stripped = value.filter { character in
            character.isLetter
        }
        return stripped.isEmpty
    }

    private func amountCandidates(
        from lines: [IndexedLine],
        deterministicReceipt: ParsedReceipt?
    ) -> [ReceiptAmountEvidenceCandidate] {
        var candidates: [ReceiptAmountEvidenceCandidate] = []

        for (offset, line) in lines.enumerated() {
            let parsedAmounts = ReceiptAmountParser.parseAll(in: line.text, defaultCurrencyCode: defaultCurrencyCode)
            for parsedAmount in parsedAmounts {
                let role = amountRole(for: line, at: offset, in: lines, amount: parsedAmount)
                candidates.append(
                    ReceiptAmountEvidenceCandidate(
                        id: "",
                        amount: parsedAmount.amount,
                        currencyCode: parsedAmount.currencyCode,
                        evidence: line.text,
                        role: role,
                        supportsModelTotal: role.supportsModelTotalByDefault
                    )
                )
            }
        }

        if let total = deterministicReceipt?.totalAmount {
            let currencyCode = deterministicReceipt?.currencyCode?.value ?? defaultCurrencyCode
            candidates.append(
                ReceiptAmountEvidenceCandidate(
                    id: "",
                    amount: total.value,
                    currencyCode: currencyCode,
                    evidence: total.evidence,
                    role: .parserSupportedTotal,
                    supportsModelTotal: true
                )
            )
        }

        return candidates
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.role.promptPriority != rhs.element.role.promptPriority {
                    return lhs.element.role.promptPriority < rhs.element.role.promptPriority
                }
                return lhs.offset < rhs.offset
            }
            .enumerated()
            .map { index, pair in
                var candidate = pair.element
                candidate.id = "A\(index + 1)"
                return candidate
            }
    }

    private func amountRole(
        for line: IndexedLine,
        at offset: Int,
        in lines: [IndexedLine],
        amount: ParsedAmount
    ) -> ReceiptAmountEvidenceRole {
        if looksLikeDateLine(line.text) {
            return .date
        }
        if containsAny(line.normalized, ReceiptLanguageProfiles.allSubtotalLabels) {
            return .subtotal
        }
        if containsAny(line.normalized, ReceiptLanguageProfiles.allTaxLabels) {
            return .tax
        }
        if containsAny(line.normalized, ReceiptLanguageProfiles.allCashHints)
            || containsAny(line.normalized, ReceiptLanguageProfiles.allCardHints) {
            return .payment
        }
        if containsAny(line.normalized, ReceiptLanguageProfiles.allMetadataKeywords)
            || containsAny(line.normalized, ReceiptLanguageProfiles.allVendorSkipKeywords) {
            return .identifier
        }
        if containsAny(line.normalized, ReceiptLanguageProfiles.allTotalLabels) {
            return .finalTotal
        }
        if offset > 0 {
            let previousLine = lines[offset - 1]
            if containsAny(previousLine.normalized, ReceiptLanguageProfiles.allTaxLabels) {
                return .tax
            }
            if containsAny(previousLine.normalized, ReceiptLanguageProfiles.allCashHints)
                || containsAny(previousLine.normalized, ReceiptLanguageProfiles.allCardHints) {
                return .payment
            }
            if ReceiptLanguageProfiles.containsApproximateTotalLabel(in: previousLine.text),
               ReceiptAmountParser.isStandaloneMonetaryLine(line.text, defaultCurrencyCode: defaultCurrencyCode) {
                return .finalTotal
            }
        }
        let sourceLines = lines.map(\.text)
        if ReceiptAmountParser.isLikelyQuantityLine(at: offset, in: sourceLines, defaultCurrencyCode: defaultCurrencyCode) {
            return .quantity
        }
        if ReceiptAmountParser.isLikelyUnitRateLine(at: offset, in: sourceLines, defaultCurrencyCode: defaultCurrencyCode) {
            return .unitRate
        }
        if isPlausibleFallbackAmount(amount, line: line.text) {
            return .fallbackAmount
        }
        return .other
    }

    private func isPlausibleFallbackAmount(_ amount: ParsedAmount, line: String) -> Bool {
        guard amount.amount > Decimal.zero else { return false }

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
        if amount.amount > Decimal(1_000_000), hasCurrencyMarker == false {
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

    private func parserEvidenceLines(for receipt: ParsedReceipt?) -> [String] {
        guard let receipt else { return [] }
        var lines: [String] = []
        if let vendor = receipt.vendor {
            lines.append("vendor=\(vendor.value) confidence=\(vendor.confidence.rawValue) evidence=\"\(vendor.evidence)\"")
        }
        if let date = receipt.date {
            lines.append("date=\(date.value.formatted(.iso8601.year().month().day())) confidence=\(date.confidence.rawValue) evidence=\"\(date.evidence)\"")
        }
        if let total = receipt.totalAmount {
            lines.append("totalAmount=\(decimalString(total.value)) confidence=\(total.confidence.rawValue) evidence=\"\(total.evidence)\"")
        }
        if let currency = receipt.currencyCode {
            lines.append("currencyCode=\(currency.value) confidence=\(currency.confidence.rawValue) evidence=\"\(currency.evidence)\"")
        }
        if let payment = receipt.paymentMethod {
            lines.append("paymentMethod=\(payment.value.rawValue) confidence=\(payment.confidence.rawValue) evidence=\"\(payment.evidence)\"")
        }
        return lines
    }

    private func makePromptText(
        vendors: [ReceiptVendorEvidenceCandidate],
        amounts: [ReceiptAmountEvidenceCandidate],
        parserLines: [String],
        tailLines: [String],
        budget: Int,
        measure: (String) -> Int
    ) -> String {
        var required: [String] = ["OCR evidence"]
        required.append("Vendor candidates:")
        if let firstVendor = vendors.first {
            required.append("- \(firstVendor.id): \(firstVendor.text)")
        } else {
            required.append("- none")
        }

        required.append("Amount candidates:")
        let supportedAmounts = amounts.filter(\.supportsModelTotal)
        if let strongestAmount = supportedAmounts.first {
            required.append(amountPromptLine(strongestAmount))
        } else {
            required.append("- no supported final payable total candidate")
        }

        var optional: [String] = []
        optional.append(contentsOf: vendors.dropFirst().map { "- \($0.id): \($0.text)" })
        optional.append(contentsOf: supportedAmounts.dropFirst().map(amountPromptLine))

        let rejectedAmounts = amounts.filter { $0.supportsModelTotal == false }
        if rejectedAmounts.isEmpty == false {
            optional.append("Rejected non-total numbers:")
            optional.append(contentsOf: rejectedAmounts.prefix(8).map(amountPromptLine))
        }

        if parserLines.isEmpty == false {
            optional.append("Parser candidates:")
            optional.append(contentsOf: parserLines.prefix(6).map { "- \($0)" })
        }

        if tailLines.isEmpty == false {
            optional.append("Receipt tail context:")
            optional.append(contentsOf: tailLines.map { "- \($0)" })
        }

        return fit(required: required, optional: optional, budget: budget, measure: measure)
    }

    private func amountPromptLine(_ candidate: ReceiptAmountEvidenceCandidate) -> String {
        "- \(candidate.id) [\(candidate.role.promptLabel)]: \(candidate.evidence) => \(decimalString(candidate.amount)) \(candidate.currencyCode)"
    }

    private func fit(
        required: [String],
        optional: [String],
        budget: Int,
        measure: (String) -> Int
    ) -> String {
        var lines: [String] = []

        for line in required {
            append(line, to: &lines, required: true, budget: budget, measure: measure)
        }
        for line in optional {
            append(line, to: &lines, required: false, budget: budget, measure: measure)
        }

        return lines.joined(separator: "\n")
    }

    private func append(
        _ line: String,
        to lines: inout [String],
        required: Bool,
        budget: Int,
        measure: (String) -> Int
    ) {
        let candidate = (lines + [line]).joined(separator: "\n")
        if measure(candidate) <= budget {
            lines.append(line)
            return
        }

        guard required else { return }
        var low = 0
        var high = line.count
        while low < high {
            let midpoint = (low + high + 1) / 2
            let truncated = String(line.prefix(midpoint))
            let projected = (lines + [truncated]).joined(separator: "\n")
            if measure(projected) <= budget {
                low = midpoint
            } else {
                high = midpoint - 1
            }
        }
        guard low > 0 else { return }
        lines.append(String(line.prefix(low)))
    }

    private func looksLikeDateLine(_ value: String) -> Bool {
        let patterns = [
            #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            #"\d{1,2}[./-]\d{1,2}[./-]\d{2,4}"#,
            #"[A-Za-z]{3,9}\s+\d{1,2},\s+\d{4}"#
        ]
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.firstMatch(in: value, range: range) != nil
        }
    }

    private func containsAny(_ normalized: String, _ candidates: Set<String>) -> Bool {
        candidates.contains { normalized.contains($0) }
    }

    private func compactIdentifier(_ value: String) -> String {
        ReceiptLanguageProfile.normalize(value).filter { $0.isLetter || $0.isNumber }
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
