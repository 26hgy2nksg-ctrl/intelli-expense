import Foundation

public struct ModelCandidateAcceptance: Equatable, Sendable {
    public var primary: ModelOutputAcceptanceTier?
    public var alternate: ModelOutputAcceptanceTier?

    public init(primary: ModelOutputAcceptanceTier? = nil, alternate: ModelOutputAcceptanceTier? = nil) {
        self.primary = primary
        self.alternate = alternate
    }
}

public struct ModelOutputAcceptance: Equatable, Sendable {
    public var vendor: ModelCandidateAcceptance
    public var date: ModelCandidateAcceptance
    public var totalAmount: ModelCandidateAcceptance
    public var currencyCode: ModelCandidateAcceptance
    public var paymentMethod: ModelCandidateAcceptance
    public var expenseType: ModelCandidateAcceptance

    public init(
        vendor: ModelCandidateAcceptance = ModelCandidateAcceptance(),
        date: ModelCandidateAcceptance = ModelCandidateAcceptance(),
        totalAmount: ModelCandidateAcceptance = ModelCandidateAcceptance(),
        currencyCode: ModelCandidateAcceptance = ModelCandidateAcceptance(),
        paymentMethod: ModelCandidateAcceptance = ModelCandidateAcceptance(),
        expenseType: ModelCandidateAcceptance = ModelCandidateAcceptance()
    ) {
        self.vendor = vendor
        self.date = date
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.paymentMethod = paymentMethod
        self.expenseType = expenseType
    }
}

public struct ModelOutputValidationResult: Equatable, Sendable {
    public var validatedReceipt: ModelExtractedReceipt
    public var acceptance: ModelOutputAcceptance

    public init(validatedReceipt: ModelExtractedReceipt, acceptance: ModelOutputAcceptance) {
        self.validatedReceipt = validatedReceipt
        self.acceptance = acceptance
    }
}

public struct ModelOutputEvidenceValidator: Sendable {
    private static let validCurrencyCodes: Set<String> = Set(
        Locale.availableIdentifiers.compactMap { Locale(identifier: $0).currency?.identifier.uppercased() }
    )

    private let referenceDate: Date
    private let calendar: Calendar
    private let oldestAllowedYearOffset: Int

    public init(
        referenceDate: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        oldestAllowedYearOffset: Int = 10
    ) {
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.oldestAllowedYearOffset = max(1, oldestAllowedYearOffset)
    }

    public func validate(_ model: ModelExtractedReceipt, against evidence: ReceiptPromptEvidence) -> ModelExtractedReceipt {
        validateWithAudit(model, against: evidence, imageInputUsed: false).validatedReceipt
    }

    public func validateWithAudit(
        _ model: ModelExtractedReceipt,
        against evidence: ReceiptPromptEvidence,
        imageInputUsed: Bool
    ) -> ModelOutputValidationResult {
        let vendor = validateVendor(model.vendor, evidence: evidence, imageInputUsed: imageInputUsed)
        let date = validateDate(model.date, evidence: evidence, imageInputUsed: imageInputUsed)
        let amount = validateAmount(model.totalAmount, evidence: evidence, imageInputUsed: imageInputUsed)
        let currency = validateCurrency(model.currencyCode, evidence: evidence, imageInputUsed: imageInputUsed)
        let payment = validateClosedField(model.paymentMethod)
        let expenseType = validateClosedField(model.expenseType)

        return ModelOutputValidationResult(
            validatedReceipt: ModelExtractedReceipt(
                vendor: vendor.field,
                date: date.field,
                totalAmount: amount.field,
                currencyCode: currency.field,
                paymentMethod: payment.field,
                expenseType: expenseType.field
            ),
            acceptance: ModelOutputAcceptance(
                vendor: vendor.acceptance,
                date: date.acceptance,
                totalAmount: amount.acceptance,
                currencyCode: currency.acceptance,
                paymentMethod: payment.acceptance,
                expenseType: expenseType.acceptance
            )
        )
    }

    private func validateVendor(
        _ field: ModelField<String>,
        evidence: ReceiptPromptEvidence,
        imageInputUsed: Bool
    ) -> ValidatedField<String> {
        validateField(field) { candidate in
            if supports(vendor: candidate.value, candidates: evidence.vendorCandidates) {
                return .evidenceSupported
            }
            guard imageInputUsed, isPlausibleImageVendor(candidate.value, evidence: evidence) else {
                return .rejected
            }
            return .imageGrounded
        }
    }

    private func validateAmount(
        _ field: ModelField<Decimal>,
        evidence: ReceiptPromptEvidence,
        imageInputUsed: Bool
    ) -> ValidatedField<Decimal> {
        validateField(field) { candidate in
            if evidence.amountCandidates.contains(where: { $0.supportsModelTotal && decimalEquals($0.amount, candidate.value) }) {
                return .evidenceSupported
            }
            guard imageInputUsed,
                  candidate.value > .zero,
                  candidate.value <= Decimal(1_000_000),
                  evidence.amountCandidates.contains(where: {
                      !$0.supportsModelTotal
                          && (
                              decimalEquals($0.amount, candidate.value)
                                  || ([.quantity, .unitRate].contains($0.role)
                                      && evidenceText($0.evidence, contains: candidate.value))
                          )
                  }) == false else {
                return .rejected
            }
            return .imageGrounded
        }
    }

