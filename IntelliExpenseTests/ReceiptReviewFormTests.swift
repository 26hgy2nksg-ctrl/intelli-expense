import ExpenseCore
import SwiftData
import XCTest
@testable import IntelliExpense

@MainActor
final class ReceiptReviewFormTests: XCTestCase {
    func testModelOutputAuditSummaryMakesImagePathAndAcceptanceReadable() throws {
        let json = #"{"acceptance":{"date":{"alternate":"rejected","primary":"imageGrounded"},"totalAmount":{"alternate":"rejected","primary":"evidenceSupported"},"vendor":{"alternate":"evidenceSupported","primary":"evidenceSupported"}},"attachmentCount":1,"attachmentLongEdges":[1280],"attemptCount":1,"imageInputUsed":true,"rawOutput":{},"version":2}"#

        let summary = try XCTUnwrap(ModelOutputAuditSummary(json: json))

        XCTAssertTrue(summary.imageInputUsed)
        XCTAssertEqual(summary.attachmentCount, 1)
        XCTAssertEqual(summary.attachmentLongEdges, [1280])
        XCTAssertEqual(summary.attemptCount, 1)
        XCTAssertEqual(summary.acceptance.first { $0.field == .vendor }?.primary, .evidenceSupported)
        XCTAssertEqual(summary.acceptance.first { $0.field == .date }?.primary, .imageGrounded)
        XCTAssertEqual(summary.acceptance.first { $0.field == .totalAmount }?.alternate, .rejected)
    }

    func testReviewFormExposesSavedModelAuditSummarySeparatelyFromOCRText() throws {
        let json = #"{"acceptance":{},"attachmentCount":1,"attachmentLongEdges":[1280],"attemptCount":1,"imageInputUsed":true,"rawOutput":{},"version":2}"#
        let draft = ReceiptDraft(rawOCRText: "KAVERI FRESH MART", modelOutputJSON: json)
        let form = ReceiptReviewForm(draft: draft, mergedReceipt: completeMergedReceipt(rawText: draft.rawOCRText))

        XCTAssertEqual(form.provenanceText, "KAVERI FRESH MART")
        XCTAssertEqual(form.modelAuditSummary?.imageInputUsed, true)
        XCTAssertEqual(form.modelAuditSummary?.attachmentCount, 1)
    }

    func testReviewFormPrefillsPrimaryValuesAndSurfacesTwoAlternates() {
        let form = ReceiptReviewForm(
            mergedReceipt: MergedReceipt(
                vendor: MergedField(options: [
                    MergedFieldOption(value: "Cafe Central", source: .deterministic, confidence: .high, evidence: "header"),
                    MergedFieldOption(value: "Cafe Centrum", source: .model, confidence: .medium, reason: "OCR could read the last word two ways")
                ]),
                date: MergedField(options: [MergedFieldOption(value: date(2026, 6, 14), source: .deterministic)]),
                totalAmount: MergedField(options: [
                    MergedFieldOption(value: Decimal(string: "18.40")!, source: .deterministic, confidence: .medium, evidence: "TOTAL"),
                    MergedFieldOption(value: Decimal(string: "13.40")!, source: .model, confidence: .medium, reason: "Faint digit")
                ]),
                currencyCode: MergedField(options: [MergedFieldOption(value: "EUR", source: .deterministic)]),
                paymentMethod: MergedField(options: [MergedFieldOption(value: .card, source: .deterministic)]),
                expenseType: MergedField(options: [MergedFieldOption(value: .food, source: .model)]),
                rawText: "Cafe Central\nTOTAL EUR 18.40"
            )
        )

        XCTAssertEqual(form.vendor, "Cafe Central")
        XCTAssertEqual(form.vendorChoices.map(\.value), ["Cafe Central", "Cafe Centrum"])
        XCTAssertEqual(form.amountText, "18.40")
        XCTAssertEqual(form.totalAmountChoices.map(\.value), [Decimal(string: "18.40")!, Decimal(string: "13.40")!])
        XCTAssertEqual(form.currencyCode, "EUR")
        XCTAssertEqual(form.categoryID, "food")
        XCTAssertEqual(form.paymentMethod, .card)
        XCTAssertTrue(form.canSave)
    }

