import ExpenseCore
import Foundation
import Observation
import SwiftData

struct ReceiptFieldChoice<Value: Equatable>: Equatable {
    var value: Value
    var source: FieldSource
    var reason: String?
}

struct ReceiptAutofillDiff: Equatable {
    var filledFields: [String] = []
    var conflictingFields: [String] = []
}

struct ModelOutputAuditSummary: Equatable {
    enum Field: String, CaseIterable {
        case vendor
        case date
        case totalAmount
        case currencyCode
        case paymentMethod
        case expenseType
    }

    enum Tier: String, Decodable {
        case evidenceSupported
        case imageGrounded
        case rejected
    }

    struct Acceptance: Equatable {
        var field: Field
        var primary: Tier?
        var alternate: Tier?
    }

    var imageInputUsed: Bool
    var attachmentCount: Int
    var attachmentLongEdges: [Int]
    var attemptCount: Int
    var acceptance: [Acceptance]

    init?(json: String?) {
        guard let json, let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version >= 2 else {
            return nil
        }
        imageInputUsed = envelope.imageInputUsed
        attachmentCount = envelope.attachmentCount
        attachmentLongEdges = envelope.attachmentLongEdges
        attemptCount = envelope.attemptCount
        acceptance = Field.allCases.compactMap { field in
            guard let candidate = envelope.acceptance[field.rawValue],
                  candidate.primary != nil || candidate.alternate != nil else {
                return nil
            }
            return Acceptance(field: field, primary: candidate.primary, alternate: candidate.alternate)
        }
    }

    private struct Envelope: Decodable {
        var version: Int
        var imageInputUsed: Bool
        var attachmentCount: Int
        var attachmentLongEdges: [Int]
        var attemptCount: Int
        var acceptance: [String: CandidateAcceptance]
    }

    private struct CandidateAcceptance: Decodable {
        var primary: Tier?
        var alternate: Tier?
    }
}

enum ReceiptReviewFormError: Error, Equatable {
    case missingRequiredFields
    case invalidAmount
}

@MainActor
@Observable
final class ReceiptReviewForm: Identifiable {
    let id = UUID()
    private let draft: ReceiptDraft?
    private let rawText: String
    private let locale: Locale
    private let initialPrimaryValues: InitialReceiptValues
    private var initialEditableValues = EditableReceiptValues()

    var vendor: String
    var date: Date
    var amountText: String
    var currencyCode: String
    /// Stable category ID the user has chosen (SPEC §D6). May be outside the current folder's visible
    /// set while awaiting reassignment.
    var categoryID: String?
    var paymentMethod: PaymentMethod?
    var notes: String

    var vendorChoices: [ReceiptFieldChoice<String>]
    var totalAmountChoices: [ReceiptFieldChoice<Decimal>]
    var dateChoices: [ReceiptFieldChoice<Date>]
    var currencyChoices: [ReceiptFieldChoice<String>]
    var categoryChoices: [ReceiptFieldChoice<String>]
    var paymentMethodChoices: [ReceiptFieldChoice<PaymentMethod>]
    var notice: ReceiptProcessingNotice?
    private(set) var didSave = false
    private var didDiscard = false

    var pageCount: Int {
        draft?.pages?.count ?? 0
    }

    var pageImageDatas: [Data] {
        sortedDraftPages.map(\.imageData)
    }

    var previewImageData: Data? {
        let firstPage = sortedDraftPages.first
        return firstPage?.thumbnailData ?? firstPage?.imageData
    }

    func fullImageData(at index: Int) -> Data? {
        guard pageImageDatas.indices.contains(index) else {
            return nil
        }
        return pageImageDatas[index]
    }

    var provenanceText: String {
        if draft?.isAgentStructuredDraft == true {
            return draft?.modelOutputJSON ?? draft?.rawOCRText ?? rawText
        }
        return draft?.rawOCRText ?? rawText
    }

    var modelAuditSummary: ModelOutputAuditSummary? {
        ModelOutputAuditSummary(json: draft?.modelOutputJSON)
    }

    var preservesPendingDraftOnDiscard: Bool {
        draft?.isAgentStructuredDraft == true
    }

