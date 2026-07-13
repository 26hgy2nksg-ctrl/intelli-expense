import ExpenseCore
import CoreGraphics
import Foundation
import FoundationModels
#if XCODE_27_FOUNDATION_MODELS
import ImageIO
#endif

struct FoundationModelAvailabilityProvider: ModelAvailabilityProviding {
    func currentAvailability() async -> ModelAvailabilityStatus {
        Self.map(SystemLanguageModel.default.availability)
    }

    func supportsLocale(_ locale: Locale) -> Bool {
        let model = SystemLanguageModel.default
        return FoundationModelLocaleSupport.isSupported(
            locale,
            supportedLanguages: model.supportedLanguages
        ) { checkedLocale in
            model.supportsLocale(checkedLocale)
        }
    }

    func supportsImageInput() -> Bool {
        #if XCODE_27_FOUNDATION_MODELS
        if #available(iOS 27.0, macOS 27.0, *) {
            return FoundationModelImageCapability.isSupported(
                betaCodeCompiled: true,
                runtimeHasVision: SystemLanguageModel.default.capabilities.contains(.vision)
            )
        }
        #endif
        return false
    }

    static func map(_ availability: SystemLanguageModel.Availability) -> ModelAvailabilityStatus {
        switch availability {
        case .available:
            return .available
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable:
            return .unknownUnavailable
        @unknown default:
            return .unknownUnavailable
        }
    }
}

enum FoundationModelImageCapability {
    static func isSupported(betaCodeCompiled: Bool, runtimeHasVision: Bool) -> Bool {
        betaCodeCompiled && runtimeHasVision
    }
}

struct FoundationModelLocaleSupport {
    static func isSupported(
        _ locale: Locale,
        supportedLanguages: Set<Locale.Language>,
        supportsExactLocale: (Locale) -> Bool
    ) -> Bool {
        if supportsExactLocale(locale) {
            return true
        }
        guard let requestedLanguageCode = locale.language.languageCode else {
            return false
        }
        return supportedLanguages.contains { supportedLanguage in
            supportedLanguage.languageCode == requestedLanguageCode
        }
    }
}

struct FoundationModelReceiptPromptFactory: Sendable {
    var maxEvidenceCharacters: Int

    init(maxOCRCharacters: Int = ReceiptPromptEvidenceBuilder.defaultCharacterBudget) {
        self.maxEvidenceCharacters = maxOCRCharacters
    }

    func localeInstructions(for locale: Locale) -> String? {
        guard locale.identifier != "en_US" else {
            return nil
        }
        return "The person's locale is \(locale.identifier)."
    }

    func makePrompt(rawText: String, deterministicReceipt: ParsedReceipt?, locale: Locale) -> String {
        let defaultCurrencyCode = deterministicReceipt?.currencyCode?.value
            ?? locale.currency?.identifier
            ?? "USD"
        let evidence = ReceiptPromptEvidenceBuilder(
            characterBudget: maxEvidenceCharacters,
            defaultCurrencyCode: defaultCurrencyCode
        )
        .build(rawText: rawText, deterministicReceipt: deterministicReceipt)

        return makePrompt(evidence: evidence, locale: locale)
    }

    func makePrompt(
        request: ExtractionModelRequest,
        locale: Locale,
        evidenceCharacterBudget: Int? = nil
    ) -> String {
        if evidenceCharacterBudget == nil, let promptEvidence = request.promptEvidence {
            return makePrompt(evidence: promptEvidence, locale: locale)
        }
        let factory = FoundationModelReceiptPromptFactory(
            maxOCRCharacters: evidenceCharacterBudget ?? maxEvidenceCharacters
        )
        return factory.makePrompt(rawText: request.rawText, deterministicReceipt: request.deterministicReceipt, locale: locale)
    }