    func testAcceptanceAmbiguousChoicesCanBePickedForEveryExtractedField() {
        let form = ReceiptReviewForm(
            mergedReceipt: MergedReceipt(
                vendor: MergedField(options: [
                    MergedFieldOption(value: "Cafe Central", source: .deterministic),
                    MergedFieldOption(value: "Cafe Centrum", source: .model, reason: "Last word is faint")
                ]),
                date: MergedField(options: [
                    MergedFieldOption(value: date(2026, 6, 14), source: .deterministic),
                    MergedFieldOption(value: date(2026, 6, 15), source: .model, reason: "Receipt footer date")
                ]),
                totalAmount: MergedField(options: [
                    MergedFieldOption(value: Decimal(string: "18.40")!, source: .deterministic),
                    MergedFieldOption(value: Decimal(string: "13.40")!, source: .model, reason: "Faint digit")
                ]),
                currencyCode: MergedField(options: [
                    MergedFieldOption(value: "EUR", source: .deterministic),
                    MergedFieldOption(value: "USD", source: .model, reason: "Symbol is damaged")
                ]),
                paymentMethod: MergedField(options: [
                    MergedFieldOption(value: .card, source: .deterministic),
                    MergedFieldOption(value: .cash, source: .model, reason: "Cash hint near footer")
                ]),
                expenseType: MergedField(options: [
                    MergedFieldOption(value: .food, source: .model),
                    MergedFieldOption(value: .other, source: .model, reason: "Vendor category uncertain")
                ]),
                rawText: "Cafe Central\nTOTAL EUR 18.40"
            )
        )

        XCTAssertEqual(form.vendorChoices.count, 2)
        XCTAssertEqual(form.dateChoices.count, 2)
        XCTAssertEqual(form.totalAmountChoices.count, 2)
        XCTAssertEqual(form.currencyChoices.count, 2)
        XCTAssertEqual(form.paymentMethodChoices.count, 2)
        XCTAssertEqual(form.categoryChoices.count, 2)

        form.chooseVendor(form.vendorChoices[1])
        form.chooseDate(form.dateChoices[1])
        form.chooseTotalAmount(form.totalAmountChoices[1])
        form.chooseCurrency(form.currencyChoices[1])
        form.choosePaymentMethod(form.paymentMethodChoices[1])
        form.chooseCategory(form.categoryChoices[1])
        form.vendor = "Manual Cafe"

        XCTAssertEqual(form.vendor, "Manual Cafe")
        XCTAssertEqual(form.date, date(2026, 6, 15))
        XCTAssertEqual(form.amountText, "13.40")
        XCTAssertEqual(form.currencyCode, "USD")
        XCTAssertEqual(form.paymentMethod, .cash)
        XCTAssertEqual(form.categoryID, "other")
    }

    func testChoiceSelectionInitiallyReflectsPrimaryValues() {
        let form = ambiguousReviewForm()

        XCTAssertTrue(form.isVendorChoiceSelected(form.vendorChoices[0]))
        XCTAssertFalse(form.isVendorChoiceSelected(form.vendorChoices[1]))
        XCTAssertTrue(form.isTotalAmountChoiceSelected(form.totalAmountChoices[0]))
        XCTAssertFalse(form.isTotalAmountChoiceSelected(form.totalAmountChoices[1]))
        XCTAssertTrue(form.isDateChoiceSelected(form.dateChoices[0]))
        XCTAssertFalse(form.isDateChoiceSelected(form.dateChoices[1]))
    }

    func testChoosingTotalAmountFlipsSelectedChoice() {
        let form = ambiguousReviewForm()

        form.chooseTotalAmount(form.totalAmountChoices[1])

        XCTAssertFalse(form.isTotalAmountChoiceSelected(form.totalAmountChoices[0]))
        XCTAssertTrue(form.isTotalAmountChoiceSelected(form.totalAmountChoices[1]))
    }

