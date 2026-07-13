import XCTest
@testable import ExpenseCore

final class ExtractionMergePolicyTests: XCTestCase {
    func testBoundaryFakesReturnConfiguredOCRModelAndAvailabilityStates() async throws {
        let pages = [
            OCRInputPage(id: "front", pageIndex: 0, imageData: Data([0x01, 0x02]))
        ]
        let ocr = FakeOCRService(
            result: .success(
                OCRResult(
                    pages: [
                        OCRTextPage(id: "front", pageIndex: 0, text: "TOTAL $12.00", confidence: 0.91)
                    ]
                )
            )
        )

        let ocrResult = try await ocr.recognizeText(from: pages)
        XCTAssertEqual(ocrResult.rawText, "TOTAL $12.00")

        let extracted = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "12.00")!),
            currencyCode: .known(primary: "USD"),
            expenseType: .known(primary: .food)
        )
        let model = FakeExtractionModelService(result: .success(extracted))
        let modelResult = try await model.extractReceipt(
            from: ExtractionModelRequest(rawText: ocrResult.rawText, localeIdentifier: "en_US")
        )
        XCTAssertEqual(modelResult.expenseType.primary?.value, .food)

        let availability = FakeModelAvailabilityProvider(status: .modelNotReady, supportsImageInput: true)
        let availabilityStatus = await availability.currentAvailability()
        XCTAssertEqual(availabilityStatus, .modelNotReady)
        XCTAssertTrue(availability.supportsImageInput())
        XCTAssertFalse(ModelAvailabilityStatus.modelNotReady.blocksCapture)
        XCTAssertTrue(ModelAvailabilityStatus.appleIntelligenceNotEnabled.blocksCapture)
        XCTAssertTrue(ModelAvailabilityStatus.deviceNotEligible.blocksCapture)

        let unsupported = FakeExtractionModelService(
            result: .failure(.unsupportedLanguageOrLocale("de_DE"))
        )
        do {
            _ = try await unsupported.extractReceipt(
                from: ExtractionModelRequest(rawText: "SUMME 8,50", localeIdentifier: "de_DE")
            )
            XCTFail("Expected unsupported language failure")
        } catch ExtractionModelError.unsupportedLanguageOrLocale(let identifier) {
            XCTAssertEqual(identifier, "de_DE")
        }
    }

    func testExtractionRequestCarriesOrderedPromptImagesAndAttemptBudget() {
        let images = [
            ExtractionModelImage(pageIndex: 0, imageData: Data([0x01]), longEdgePixels: 1_280),
            ExtractionModelImage(pageIndex: 2, imageData: Data([0x03]), longEdgePixels: 1_280)
        ]

        let request = ExtractionModelRequest(
            rawText: "receipt",
            localeIdentifier: "en_US",
            images: images,
            timeoutSeconds: 22
        )

        XCTAssertEqual(request.images, images)
        XCTAssertEqual(request.timeoutSeconds, 22)
    }

    func testModelFieldSchemaShapeSupportsPrimarySingleAlternateAndExplicitUnknown() {
        let field = ModelField<Decimal>.known(
            primary: Decimal(string: "1240.00")!,
            alternate: .init(value: Decimal(string: "1420.00")!, reason: "Two bold totals were visible")
        )

        XCTAssertFalse(field.isUnknown)
        XCTAssertEqual(field.primary?.value, Decimal(string: "1240.00")!)
        XCTAssertEqual(field.alternate?.value, Decimal(string: "1420.00")!)
        XCTAssertEqual(field.alternate?.reason, "Two bold totals were visible")

        let unknown = ModelField<String>.unknown()
        XCTAssertTrue(unknown.isUnknown)
        XCTAssertNil(unknown.primary)
        XCTAssertNil(unknown.alternate)
    }

    func testOCRResultAggregatesPageConfidenceAsMinimumKnownConfidence() {
        let mixed = OCRResult(
            pages: [
                OCRTextPage(id: "front", pageIndex: 0, text: "A", confidence: 0.9),
                OCRTextPage(id: "back", pageIndex: 1, text: "B", confidence: 0.4),
                OCRTextPage(id: "extra", pageIndex: 2, text: "C", confidence: nil)
            ],
            skippedPageIndices: [3]
        )
        XCTAssertEqual(mixed.aggregateConfidence, 0.4)
        XCTAssertEqual(mixed.skippedPageIndices, [3])

        let unknown = OCRResult(
            pages: [
                OCRTextPage(id: "front", pageIndex: 0, text: "A", confidence: nil)
            ]
        )
        XCTAssertNil(unknown.aggregateConfidence)
    }

    func testModelOutputAuditEncoderProducesStableVersionedJSONWithPathAttemptsAndAcceptance() throws {
        let receipt = ModelExtractedReceipt(
            vendor: .known(primary: "REWE CITY", alternate: .init(value: "REWE", reason: "Short header candidate")),
            date: .known(primary: date(2026, 6, 14)),
            totalAmount: .known(primary: Decimal(string: "84.50")!, alternate: .init(value: Decimal(string: "48.50")!, reason: "Faint leading digit")),
            currencyCode: .known(primary: "EUR"),
            paymentMethod: .known(primary: .cash),
            expenseType: .known(primary: .food)
        )

        let validation = ModelOutputEvidenceValidator(referenceDate: date(2026, 7, 11)).validateWithAudit(
            receipt,
            against: ReceiptPromptEvidence(
                promptText: "OCR evidence",
                vendorCandidates: [.init(id: "V1", text: "REWE CITY", evidence: "REWE CITY")],
                amountCandidates: [.init(id: "A1", amount: Decimal(string: "84.50")!, currencyCode: "EUR", evidence: "SUMME 84,50", role: .finalTotal, supportsModelTotal: true)],
                parserLines: ["date=2026-06-14", "currencyCode=EUR"],
                tailLines: []
            ),
            imageInputUsed: true
        )
        let json = try ModelOutputAuditEncoder.json(
            for: receipt,
            context: ModelOutputAuditContext(
                imageInputUsed: true,
                attachmentCount: 2,
                attachmentLongEdges: [1_280, 1_280],
                attemptCount: 2,
                acceptance: validation.acceptance
            )
        )

        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["version"] as? Int, 2)
        XCTAssertEqual(decoded?["imageInputUsed"] as? Bool, true)
        XCTAssertEqual(decoded?["attachmentCount"] as? Int, 2)
        XCTAssertEqual(decoded?["attachmentLongEdges"] as? [Int], [1_280, 1_280])
        XCTAssertEqual(decoded?["attemptCount"] as? Int, 2)
        XCTAssertNotNil(decoded?["rawOutput"] as? [String: Any])
        let acceptance = try XCTUnwrap(decoded?["acceptance"] as? [String: Any])
        let vendor = try XCTUnwrap(acceptance["vendor"] as? [String: Any])
        XCTAssertEqual(vendor["primary"] as? String, ModelOutputAcceptanceTier.evidenceSupported.rawValue)
    }

    func testDeterministicHighConfidenceWinsAndModelConflictBecomesSecondChip() {
        let deterministic = ParsedReceipt(
            totalAmount: ParsedField(value: Decimal(string: "1240.00")!, confidence: .high, evidence: "Grand Total ₹1,240.00"),
            currencyCode: ParsedField(value: "INR", confidence: .high, evidence: "Grand Total ₹1,240.00"),
            rawText: "Grand Total ₹1,240.00"
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(
                primary: Decimal(string: "1420.00")!,
                alternate: .init(value: Decimal(string: "1240.00")!, reason: "The printed total is partly crumpled")
            ),
            currencyCode: .known(primary: "INR")
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertEqual(merged.totalAmount.options.map(\.value), [Decimal(string: "1240.00")!, Decimal(string: "1420.00")!])
        XCTAssertEqual(merged.totalAmount.options.map(\.source), [.deterministic, .model])
        XCTAssertEqual(merged.totalAmount.options.count, 2)
        XCTAssertEqual(merged.currencyCode.primary?.value, "INR")
        XCTAssertEqual(merged.currencyCode.options.count, 1)
    }

    func testModelPrimaryWinsWhenDeterministicTotalIsLowConfidenceFallback() {
        let deterministic = ParsedReceipt(
            totalAmount: ParsedField(value: Decimal(string: "142.86")!, confidence: .low, evidence: "142.86"),
            currencyCode: ParsedField(value: "INR", confidence: .low, evidence: "142.86"),
            rawText: "142.86\n150.00\nTotal:"
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "150.00")!),
            currencyCode: .known(primary: "INR")
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertEqual(merged.totalAmount.options.map(\.value), [Decimal(string: "150.00")!, Decimal(string: "142.86")!])
        XCTAssertEqual(merged.totalAmount.options.map(\.source), [.model, .deterministic])
        XCTAssertEqual(merged.totalAmount.primary?.source, .model)
    }

    func testModelFillsDeterministicGapsAndClassifiesExpenseType() {
        let deterministic = ParsedReceipt(
            vendor: ParsedField(value: "ACME MARKET", confidence: .medium, evidence: "ACME MARKET"),
            date: ParsedField(value: date(2026, 6, 15), confidence: .medium, evidence: "06/15/2026"),
            rawText: "ACME MARKET\n06/15/2026"
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "13.02")!),
            currencyCode: .known(primary: "USD"),
            paymentMethod: .known(primary: .cash),
            expenseType: .known(primary: .food)
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertEqual(merged.vendor.primary?.value, "ACME MARKET")
        XCTAssertEqual(merged.vendor.primary?.source, .deterministic)
        XCTAssertEqual(merged.totalAmount.primary?.value, Decimal(string: "13.02")!)
        XCTAssertEqual(merged.totalAmount.primary?.source, .model)
        XCTAssertEqual(merged.paymentMethod.primary?.value, .cash)
        XCTAssertEqual(merged.expenseType.primary?.value, .food)
    }

    func testEveryMergedFieldIsCappedAtTwoOptions() {
        let deterministic = ParsedReceipt(
            totalAmount: ParsedField(value: Decimal(string: "10.00")!, confidence: .high, evidence: "TOTAL 10.00"),
            rawText: "TOTAL 10.00"
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(
                primary: Decimal(string: "11.00")!,
                alternate: .init(value: Decimal(string: "12.00")!, reason: "Another amount looked plausible")
            )
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertEqual(merged.totalAmount.options.map(\.value), [Decimal(string: "10.00")!, Decimal(string: "11.00")!])
        XCTAssertLessThanOrEqual(merged.totalAmount.options.count, 2)
    }

    func testImageGroundedOptionIsLowConfidenceAndDroppedBehindSupportedOption() {
        let deterministic = ParsedReceipt(
            totalAmount: ParsedField(value: Decimal(string: "10.00")!, confidence: .high, evidence: "TOTAL 10.00"),
            rawText: "TOTAL 10.00"
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(
                primary: ModelFieldCandidate(value: Decimal(string: "11.00")!, acceptanceTier: .evidenceSupported),
                alternate: ModelFieldCandidate(value: Decimal(string: "12.00")!, reason: "image only", acceptanceTier: .imageGrounded)
            )
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertEqual(merged.totalAmount.options.map(\.value), [Decimal(string: "10.00")!, Decimal(string: "11.00")!])
        XCTAssertEqual(merged.totalAmount.options[1].confidence, .medium)
    }

    func testImageGroundedModelValueNeverDisplacesExistingDeterministicPrimary() {
        let deterministic = ParsedReceipt(
            totalAmount: ParsedField(value: Decimal(string: "10.00")!, confidence: .low, evidence: "10.00"),
            rawText: "10.00"
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(
                primary: ModelFieldCandidate(value: Decimal(string: "11.00")!, acceptanceTier: .imageGrounded)
            )
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertEqual(merged.totalAmount.options.map(\.value), [Decimal(string: "10.00")!, Decimal(string: "11.00")!])
        XCTAssertEqual(merged.totalAmount.options.map(\.confidence), [.low, .low])
    }

    func testTooAmbiguousExtractionFallsBackToEmptyFields() {
        let deterministic = ParsedReceipt(rawText: "blurred torn receipt")
        let model = ModelExtractedReceipt(
            vendor: .known(primary: "Market", alternate: .init(value: "Mart", reason: "Header is torn")),
            date: .known(primary: date(2026, 6, 15), alternate: .init(value: date(2026, 6, 16), reason: "Date digits are smudged")),
            totalAmount: .known(primary: Decimal(string: "13.02")!, alternate: .init(value: Decimal(string: "18.02")!, reason: "Two totals are visible")),
            currencyCode: .known(primary: "USD", alternate: .init(value: "CAD", reason: "Currency symbol is unclear")),
            paymentMethod: .known(primary: .cash, alternate: .init(value: .card, reason: "Both cash and card text appears")),
            expenseType: .known(primary: .food, alternate: .init(value: .other, reason: "Merchant category is unclear"))
        )

        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: model)

        XCTAssertTrue(merged.requiresManualEntryFallback)
        XCTAssertTrue(merged.vendor.options.isEmpty)
        XCTAssertTrue(merged.date.options.isEmpty)
        XCTAssertTrue(merged.totalAmount.options.isEmpty)
        XCTAssertTrue(merged.expenseType.options.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}