    init(
        draft: ReceiptDraft? = nil,
        mergedReceipt: MergedReceipt,
        notice: ReceiptProcessingNotice? = nil,
        defaultCurrencyCode: String = Locale.current.currency?.identifier ?? "USD",
        defaultPaymentMethod: PaymentMethod? = nil,
        initialCategoryID: String? = nil,
        locale: Locale = .current
    ) {
        self.draft = draft
        self.rawText = mergedReceipt.rawText
        self.locale = locale
        self.notice = notice
        self.initialPrimaryValues = InitialReceiptValues(mergedReceipt: mergedReceipt, initialCategoryID: initialCategoryID)

        self.vendorChoices = mergedReceipt.vendor.choiceModels()
        self.totalAmountChoices = mergedReceipt.totalAmount.choiceModels()
        self.dateChoices = mergedReceipt.date.choiceModels()
        self.currencyChoices = mergedReceipt.currencyCode.choiceModels()
        self.categoryChoices = mergedReceipt.expenseType.categoryChoiceModels()
        self.paymentMethodChoices = mergedReceipt.paymentMethod.choiceModels()

        self.vendor = mergedReceipt.vendor.primary?.value ?? ""
        self.date = mergedReceipt.date.primary?.value ?? Date()
        self.amountText = mergedReceipt.totalAmount.primary.map { Self.formatAmount($0.value, locale: locale) } ?? ""
        self.currencyCode = mergedReceipt.currencyCode.primary?.value.uppercased() ?? defaultCurrencyCode.uppercased()
        self.categoryID = initialCategoryID ?? mergedReceipt.expenseType.primary?.value.categoryID
        self.paymentMethod = mergedReceipt.paymentMethod.primary?.value ?? defaultPaymentMethod
        self.notes = ""
        self.initialEditableValues = EditableReceiptValues(
            vendor: self.vendor,
            date: self.date,
            amountText: self.amountText,
            currencyCode: self.currencyCode,
            categoryID: self.categoryID,
            paymentMethod: self.paymentMethod,
            notes: self.notes
        )
    }

    static func manual(
        defaultCurrencyCode: String = Locale.current.currency?.identifier ?? "USD",
        defaultPaymentMethod: PaymentMethod? = nil,
        locale: Locale = .current
    ) -> ReceiptReviewForm {
        ReceiptReviewForm(
            mergedReceipt: MergedReceipt(rawText: ""),
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod,
            locale: locale
        )
    }

    var canSave: Bool {
        guard parsedAmount != nil else { return false }
        return currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && categoryID != nil
            && paymentMethod != nil
    }