    func testFreeTypedValuesDeselectMatchingChips() {
        let form = ambiguousReviewForm()

        form.amountText = "999.99"
        form.vendor = "Manual Cafe"

        XCTAssertFalse(form.isTotalAmountChoiceSelected(form.totalAmountChoices[0]))
        XCTAssertFalse(form.isTotalAmountChoiceSelected(form.totalAmountChoices[1]))
        XCTAssertFalse(form.isVendorChoiceSelected(form.vendorChoices[0]))
        XCTAssertFalse(form.isVendorChoiceSelected(form.vendorChoices[1]))
    }

    func testUnparseableAmountDeselectsAmountChoices() {
        let form = ambiguousReviewForm()

        form.amountText = "abc"

        XCTAssertFalse(form.isTotalAmountChoiceSelected(form.totalAmountChoices[0]))
        XCTAssertFalse(form.isTotalAmountChoiceSelected(form.totalAmountChoices[1]))
    }

    func testPageImageDatasReturnFullResolutionDraftImagesInPageOrder() {
        let draft = ReceiptDraft(rawOCRText: "Three pages")
        draft.pages = [
            ReceiptDraftPage(imageData: Data([0x30]), thumbnailData: Data([0x03]), pageIndex: 2, draft: draft),
            ReceiptDraftPage(imageData: Data([0x10]), thumbnailData: Data([0x01]), pageIndex: 0, draft: draft),
            ReceiptDraftPage(imageData: Data([0x20]), thumbnailData: Data([0x02]), pageIndex: 1, draft: draft)
        ]

        let form = ReceiptReviewForm(draft: draft, mergedReceipt: MergedReceipt(rawText: "Three pages"))

        XCTAssertEqual(form.pageImageDatas, [Data([0x10]), Data([0x20]), Data([0x30])])
        XCTAssertEqual(form.fullImageData(at: 1), Data([0x20]))
        XCTAssertEqual(form.fullImageData(at: 3), nil)
        XCTAssertNotEqual(form.pageImageDatas.first, Data([0x01]))
    }

    func testDateChoiceSelectionUsesSameDaySemantics() {
        let form = ambiguousReviewForm()
        form.date = date(2026, 6, 14, hour: 10, minute: 30)

        XCTAssertTrue(form.isDateChoiceSelected(form.dateChoices[0]))
        XCTAssertFalse(form.isDateChoiceSelected(form.dateChoices[1]))
    }

    func testCurrencyChoiceSelectionIgnoresCaseAndWhitespace() {
        let form = ambiguousReviewForm()

        form.currencyCode = " inr "

        XCTAssertTrue(form.isCurrencyChoiceSelected(form.currencyChoices[0]))
        XCTAssertFalse(form.isCurrencyChoiceSelected(form.currencyChoices[1]))
    }

    func testNilExpenseTypeAndPaymentMethodDoNotSelectChoices() {
        let form = ambiguousReviewForm()

        form.categoryID = nil
        form.paymentMethod = nil

        XCTAssertFalse(form.isCategoryChoiceSelected(form.categoryChoices[0]))
        XCTAssertFalse(form.isCategoryChoiceSelected(form.categoryChoices[1]))
        XCTAssertFalse(form.isPaymentMethodChoiceSelected(form.paymentMethodChoices[0]))
        XCTAssertFalse(form.isPaymentMethodChoiceSelected(form.paymentMethodChoices[1]))
    }