    private func makePrompt(evidence: ReceiptPromptEvidence, locale: Locale) -> String {
        var sections: [String] = []
        if let localeInstructions = localeInstructions(for: locale) {
            sections.append(localeInstructions)
        }
        sections.append(
            """
            Extract one receipt from the supplied evidence. Prefer agreement between OCR evidence and any attached receipt images. Prefer unknown over guessing. Return alternate values only when genuinely torn between two supported readings.
            """
        )
        sections.append(
            """
            Field checklist:
            - vendor: user-facing merchant/store name from vendor evidence
            - date: receipt issue/purchase date in yyyy-MM-dd
            - totalAmount: final payable total as a plain decimal string
            - currencyCode: ISO 4217 code
            - paymentMethod: card, cash, or unknown
            - expenseType: food, hotel, flight, taxi, other, or unknown

            Amount rule: choose totalAmount only from final payable total or parser-supported total candidates; choose unknown for totalAmount when final payable total evidence is absent. Do not use subtotal, tax, invoice/order/GST/VAT identifiers, dates, or card masks as totals.
            Vendor rule: choose the consumer-facing merchant/store name. Do not use tax IDs, legal entities, payment lines, addresses, or registration metadata as vendor.
            """
        )
        sections.append(evidence.promptText)
        return sections.joined(separator: "\n\n")
    }

    func outputLanguageInstruction(for locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let languageName = Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English"
        return "You MUST write user-visible alternate reasons in \(languageName)."
    }

    func instructions(locale: Locale) -> String {
        [
            "You extract factual receipt fields for an expense-tracking app.",
            "All schema property names and instructions are in English.",
            localeInstructions(for: locale),
            outputLanguageInstruction(for: locale),
            "Return structured values only. Use the prompt's OCR evidence and attached receipt images only."
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

struct FoundationModelPromptBudget: Equatable, Sendable {
    var contextSize: Int
    var instructionsTokens: Int
    var schemaTokens: Int
    var attachmentTokens: Int

    var maximumResponseTokens: Int {
        min(1_200, max(700, contextSize / 6))
    }

    var maximumPromptTokens: Int {
        max(0, contextSize - instructionsTokens - schemaTokens - attachmentTokens - maximumResponseTokens)
    }

    func fits(promptTokens: Int) -> Bool {
        promptTokens <= maximumPromptTokens
    }
}

struct FoundationModelReceiptService: ExtractionModelServicing {
    static let defaultTimeoutSeconds: TimeInterval = 30

    var promptFactory: FoundationModelReceiptPromptFactory
    var timeoutSeconds: TimeInterval

    init(
        promptFactory: FoundationModelReceiptPromptFactory = FoundationModelReceiptPromptFactory(),
        timeoutSeconds: TimeInterval = Self.defaultTimeoutSeconds
    ) {
        self.promptFactory = promptFactory
        self.timeoutSeconds = timeoutSeconds
    }

    func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt {
        try await withTimeout(seconds: request.timeoutSeconds ?? timeoutSeconds) {
            let locale = Locale(identifier: request.localeIdentifier)
            let model = SystemLanguageModel.default
            let instructionsText = promptFactory.instructions(locale: locale)
            let prepared = try await preparedPrompt(
                request: request,
                locale: locale,
                model: model,
                instructionsText: instructionsText
            )
            let session = LanguageModelSession(model: model, instructions: instructionsText)
            let response = try await session.respond(
                to: prepared.prompt,
                generating: FoundationModelReceiptSchema.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: prepared.maximumResponseTokens
                )
            )
            return response.content.modelExtractedReceipt()
        }
    }

    private func preparedPrompt(
        request: ExtractionModelRequest,
        locale: Locale,
        model: SystemLanguageModel,
        instructionsText: String
    ) async throws -> (prompt: Prompt, maximumResponseTokens: Int) {
        var evidenceCharacterBudget = promptFactory.maxEvidenceCharacters
        var latestPrompt = makePrompt(
            text: promptFactory.makePrompt(request: request, locale: locale),
            images: request.images
        )

        guard #available(iOS 26.4, macOS 26.4, *) else {
            return (latestPrompt, 700)
        }

        let instructions = Instructions(instructionsText)
        let instructionsTokens = try await model.tokenCount(for: instructions)
        let schemaTokens = try await model.tokenCount(for: FoundationModelReceiptSchema.generationSchema)

        for _ in 0..<6 {
            let text = promptFactory.makePrompt(
                request: request,
                locale: locale,
                evidenceCharacterBudget: evidenceCharacterBudget
            )
            let textPrompt = Prompt(text)
            latestPrompt = makePrompt(text: text, images: request.images)
            let textTokens = try await model.tokenCount(for: textPrompt)
            let totalPromptTokens = try await model.tokenCount(for: latestPrompt)
            let budget = FoundationModelPromptBudget(
                contextSize: model.contextSize,
                instructionsTokens: instructionsTokens,
                schemaTokens: schemaTokens,
                attachmentTokens: max(0, totalPromptTokens - textTokens)
            )
            if budget.fits(promptTokens: textTokens) {
                return (latestPrompt, budget.maximumResponseTokens)
            }
            evidenceCharacterBudget = max(200, evidenceCharacterBudget * 2 / 3)
        }

        throw ExtractionModelError.contextSizeExceeded
    }

    private func makePrompt(text: String, images: [ExtractionModelImage]) -> Prompt {
        #if XCODE_27_FOUNDATION_MODELS
        if #available(iOS 27.0, macOS 27.0, *), images.isEmpty == false {
            let attachments: [Attachment<ImageAttachmentContent>] = images.compactMap { image in
                guard let source = CGImageSourceCreateWithData(image.imageData as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    return nil
                }
                return Attachment(cgImage).label("Receipt page \(image.pageIndex + 1)")
            }
            return Prompt {
                text
                attachments
            }
        }
        #endif
        return Prompt(text)
    }