    var missingRequiredFieldKeys: [String] {
        var keys: [String] = []
        if parsedAmount == nil {
            keys.append("receipt.field.amount")
        }
        if currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keys.append("receipt.field.currency")
        }
        if categoryID == nil {
            keys.append("receipt.field.type")
        }
        if paymentMethod == nil {
            keys.append("receipt.field.payment")
        }
        return keys
    }

    var isDirty: Bool {
        initialEditableValues.isDirty(
            vendor: vendor,
            date: date,
            amountText: amountText,
            currencyCode: currencyCode,
            categoryID: categoryID,
            paymentMethod: paymentMethod,
            notes: notes,
            normalize: normalized
        )
    }

    func isVendorChoiceSelected(_ choice: ReceiptFieldChoice<String>) -> Bool {
        normalized(vendor) == normalized(choice.value)
    }

    func isTotalAmountChoiceSelected(_ choice: ReceiptFieldChoice<Decimal>) -> Bool {
        parsedAmount == choice.value
    }

    func isDateChoiceSelected(_ choice: ReceiptFieldChoice<Date>) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: choice.value)
    }

    func isCurrencyChoiceSelected(_ choice: ReceiptFieldChoice<String>) -> Bool {
        normalized(currencyCode).uppercased() == normalized(choice.value).uppercased()
    }

    func isCategoryChoiceSelected(_ choice: ReceiptFieldChoice<String>) -> Bool {
        categoryID == choice.value
    }

    func isPaymentMethodChoiceSelected(_ choice: ReceiptFieldChoice<PaymentMethod>) -> Bool {
        paymentMethod == choice.value
    }

    func chooseVendor(_ choice: ReceiptFieldChoice<String>) {
        vendor = choice.value
    }

    func chooseTotalAmount(_ choice: ReceiptFieldChoice<Decimal>) {
        amountText = Self.formatAmount(choice.value, locale: locale)
    }

    func chooseDate(_ choice: ReceiptFieldChoice<Date>) {
        date = choice.value
    }

    func chooseCurrency(_ choice: ReceiptFieldChoice<String>) {
        currencyCode = choice.value.uppercased()
    }

    func chooseCategory(_ choice: ReceiptFieldChoice<String>) {
        categoryID = choice.value
    }

    func choosePaymentMethod(_ choice: ReceiptFieldChoice<PaymentMethod>) {
        paymentMethod = choice.value
    }

    func applyAutofill(_ mergedReceipt: MergedReceipt) -> ReceiptAutofillDiff {
        var diff = ReceiptAutofillDiff()

        if let extractedVendor = mergedReceipt.vendor.primary?.value {
            applyString(
                current: &vendor,
                extracted: extractedVendor,
                fieldName: "vendor",
                diff: &diff
            )
        }

        if let extractedDate = mergedReceipt.date.primary?.value, Calendar.current.isDate(date, inSameDayAs: extractedDate) == false {
            diff.conflictingFields.append("date")
        }

        if let extractedAmount = mergedReceipt.totalAmount.primary?.value {
            if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                amountText = Self.formatAmount(extractedAmount, locale: locale)
                diff.filledFields.append("totalAmount")
            } else if parsedAmount != extractedAmount {
                diff.conflictingFields.append("totalAmount")
            }
        }

        if let extractedCurrency = mergedReceipt.currencyCode.primary?.value {
            let normalizedExtractedCurrency = extractedCurrency.uppercased()
            if currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currencyCode = normalizedExtractedCurrency
                diff.filledFields.append("currencyCode")
            } else if currencyCode.uppercased() != normalizedExtractedCurrency {
                diff.conflictingFields.append("currencyCode")
            }
        }

        if let extractedType = mergedReceipt.expenseType.primary?.value {
            if categoryID == nil {
                categoryID = extractedType.categoryID
                diff.filledFields.append("expenseType")
            } else if categoryID != extractedType.categoryID {
                diff.conflictingFields.append("expenseType")
            }
        }

        if let extractedPayment = mergedReceipt.paymentMethod.primary?.value {
            if paymentMethod == nil {
                paymentMethod = extractedPayment
                diff.filledFields.append("paymentMethod")
            } else if paymentMethod != extractedPayment {
                diff.conflictingFields.append("paymentMethod")
            }
        }

        return diff
    }

    func save(in context: ModelContext, group: ExpenseGroup?) throws -> Receipt {
        guard let amount = parsedAmount else {
            throw ReceiptReviewFormError.invalidAmount
        }
        guard currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ReceiptReviewFormError.missingRequiredFields
        }
        guard let categoryID, let paymentMethod else {
            throw ReceiptReviewFormError.missingRequiredFields
        }

        let receipt = Receipt(
            vendor: vendor.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            totalAmount: amount,
            currencyCode: currencyCode,
            paymentMethod: paymentMethod,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            group: group
        )
        receipt.categoryID = categoryID

        let attachments = (draft?.pages ?? [])
            .sorted { $0.pageIndex < $1.pageIndex }
            .map { page in
                ReceiptAttachment(
                    imageData: page.imageData,
                    thumbnailData: page.thumbnailData,
                    pageIndex: page.pageIndex,
                    sourceType: page.sourceType,
                    receipt: receipt
                )
            }

        let extraction = ExtractionRecord(
            rawOCRText: extractionRawText,
            modelOutputJSON: draft?.modelOutputJSON,
            ocrConfidence: draft?.ocrConfidence,
            pipelineVersion: draft?.pipelineVersion ?? "v1",
            userCorrectedFields: correctedFields(
                vendor: receipt.vendor,
                date: receipt.date,
                totalAmount: receipt.totalAmount,
                currencyCode: receipt.currencyCode,
                categoryID: receipt.categoryID,
                paymentMethod: receipt.paymentMethod
            ).nilIfEmpty,
            receipt: receipt
        )

        receipt.attachments = attachments
        receipt.extraction = extraction

        context.insert(receipt)
        attachments.forEach { context.insert($0) }
        context.insert(extraction)

        if let group {
            var receipts = group.receipts ?? []
            receipts.append(receipt)
            group.receipts = receipts
        }

        if let draft {
            context.delete(draft)
        }
        try context.save()
        didSave = true
        return receipt
    }

    func discardIfUnsaved(in context: ModelContext) {
        guard didSave == false, didDiscard == false, let draft else { return }
        guard preservesPendingDraftOnDiscard == false else { return }
        didDiscard = true
        context.delete(draft)
        try? context.save()
    }

    var parsedAmount: Decimal? {
        AmountInputParser.parse(amountText, locale: locale)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedDraftPages: [ReceiptDraftPage] {
        (draft?.pages ?? []).sorted { $0.pageIndex < $1.pageIndex }
    }

    private var extractionRawText: String {
        if draft?.isAgentStructuredDraft == true {
            return draft?.modelOutputJSON ?? draft?.rawOCRText ?? rawText
        }
        return draft?.rawOCRText ?? rawText
    }

    private func applyString(
        current: inout String,
        extracted: String,
        fieldName: String,
        diff: inout ReceiptAutofillDiff
    ) {
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current = extracted
            diff.filledFields.append(fieldName)
        } else if current != extracted {
            diff.conflictingFields.append(fieldName)
        }
    }

    private static func formatAmount(_ amount: Decimal, locale: Locale) -> String {
        amount.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(2))
        )
    }

    private func correctedFields(
        vendor: String,
        date: Date,
        totalAmount: Decimal,
        currencyCode: String,
        categoryID: String,
        paymentMethod: PaymentMethod
    ) -> [String] {
        var fields: [String] = []
        if let initialVendor = initialPrimaryValues.vendor, normalized(vendor) != normalized(initialVendor) {
            fields.append("vendor")
        }
        if let initialDate = initialPrimaryValues.date, Calendar.current.isDate(date, inSameDayAs: initialDate) == false {
            fields.append("date")
        }
        if let initialAmount = initialPrimaryValues.totalAmount, totalAmount != initialAmount {
            fields.append("totalAmount")
        }
        if let initialCurrency = initialPrimaryValues.currencyCode, currencyCode.uppercased() != initialCurrency.uppercased() {
            fields.append("currencyCode")
        }
        if let initialCategory = initialPrimaryValues.categoryID, categoryID != initialCategory {
            fields.append("expenseType")
        }
        if let initialPayment = initialPrimaryValues.paymentMethod, paymentMethod != initialPayment {
            fields.append("paymentMethod")
        }
        return fields
    }
}