    func testSaveConvertsDraftPagesToReceiptAttachmentsAndExtractionRecord() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let group = ExpenseGroup(name: "Berlin June 2026")
        let draft = ReceiptDraft(
            rawOCRText: "REWE\nSUMME 84,50 EUR",
            modelOutputJSON: #"{"version":1}"#,
            ocrConfidence: 0.42
        )
        let firstPage = ReceiptDraftPage(
            imageData: Data([0x01, 0x02]),
            thumbnailData: Data([0x03]),
            pageIndex: 0,
            sourceType: .photoImport,
            draft: draft
        )
        let secondPage = ReceiptDraftPage(
            imageData: Data([0x04, 0x05]),
            thumbnailData: Data([0x06]),
            pageIndex: 1,
            sourceType: .photoImport,
            draft: draft
        )
        draft.pages = [firstPage, secondPage]
        context.insert(group)
        context.insert(draft)
        context.insert(firstPage)
        context.insert(secondPage)

        let form = ReceiptReviewForm(
            draft: draft,
            mergedReceipt: completeMergedReceipt(rawText: draft.rawOCRText)
        )

        let receipt = try form.save(in: context, group: group)

        XCTAssertEqual(receipt.group?.name, "Berlin June 2026")
        XCTAssertEqual(receipt.vendor, "REWE")
        XCTAssertEqual(receipt.totalAmount, Decimal(string: "84.50")!)
        XCTAssertEqual(receipt.attachments?.count, 2)
        XCTAssertEqual(receipt.attachments?.sorted { $0.pageIndex < $1.pageIndex }.map(\.imageData), [Data([0x01, 0x02]), Data([0x04, 0x05])])
        XCTAssertEqual(receipt.attachments?.first?.sourceType, .photoImport)
        XCTAssertEqual(receipt.extraction?.rawOCRText, "REWE\nSUMME 84,50 EUR")
        XCTAssertEqual(receipt.extraction?.modelOutputJSON, #"{"version":1}"#)
        XCTAssertEqual(receipt.extraction?.ocrConfidence, 0.42)
        XCTAssertTrue(form.didSave)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Receipt>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraftPage>()).isEmpty)
    }

    func testDiscardDeletesUnsavedDraftAndIsIdempotent() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let draft = ReceiptDraft(rawOCRText: "Unsaved")
        let page = ReceiptDraftPage(imageData: Data([0x01]), pageIndex: 0, draft: draft)
        draft.pages = [page]
        context.insert(draft)
        context.insert(page)
        let form = ReceiptReviewForm(draft: draft, mergedReceipt: completeMergedReceipt(rawText: draft.rawOCRText))

        form.discardIfUnsaved(in: context)
        form.discardIfUnsaved(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraftPage>()).isEmpty)
    }

    func testDiscardAfterSaveDoesNotDeleteSavedReceipt() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let draft = ReceiptDraft(rawOCRText: "Saved")
        let page = ReceiptDraftPage(imageData: Data([0x01]), pageIndex: 0, draft: draft)
        draft.pages = [page]
        context.insert(draft)
        context.insert(page)
        let form = ReceiptReviewForm(draft: draft, mergedReceipt: completeMergedReceipt(rawText: draft.rawOCRText))

        _ = try form.save(in: context, group: nil)
        form.discardIfUnsaved(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Receipt>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
    }

    func testManualFormSaveAndDiscardWorkWithoutDraft() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let form = ReceiptReviewForm.manual(defaultCurrencyCode: "USD")
        form.amountText = "12.50"
        form.categoryID = "food"
        form.paymentMethod = .card

        _ = try form.save(in: context, group: nil)
        form.discardIfUnsaved(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Receipt>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
    }

    func testSettingsDefaultsApplyOnlyWhenMergedValuesAreMissing() {
        let manual = ReceiptReviewForm.manual(
            defaultCurrencyCode: "cad",
            defaultPaymentMethod: .cash
        )

        XCTAssertEqual(manual.currencyCode, "CAD")
        XCTAssertEqual(manual.paymentMethod, .cash)

        let missingValues = ReceiptReviewForm(
            mergedReceipt: MergedReceipt(rawText: ""),
            defaultCurrencyCode: "gbp",
            defaultPaymentMethod: .cash
        )

        XCTAssertEqual(missingValues.currencyCode, "GBP")
        XCTAssertEqual(missingValues.paymentMethod, .cash)

        let extractedValues = ReceiptReviewForm(
            mergedReceipt: completeMergedReceipt(),
            defaultCurrencyCode: "USD",
            defaultPaymentMethod: .card
        )

        XCTAssertEqual(extractedValues.currencyCode, "EUR")
        XCTAssertEqual(extractedValues.paymentMethod, .cash)
    }

    func testSaveRecordsUserCorrectedFieldsComparedWithMergedPrimaries() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let form = ReceiptReviewForm(
            mergedReceipt: completeMergedReceipt(
                totalAmount: Decimal(string: "84.50")!,
                rawText: "REWE\nSUMME 84,50 EUR"
            )
        )
        form.vendor = "REWE City Edited"
        form.amountText = "85.25"

        let receipt = try form.save(in: context, group: nil)

        XCTAssertEqual(receipt.extraction?.userCorrectedFields, ["vendor", "totalAmount"])
    }

    func testGermanCommaAmountSavesAsFractionalDecimal() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let form = ReceiptReviewForm.manual(defaultCurrencyCode: "EUR", locale: Locale(identifier: "de_DE"))
        form.amountText = "12,50"
        form.categoryID = "food"
        form.paymentMethod = .cash

        let receipt = try form.save(in: context, group: nil)

        XCTAssertTrue(form.canSave)
        XCTAssertEqual(form.parsedAmount, Decimal(string: "12.50")!)
        XCTAssertEqual(receipt.totalAmount, Decimal(string: "12.50")!)
    }

    func testInvalidGroupedAmountCannotSave() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let form = ReceiptReviewForm.manual(defaultCurrencyCode: "EUR", locale: Locale(identifier: "de_DE"))
        form.amountText = "1.2.3"
        form.categoryID = "food"
        form.paymentMethod = .cash

        XCTAssertFalse(form.canSave)
        XCTAssertThrowsError(try form.save(in: context, group: nil)) { error in
            XCTAssertEqual(error as? ReceiptReviewFormError, .invalidAmount)
        }
    }

    func testGermanPrefillAndChoiceUseLocaleSeparator() {
        let form = ReceiptReviewForm(
            mergedReceipt: completeMergedReceipt(totalAmount: Decimal(string: "1234.50")!),
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertEqual(form.amountText, "1234,50")
        XCTAssertEqual(form.parsedAmount, Decimal(string: "1234.50")!)
        XCTAssertTrue(form.isTotalAmountChoiceSelected(form.totalAmountChoices[0]))

        let alternate = ReceiptFieldChoice(value: Decimal(string: "1235.60")!, source: .model, reason: nil)
        form.chooseTotalAmount(alternate)
        XCTAssertEqual(form.amountText, "1235,60")
        XCTAssertEqual(form.parsedAmount, Decimal(string: "1235.60")!)
    }

    func testReceiptDetailAmountEditorUsesLocaleAwareParserAndRejectsInvalidText() {
        let receipt = Receipt(
            vendor: "REWE",
            totalAmount: Decimal(string: "10.00")!,
            currencyCode: "EUR",
            expenseType: .food,
            paymentMethod: .cash
        )
        let editor = ReceiptDetailAmountEditor(receipt: receipt, locale: Locale(identifier: "de_DE"))

        editor.amountText = "84,50"

        XCTAssertEqual(receipt.totalAmount, Decimal(string: "84.50")!)
        XCTAssertNil(editor.validationMessageKey)

        editor.amountText = "abc"

        XCTAssertEqual(receipt.totalAmount, Decimal(string: "84.50")!)
        XCTAssertEqual(editor.validationMessageKey, "receipt.amount.invalid")
    }

    func testAutofillFromAttachedPhotoDoesNotOverwriteManualValues() {
        let form = ReceiptReviewForm.manual(defaultCurrencyCode: "USD")
        form.vendor = ""
        form.amountText = "41.00"
        form.currencyCode = "USD"
        form.date = date(2026, 6, 20)
        form.categoryID = "taxi"
        form.paymentMethod = .cash

        let diff = form.applyAutofill(
            MergedReceipt(
                vendor: MergedField(options: [MergedFieldOption(value: "Berlin Cab", source: .deterministic)]),
                date: MergedField(options: [MergedFieldOption(value: date(2026, 6, 20), source: .deterministic)]),
                totalAmount: MergedField(options: [MergedFieldOption(value: Decimal(string: "45.00")!, source: .deterministic)]),
                currencyCode: MergedField(options: [MergedFieldOption(value: "EUR", source: .deterministic)]),
                paymentMethod: MergedField(options: [MergedFieldOption(value: .card, source: .deterministic)]),
                expenseType: MergedField(options: [MergedFieldOption(value: .taxi, source: .model)]),
                rawText: "Berlin Cab\nTOTAL EUR 45.00"
            )
        )

        XCTAssertEqual(form.vendor, "Berlin Cab")
        XCTAssertEqual(form.amountText, "41.00")
        XCTAssertEqual(form.currencyCode, "USD")
        XCTAssertEqual(form.paymentMethod, .cash)
        XCTAssertEqual(diff.filledFields, ["vendor"])
        XCTAssertEqual(diff.conflictingFields, ["totalAmount", "currencyCode", "paymentMethod"])
    }

    func testApplyingAttachedCaptureAppendsPagesAndKeepsManualReceiptValues() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let receipt = Receipt(
            vendor: "",
            date: date(2026, 6, 20),
            totalAmount: Decimal(string: "41.00")!,
            currencyCode: "USD",
            expenseType: .taxi,
            paymentMethod: .cash
        )
        context.insert(receipt)

        let draft = ReceiptDraft(
            rawOCRText: "Berlin Cab\nSUMME 45,00 EUR\nKarte",
            modelOutputJSON: #"{"version":1}"#,
            ocrConfidence: 0.64
        )
        let page = ReceiptDraftPage(
            imageData: Data([0x0A, 0x0B]),
            thumbnailData: Data([0x0C]),
            pageIndex: 0,
            sourceType: .photoImport,
            draft: draft
        )
        draft.pages = [page]
        context.insert(draft)
        context.insert(page)

        let diff = try receipt.applyAttachedCapture(
            ReceiptProcessingResult(
                draft: draft,
                mergedReceipt: MergedReceipt(
                    vendor: MergedField(options: [MergedFieldOption(value: "Berlin Cab", source: .deterministic)]),
                    date: MergedField(options: [MergedFieldOption(value: date(2026, 6, 20), source: .deterministic)]),
                    totalAmount: MergedField(options: [MergedFieldOption(value: Decimal(string: "45.00")!, source: .deterministic)]),
                    currencyCode: MergedField(options: [MergedFieldOption(value: "EUR", source: .deterministic)]),
                    paymentMethod: MergedField(options: [MergedFieldOption(value: .card, source: .deterministic)]),
                    expenseType: MergedField(options: [MergedFieldOption(value: .taxi, source: .model)]),
                    rawText: draft.rawOCRText
                ),
                notice: nil
            ),
            in: context
        )

        XCTAssertEqual(receipt.vendor, "Berlin Cab")
        XCTAssertEqual(receipt.totalAmount, Decimal(string: "41.00")!)
        XCTAssertEqual(receipt.currencyCode, "USD")
        XCTAssertEqual(receipt.expenseType, .taxi)
        XCTAssertEqual(receipt.paymentMethod, .cash)
        XCTAssertEqual(receipt.attachments?.count, 1)
        XCTAssertEqual(receipt.attachments?.first?.imageData, Data([0x0A, 0x0B]))
        XCTAssertEqual(receipt.attachments?.first?.thumbnailData, Data([0x0C]))
        XCTAssertEqual(receipt.attachments?.first?.sourceType, .photoImport)
        XCTAssertEqual(receipt.extraction?.rawOCRText, draft.rawOCRText)
        XCTAssertEqual(receipt.extraction?.modelOutputJSON, #"{"version":1}"#)
        XCTAssertEqual(receipt.extraction?.ocrConfidence, 0.64)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
        XCTAssertEqual(diff.filledFields, ["vendor"])
        XCTAssertEqual(diff.conflictingFields, ["totalAmount", "currencyCode", "paymentMethod"])
    }

    func testDeterministicOnlyAttachmentDoesNotOverwriteExistingAuditJSONOrConfidence() throws {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let receipt = Receipt(
            vendor: "Cafe",
            totalAmount: Decimal(string: "10.00")!,
            currencyCode: "USD",
            expenseType: .food,
            paymentMethod: .card
        )
        let extraction = ExtractionRecord(
            rawOCRText: "Existing",
            modelOutputJSON: #"{"version":1,"existing":true}"#,
            ocrConfidence: 0.91,
            receipt: receipt
        )
        receipt.extraction = extraction
        context.insert(receipt)
        context.insert(extraction)

        let draft = ReceiptDraft(rawOCRText: "New deterministic text")
        let page = ReceiptDraftPage(imageData: Data([0x0D]), pageIndex: 0, draft: draft)
        draft.pages = [page]
        context.insert(draft)
        context.insert(page)

        _ = try receipt.applyAttachedCapture(
            ReceiptProcessingResult(
                draft: draft,
                mergedReceipt: completeMergedReceipt(rawText: draft.rawOCRText),
                notice: .smartExtractionPreparing
            ),
            in: context
        )

        XCTAssertEqual(receipt.extraction?.modelOutputJSON, #"{"version":1,"existing":true}"#)
        XCTAssertEqual(receipt.extraction?.ocrConfidence, 0.91)
    }

    private func ambiguousReviewForm() -> ReceiptReviewForm {
        ReceiptReviewForm(
            mergedReceipt: MergedReceipt(
                vendor: MergedField(options: [
                    MergedFieldOption(value: "Cafe Central", source: .deterministic),
                    MergedFieldOption(value: "Cafe Centrum", source: .model, reason: "Last word is faint")
                ]),
                date: MergedField(options: [
                    MergedFieldOption(value: date(2026, 6, 14), source: .deterministic),
                    MergedFieldOption(value: date(2026, 6, 15), source: .model, reason: "Receipt footer date")
                ]),
                totalAmount: MergedField(options: [
                    MergedFieldOption(value: Decimal(string: "18.40")!, source: .deterministic),
                    MergedFieldOption(value: Decimal(string: "13.40")!, source: .model, reason: "Faint digit")
                ]),
                currencyCode: MergedField(options: [
                    MergedFieldOption(value: "INR", source: .deterministic),
                    MergedFieldOption(value: "USD", source: .model, reason: "Symbol is damaged")
                ]),
                paymentMethod: MergedField(options: [
                    MergedFieldOption(value: .card, source: .deterministic),
                    MergedFieldOption(value: .cash, source: .model, reason: "Cash hint near footer")
                ]),
                expenseType: MergedField(options: [
                    MergedFieldOption(value: .food, source: .model),
                    MergedFieldOption(value: .other, source: .model, reason: "Vendor category uncertain")
                ]),
                rawText: "Cafe Central\nTOTAL INR 18.40"
            )
        )
    }

    private func completeMergedReceipt(
        totalAmount: Decimal = Decimal(string: "84.50")!,
        rawText: String = "REWE\nSUMME 84,50 EUR"
    ) -> MergedReceipt {
        MergedReceipt(
            vendor: MergedField(options: [MergedFieldOption(value: "REWE", source: .deterministic)]),
            date: MergedField(options: [MergedFieldOption(value: date(2026, 6, 14), source: .deterministic)]),
            totalAmount: MergedField(options: [MergedFieldOption(value: totalAmount, source: .deterministic)]),
            currencyCode: MergedField(options: [MergedFieldOption(value: "EUR", source: .deterministic)]),
            paymentMethod: MergedField(options: [MergedFieldOption(value: .cash, source: .deterministic)]),
            expenseType: MergedField(options: [MergedFieldOption(value: .food, source: .model)]),
            rawText: rawText
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