    private func withTimeout(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> ModelExtractedReceipt
    ) async throws -> ModelExtractedReceipt {
        do {
            return try await withThrowingTaskGroup(of: ModelExtractedReceipt.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    throw ExtractionModelError.timedOut
                }

                guard let result = try await group.next() else {
                    throw ExtractionModelError.generationFailed("No model response.")
                }
                group.cancelAll()
                return result
            }
        } catch let error as ExtractionModelError {
            throw error
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            throw ExtractionModelError.unsupportedLanguageOrLocale("Unsupported receipt language or locale.")
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw ExtractionModelError.contextSizeExceeded
        } catch {
            throw ExtractionModelError.generationFailed(String(describing: error))
        }
    }
}

@Generable
private struct FoundationModelReceiptSchema {
    @Guide(description: "Best merchant or store name printed on the receipt, or unknown.")
    var vendor: String

    @Guide(description: "Alternate merchant reading only if genuinely ambiguous, otherwise unknown.")
    var vendorAlternate: String

    @Guide(description: "One short phrase explaining the alternate merchant, otherwise empty.")
    var vendorAlternateReason: String

    @Guide(description: "Receipt date in yyyy-MM-dd format, or unknown.")
    var date: String

    @Guide(description: "Alternate receipt date in yyyy-MM-dd format only if genuinely ambiguous, otherwise unknown.")
    var dateAlternate: String

    @Guide(description: "One short phrase explaining the alternate date, otherwise empty.")
    var dateAlternateReason: String

    @Guide(description: "Final total amount as a plain decimal string, or unknown.")
    var totalAmount: String

    @Guide(description: "Alternate total amount as a plain decimal string only if genuinely ambiguous, otherwise unknown.")
    var totalAmountAlternate: String

    @Guide(description: "One short phrase explaining the alternate total, otherwise empty.")
    var totalAmountAlternateReason: String

    @Guide(description: "ISO 4217 currency code, or unknown.")
    var currencyCode: String

    @Guide(description: "Alternate ISO 4217 currency code only if genuinely ambiguous, otherwise unknown.")
    var currencyCodeAlternate: String

    @Guide(description: "One short phrase explaining the alternate currency, otherwise empty.")
    var currencyCodeAlternateReason: String

    @Guide(description: "Payment method: card, cash, or unknown.", .anyOf(["card", "cash", "unknown"]))
    var paymentMethod: String