    private func validateDate(
        _ field: ModelField<Date>,
        evidence: ReceiptPromptEvidence,
        imageInputUsed: Bool
    ) -> ValidatedField<Date> {
        validateField(field) { candidate in
            guard isPlausibleDate(candidate.value) else { return .rejected }
            let dateString = candidate.value.formatted(.iso8601.year().month().day())
            if evidence.parserLines.contains(where: { $0.contains("date=\(dateString)") }) {
                return .evidenceSupported
            }
            return imageInputUsed ? .imageGrounded : .evidenceSupported
        }
    }

    private func validateCurrency(
        _ field: ModelField<String>,
        evidence: ReceiptPromptEvidence,
        imageInputUsed: Bool
    ) -> ValidatedField<String> {
        validateField(field) { candidate in
            let code = candidate.value.uppercased()
            guard Self.validCurrencyCodes.contains(code) else { return .rejected }
            let supported = evidence.amountCandidates.contains { $0.currencyCode == code }
                || evidence.parserLines.contains { $0.contains("currencyCode=\(code)") }
            if supported || imageInputUsed == false {
                return .evidenceSupported
            }
            return .imageGrounded
        }
    }

    private func validateClosedField<Value>(_ field: ModelField<Value>) -> ValidatedField<Value> {
        validateField(field) { _ in .evidenceSupported }
    }

    private func validateField<Value>(
        _ field: ModelField<Value>,
        classifier: (ModelFieldCandidate<Value>) -> ModelOutputAcceptanceTier
    ) -> ValidatedField<Value> {
        guard field.isUnknown == false, let primary = field.primary else {
            return ValidatedField(field: field, acceptance: ModelCandidateAcceptance())
        }

        let primaryTier = classifier(primary)
        guard primaryTier != .rejected else {
            return ValidatedField(
                field: .unknown(),
                acceptance: ModelCandidateAcceptance(
                    primary: .rejected,
                    alternate: field.alternate.map(classifier)
                )
            )
        }

        let validatedPrimary = ModelFieldCandidate(
            value: primary.value,
            reason: primary.reason,
            acceptanceTier: primaryTier
        )
        let alternateTier = field.alternate.map(classifier)
        let validatedAlternate = field.alternate.flatMap { alternate -> ModelFieldCandidate<Value>? in
            guard let alternateTier, alternateTier != .rejected else { return nil }
            return ModelFieldCandidate(
                value: alternate.value,
                reason: alternate.reason,
                acceptanceTier: alternateTier
            )
        }
        return ValidatedField(
            field: .known(primary: validatedPrimary, alternate: validatedAlternate),
            acceptance: ModelCandidateAcceptance(primary: primaryTier, alternate: alternateTier)
        )
    }

    private func supports(vendor: String, candidates: [ReceiptVendorEvidenceCandidate]) -> Bool {
        let normalizedVendor = normalizeVendor(vendor)
        guard normalizedVendor.isEmpty == false else { return false }

        return candidates.contains { candidate in
            let normalizedCandidate = normalizeVendor(candidate.text)
            guard normalizedCandidate.isEmpty == false else { return false }
            if normalizedVendor == normalizedCandidate {
                return true
            }
            let shortest = min(normalizedVendor.count, normalizedCandidate.count)
            guard shortest >= 4 else { return false }
            return normalizedVendor.contains(normalizedCandidate) || normalizedCandidate.contains(normalizedVendor)
        }
    }

    private func isPlausibleImageVendor(_ value: String, evidence: ReceiptPromptEvidence) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ReceiptLanguageProfile.normalize(trimmed)
        guard trimmed.count >= 2, trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        guard ReceiptLanguageProfiles.allMetadataKeywords.contains(where: normalized.contains) == false else { return false }
        guard ReceiptLanguageProfiles.allVendorSkipKeywords.contains(where: normalized.contains) == false else { return false }
        guard ReceiptLanguageProfiles.allTaxLabels.contains(where: normalized.contains) == false else { return false }
        guard ReceiptLanguageProfiles.allCashHints.contains(where: normalized.contains) == false else { return false }
        guard ReceiptLanguageProfiles.allCardHints.contains(where: normalized.contains) == false else { return false }

        let compact = normalizeVendor(trimmed)
        let forbiddenLines = evidence.amountCandidates.filter { !$0.supportsModelTotal }.map(\.evidence) + evidence.tailLines
        return forbiddenLines.contains { normalizeVendor($0) == compact } == false
    }

    private func isPlausibleDate(_ value: Date) -> Bool {
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        guard let latest = calendar.date(byAdding: .day, value: 1, to: startOfReferenceDay),
              let earliest = calendar.date(byAdding: .year, value: -oldestAllowedYearOffset, to: startOfReferenceDay) else {
            return false
        }
        return value >= earliest && value <= latest
    }

    private func normalizeVendor(_ value: String) -> String {
        ReceiptLanguageProfile.normalize(value).filter { $0.isLetter || $0.isNumber }
    }

    private func decimalEquals(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        NSDecimalNumber(decimal: lhs).compare(NSDecimalNumber(decimal: rhs)) == .orderedSame
    }

    private func evidenceText(_ evidence: String, contains value: Decimal) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\d+[.,]\d+"#) else { return false }
        let range = NSRange(evidence.startIndex..<evidence.endIndex, in: evidence)
        return regex.matches(in: evidence, range: range).contains { match in
            guard let tokenRange = Range(match.range, in: evidence) else { return false }
            let token = String(evidence[tokenRange]).replacingOccurrences(of: ",", with: ".")
            guard let parsed = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) else { return false }
            return decimalEquals(parsed, value)
        }
    }

    private struct ValidatedField<Value: Equatable & Sendable> {
        var field: ModelField<Value>
        var acceptance: ModelCandidateAcceptance
    }
}
