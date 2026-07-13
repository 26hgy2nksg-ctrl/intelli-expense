import XCTest
@testable import ExpenseCore

final class ModelOutputEvidenceValidatorTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-07-11T00:00:00Z")!

    func testUnsupportedAmountPrimaryMatchingInvoiceNumberIsDropped() {
        let evidence = evidence(
            vendors: ["ACME MARKET"],
            amounts: [
                amount("999999", role: .identifier, evidence: "Invoice 999999"),
                amount("12.40", role: .finalTotal, evidence: "TOTAL USD 12.40")
            ]
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "999999")!)
        )

        let validated = ModelOutputEvidenceValidator().validate(model, against: evidence)

        XCTAssertTrue(validated.totalAmount.isUnknown)
        XCTAssertNil(validated.totalAmount.primary)
    }

    func testUnsupportedAmountAlternateMatchingTaxLineIsDropped() {
        let evidence = evidence(
            vendors: ["ACME MARKET"],
            amounts: [
                amount("12.40", role: .finalTotal, evidence: "TOTAL USD 12.40"),
                amount("1.02", role: .tax, evidence: "Tax USD 1.02")
            ]
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(
                primary: Decimal(string: "12.40")!,
                alternate: .init(value: Decimal(string: "1.02")!, reason: "Tax line looked like a total")
            )
        )

        let validated = ModelOutputEvidenceValidator().validate(model, against: evidence)

        XCTAssertEqual(validated.totalAmount.primary?.value, Decimal(string: "12.40")!)
        XCTAssertNil(validated.totalAmount.alternate)
    }

    func testSupportedAmountWithEquivalentFormattingSurvives() {
        let evidence = evidence(
            vendors: ["BLR SKY BITES - T1"],
            amounts: [
                amount("150.00", role: .parserSupportedTotal, evidence: "parser total 150.0")
            ]
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "150.0")!)
        )

        let validated = ModelOutputEvidenceValidator().validate(model, against: evidence)

        XCTAssertEqual(validated.totalAmount.primary?.value, Decimal(string: "150.0")!)
    }

    func testUnsupportedVendorPrimaryMatchingTaxOrPaymentLineIsDropped() {
        let evidence = evidence(
            vendors: ["ANAND RESTAURANT"],
            amounts: [
                amount("1240.00", role: .finalTotal, evidence: "GRAND TOTAL ₹1,240.00")
            ]
        )
        let model = ModelExtractedReceipt(
            vendor: .known(primary: "GSTIN 27ABCDE1234F1Z5", alternate: .init(value: "Paid by VISA", reason: "Top receipt line"))
        )

        let validated = ModelOutputEvidenceValidator().validate(model, against: evidence)

        XCTAssertTrue(validated.vendor.isUnknown)
        XCTAssertNil(validated.vendor.primary)
        XCTAssertNil(validated.vendor.alternate)
    }

    func testSupportedVendorWithPunctuationCaseAndSpacingNormalizationSurvives() {
        let evidence = evidence(
            vendors: ["BLR SKY BITES - T1"],
            amounts: [
                amount("150.0", role: .parserSupportedTotal, evidence: "150.0")
            ]
        )
        let model = ModelExtractedReceipt(
            vendor: .known(primary: "blr sky bites t1")
        )

        let validated = ModelOutputEvidenceValidator().validate(model, against: evidence)

        XCTAssertEqual(validated.vendor.primary?.value, "blr sky bites t1")
    }

    func testHighConfidenceDeterministicAmountRemainsPrimaryWhenSupportedModelConflictExists() {
        let deterministic = ParsedReceipt(
            totalAmount: ParsedField(value: Decimal(string: "1240.00")!, confidence: .high, evidence: "GRAND TOTAL ₹1,240.00"),
            rawText: "ANAND RESTAURANT\nGRAND TOTAL ₹1,240.00\nTOTAL ₹1,420.00"
        )
        let evidence = evidence(
            vendors: ["ANAND RESTAURANT"],
            amounts: [
                amount("1240.00", role: .finalTotal, evidence: "GRAND TOTAL ₹1,240.00"),
                amount("1420.00", role: .finalTotal, evidence: "TOTAL ₹1,420.00")
            ]
        )
        let model = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "1420.00")!)
        )

        let validated = ModelOutputEvidenceValidator().validate(model, against: evidence)
        let merged = ReceiptMergePolicy().merge(deterministic: deterministic, model: validated)

        XCTAssertEqual(merged.totalAmount.options.map(\.value), [
            Decimal(string: "1240.00")!,
            Decimal(string: "1420.00")!
        ])
        XCTAssertEqual(merged.totalAmount.options.map(\.source), [.deterministic, .model])
    }

    func testImageGroundedPlausibleVendorAndTotalAreAcceptedWithLowTier() {
        let model = ModelExtractedReceipt(
            vendor: .known(primary: "FADED CAFE"),
            totalAmount: .known(primary: Decimal(string: "18.40")!)
        )

        let result = ModelOutputEvidenceValidator(referenceDate: referenceDate).validateWithAudit(
            model,
            against: evidence(vendors: ["UNKNOWN HEADER"], amounts: []),
            imageInputUsed: true
        )

        XCTAssertEqual(result.validatedReceipt.vendor.primary?.acceptanceTier, .imageGrounded)
        XCTAssertEqual(result.validatedReceipt.totalAmount.primary?.acceptanceTier, .imageGrounded)
        XCTAssertEqual(result.acceptance.vendor.primary, .imageGrounded)
        XCTAssertEqual(result.acceptance.totalAmount.primary, .imageGrounded)
    }

    func testImageGroundedAmountCollidingWithTaxOrIdentifierIsRejected() {
        let model = ModelExtractedReceipt(totalAmount: .known(primary: Decimal(string: "1.02")!))
        let result = ModelOutputEvidenceValidator(referenceDate: referenceDate).validateWithAudit(
            model,
            against: evidence(
                vendors: ["ACME"],
                amounts: [amount("1.02", role: .tax, evidence: "Tax USD 1.02")]
            ),
            imageInputUsed: true
        )

        XCTAssertTrue(result.validatedReceipt.totalAmount.isUnknown)
        XCTAssertEqual(result.acceptance.totalAmount.primary, .rejected)
    }

    func testSyntheticChennaiMarketModelKeepsPrintedTotalAndRejectsQuantityAlternate() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic_chennai_market_ocr", withExtension: "txt"))
        let rawText = try String(contentsOf: url, encoding: .utf8)
        let parsed = ReceiptParser(
            referenceDate: referenceDate,
            defaultCurrencyCode: "INR",
            locale: Locale(identifier: "en_IN")
        ).parse(rawText)
        let receiptEvidence = ReceiptPromptEvidenceBuilder(defaultCurrencyCode: "INR")
            .build(rawText: rawText, deterministicReceipt: parsed)
        let model = ModelExtractedReceipt(
            totalAmount: .known(
                primary: Decimal(string: "1864.30")!,
                alternate: .init(value: Decimal(string: "6.495")!, reason: "Parsed total from OCR.")
            )
        )

        let result = ModelOutputEvidenceValidator(referenceDate: referenceDate).validateWithAudit(
            model,
            against: receiptEvidence,
            imageInputUsed: true
        )

        XCTAssertEqual(result.validatedReceipt.totalAmount.primary?.value, Decimal(string: "1864.30")!)
        XCTAssertEqual(result.validatedReceipt.totalAmount.primary?.acceptanceTier, .evidenceSupported)
        XCTAssertNil(result.validatedReceipt.totalAmount.alternate)
        XCTAssertEqual(result.acceptance.totalAmount.alternate, .rejected)
    }

    func testTierTwoIsUnavailableOnTextOnlyPath() {
        let model = ModelExtractedReceipt(vendor: .known(primary: "IMAGE ONLY STORE"))
        let result = ModelOutputEvidenceValidator(referenceDate: referenceDate).validateWithAudit(
            model,
            against: evidence(vendors: ["OCR STORE"], amounts: []),
            imageInputUsed: false
        )

        XCTAssertTrue(result.validatedReceipt.vendor.isUnknown)
        XCTAssertEqual(result.acceptance.vendor.primary, .rejected)
    }

    func testPlausibilityRejectsFutureDateInvalidCurrencyAndNegativeImageTotal() {
        let model = ModelExtractedReceipt(
            date: .known(primary: ISO8601DateFormatter().date(from: "2026-07-13T00:00:00Z")!),
            totalAmount: .known(primary: Decimal(string: "-4.20")!),
            currencyCode: .known(primary: "ZZZ")
        )
        let result = ModelOutputEvidenceValidator(referenceDate: referenceDate).validateWithAudit(
            model,
            against: evidence(vendors: [], amounts: []),
            imageInputUsed: true
        )

        XCTAssertTrue(result.validatedReceipt.date.isUnknown)
        XCTAssertTrue(result.validatedReceipt.totalAmount.isUnknown)
        XCTAssertTrue(result.validatedReceipt.currencyCode.isUnknown)
        XCTAssertEqual(result.acceptance.date.primary, .rejected)
        XCTAssertEqual(result.acceptance.currencyCode.primary, .rejected)
    }

    func testValidISO4217CurrencyAndSaneDateSurviveTextOnlyValidation() {
        let model = ModelExtractedReceipt(
            date: .known(primary: ISO8601DateFormatter().date(from: "2026-07-10T00:00:00Z")!),
            currencyCode: .known(primary: "EUR")
        )
        let result = ModelOutputEvidenceValidator(referenceDate: referenceDate).validateWithAudit(
            model,
            against: evidence(vendors: [], amounts: []),
            imageInputUsed: false
        )

        XCTAssertEqual(result.validatedReceipt.date.primary?.value, model.date.primary?.value)
        XCTAssertEqual(result.validatedReceipt.currencyCode.primary?.value, "EUR")
        XCTAssertEqual(result.acceptance.currencyCode.primary, .evidenceSupported)
    }

    private func evidence(
        vendors: [String],
        amounts: [ReceiptAmountEvidenceCandidate]
    ) -> ReceiptPromptEvidence {
        ReceiptPromptEvidence(
            promptText: "OCR evidence",
            vendorCandidates: vendors.enumerated().map { index, vendor in
                ReceiptVendorEvidenceCandidate(id: "V\(index + 1)", text: vendor, evidence: vendor)
            },
            amountCandidates: amounts,
            parserLines: [],
            tailLines: []
        )
    }

    private func amount(
        _ value: String,
        role: ReceiptAmountEvidenceRole,
        evidence: String
    ) -> ReceiptAmountEvidenceCandidate {
        ReceiptAmountEvidenceCandidate(
            id: UUID().uuidString,
            amount: Decimal(string: value)!,
            currencyCode: "USD",
            evidence: evidence,
            role: role,
            supportsModelTotal: role.supportsModelTotalByDefault
        )
    }
}