private struct InitialReceiptValues {
    var vendor: String?
    var date: Date?
    var totalAmount: Decimal?
    var currencyCode: String?
    var categoryID: String?
    var paymentMethod: PaymentMethod?

    init(mergedReceipt: MergedReceipt, initialCategoryID: String?) {
        self.vendor = mergedReceipt.vendor.primary?.value
        self.date = mergedReceipt.date.primary?.value
        self.totalAmount = mergedReceipt.totalAmount.primary?.value
        self.currencyCode = mergedReceipt.currencyCode.primary?.value
        self.categoryID = initialCategoryID ?? mergedReceipt.expenseType.primary?.value.categoryID
        self.paymentMethod = mergedReceipt.paymentMethod.primary?.value
    }
}

private struct EditableReceiptValues {
    var vendor: String = ""
    var date: Date = Date()
    var amountText: String = ""
    var currencyCode: String = ""
    var categoryID: String?
    var paymentMethod: PaymentMethod?
    var notes: String = ""

    func isDirty(
        vendor: String,
        date: Date,
        amountText: String,
        currencyCode: String,
        categoryID: String?,
        paymentMethod: PaymentMethod?,
        notes: String,
        normalize: (String) -> String
    ) -> Bool {
        normalize(vendor) != normalize(self.vendor)
            || Calendar.current.isDate(date, inSameDayAs: self.date) == false
            || normalize(amountText) != normalize(self.amountText)
            || normalize(currencyCode).uppercased() != normalize(self.currencyCode).uppercased()
            || categoryID != self.categoryID
            || paymentMethod != self.paymentMethod
            || normalize(notes) != normalize(self.notes)
    }
}

private extension MergedField {
    func choiceModels() -> [ReceiptFieldChoice<Value>] {
        options.map { option in
            ReceiptFieldChoice(
                value: option.value,
                source: option.source,
                reason: option.reason ?? option.evidence
            )
        }
    }
}