    @Guide(description: "Alternate payment method only if genuinely ambiguous: card, cash, or unknown.", .anyOf(["card", "cash", "unknown"]))
    var paymentMethodAlternate: String

    @Guide(description: "One short phrase explaining the alternate payment method, otherwise empty.")
    var paymentMethodAlternateReason: String

    @Guide(description: "Expense type: food, hotel, flight, taxi, other, or unknown.", .anyOf(["food", "hotel", "flight", "taxi", "other", "unknown"]))
    var expenseType: String

    @Guide(description: "Alternate expense type only if genuinely ambiguous: food, hotel, flight, taxi, other, or unknown.", .anyOf(["food", "hotel", "flight", "taxi", "other", "unknown"]))
    var expenseTypeAlternate: String

    @Guide(description: "One short phrase explaining the alternate expense type, otherwise empty.")
    var expenseTypeAlternateReason: String

    func modelExtractedReceipt() -> ModelExtractedReceipt {
        ModelExtractedReceipt(
            vendor: stringField(primary: vendor, alternate: vendorAlternate, reason: vendorAlternateReason),
            date: dateField(primary: date, alternate: dateAlternate, reason: dateAlternateReason),
            totalAmount: decimalField(primary: totalAmount, alternate: totalAmountAlternate, reason: totalAmountAlternateReason),
            currencyCode: currencyField(primary: currencyCode, alternate: currencyCodeAlternate, reason: currencyCodeAlternateReason),
            paymentMethod: enumField(primary: paymentMethod, alternate: paymentMethodAlternate, reason: paymentMethodAlternateReason),
            expenseType: enumField(primary: expenseType, alternate: expenseTypeAlternate, reason: expenseTypeAlternateReason)
        )
    }

    private func stringField(primary: String, alternate: String, reason: String) -> ModelField<String> {
        guard let primary = knownString(primary) else {
            return .unknown()
        }
        return .known(
            primary: primary,
            alternate: knownString(alternate).map { ModelFieldCandidate(value: $0, reason: emptyToNil(reason)) }
        )
    }

    private func dateField(primary: String, alternate: String, reason: String) -> ModelField<Date> {
        guard let primary = parseDate(primary) else {
            return .unknown()
        }
        return .known(
            primary: primary,
            alternate: parseDate(alternate).map { ModelFieldCandidate(value: $0, reason: emptyToNil(reason)) }
        )
    }

    private func decimalField(primary: String, alternate: String, reason: String) -> ModelField<Decimal> {
        guard let primary = Decimal(string: primary, locale: Locale(identifier: "en_US_POSIX")) else {
            return .unknown()
        }
        return .known(
            primary: primary,
            alternate: Decimal(string: alternate, locale: Locale(identifier: "en_US_POSIX")).map {
                ModelFieldCandidate(value: $0, reason: emptyToNil(reason))
            }
        )
    }

    private func currencyField(primary: String, alternate: String, reason: String) -> ModelField<String> {
        guard let primary = knownString(primary)?.uppercased(), primary.count == 3 else {
            return .unknown()
        }
        let alternateValue = knownString(alternate)?.uppercased()
        return .known(
            primary: primary,
            alternate: alternateValue.flatMap { value in
                value.count == 3 ? ModelFieldCandidate(value: value, reason: emptyToNil(reason)) : nil
            }
        )
    }

    private func enumField<T: RawRepresentable & Equatable & Sendable>(
        primary: String,
        alternate: String,
        reason: String
    ) -> ModelField<T> where T.RawValue == String {
        guard let primary = knownString(primary).flatMap(T.init(rawValue:)) else {
            return .unknown()
        }
        return .known(
            primary: primary,
            alternate: knownString(alternate).flatMap(T.init(rawValue:)).map {
                ModelFieldCandidate(value: $0, reason: emptyToNil(reason))
            }
        )
    }

    private func knownString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.lowercased() != "unknown" else {
            return nil
        }
        return trimmed
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDate(_ value: String) -> Date? {
        guard let value = knownString(value) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