private extension MergedField where Value == ExpenseType {
    /// Maps model-suggested legacy expense types onto category-ID choices for the folder-scoped
    /// selector (SPEC §D6). The model still classifies into the five legacy types.
    func categoryChoiceModels() -> [ReceiptFieldChoice<String>] {
        options.map { option in
            ReceiptFieldChoice(
                value: option.value.categoryID,
                source: option.source,
                reason: option.reason ?? option.evidence
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}

@MainActor
extension Receipt {
    func applyAttachedCapture(
        _ result: ReceiptProcessingResult,
        in context: ModelContext
    ) throws -> ReceiptAutofillDiff {
        let sortedPages = (result.draft.pages ?? []).sorted { $0.pageIndex < $1.pageIndex }
        let pageIndexOffset = attachments?.count ?? 0
        let newAttachments = sortedPages.map { page in
            ReceiptAttachment(
                imageData: page.imageData,
                thumbnailData: page.thumbnailData,
                pageIndex: pageIndexOffset + page.pageIndex,
                sourceType: page.sourceType,
                receipt: self
            )
        }

        var currentAttachments = attachments ?? []
        currentAttachments.append(contentsOf: newAttachments)
        attachments = currentAttachments
        newAttachments.forEach { context.insert($0) }

        let diff = applyAutofillWithoutOverwriting(result.mergedReceipt)
        upsertExtractionRecord(
            rawOCRText: result.draft.rawOCRText,
            modelOutputJSON: result.draft.modelOutputJSON,
            ocrConfidence: result.draft.ocrConfidence,
            correctedFields: diff.conflictingFields,
            in: context
        )

        context.delete(result.draft)
        try context.save()
        return diff
    }

    private func applyAutofillWithoutOverwriting(_ mergedReceipt: MergedReceipt) -> ReceiptAutofillDiff {
        var diff = ReceiptAutofillDiff()

        if let extractedVendor = mergedReceipt.vendor.primary?.value {
            if vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                vendor = extractedVendor
                diff.filledFields.append("vendor")
            } else if vendor != extractedVendor {
                diff.conflictingFields.append("vendor")
            }
        }

        if let extractedDate = mergedReceipt.date.primary?.value,
           Calendar.current.isDate(date, inSameDayAs: extractedDate) == false {
            diff.conflictingFields.append("date")
        }

        if let extractedAmount = mergedReceipt.totalAmount.primary?.value,
           totalAmount != extractedAmount {
            diff.conflictingFields.append("totalAmount")
        }

        if let extractedCurrency = mergedReceipt.currencyCode.primary?.value,
           currencyCode.uppercased() != extractedCurrency.uppercased() {
            diff.conflictingFields.append("currencyCode")
        }

        if let extractedType = mergedReceipt.expenseType.primary?.value,
           categoryID != extractedType.categoryID {
            diff.conflictingFields.append("expenseType")
        }

        if let extractedPayment = mergedReceipt.paymentMethod.primary?.value,
           paymentMethod != extractedPayment {
            diff.conflictingFields.append("paymentMethod")
        }

        return diff
    }

    private func upsertExtractionRecord(
        rawOCRText: String,
        modelOutputJSON: String?,
        ocrConfidence: Double?,
        correctedFields: [String],
        in context: ModelContext
    ) {
        let normalizedText = rawOCRText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else { return }

        if let extraction {
            let existing = extraction.rawOCRText.trimmingCharacters(in: .whitespacesAndNewlines)
            extraction.rawOCRText = existing.isEmpty ? normalizedText : "\(existing)\n\n\(normalizedText)"
            if let modelOutputJSON {
                extraction.modelOutputJSON = modelOutputJSON
            }
            if let ocrConfidence {
                extraction.ocrConfidence = ocrConfidence
            }
            extraction.userCorrectedFields = correctedFields.isEmpty ? extraction.userCorrectedFields : correctedFields
        } else {
            let extraction = ExtractionRecord(
                rawOCRText: normalizedText,
                modelOutputJSON: modelOutputJSON,
                ocrConfidence: ocrConfidence,
                userCorrectedFields: correctedFields.isEmpty ? nil : correctedFields,
                receipt: self
            )
            self.extraction = extraction
            context.insert(extraction)
        }
    }
}
