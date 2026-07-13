import XCTest
@testable import ExpenseCore

final class ReceiptPromptEvidenceBuilderTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-07-05T00:00:00Z")!

    func testIndianGSTEvidenceMarksGrandTotalAndVendor() throws {
        let evidence = try buildEvidence(for: "indian_gst", defaultCurrencyCode: "INR")

        XCTAssertEqual(evidence.vendorCandidates.first?.text, "ANAND RESTAURANT")
        XCTAssertTrue(
            evidence.amountCandidates.contains {
                $0.role == .finalTotal
                    && $0.amount == Decimal(string: "1240.00")!
                    && $0.evidence.contains("GRAND TOTAL")
                    && $0.supportsModelTotal
            }
        )

        let trustedLines = evidence.amountCandidates
            .filter(\.supportsModelTotal)
            .map(\.evidence)
            .joined(separator: "\n")
        XCTAssertFalse(trustedLines.contains("Bill No"))
        XCTAssertFalse(trustedLines.contains("GSTIN"))
        XCTAssertFalse(trustedLines.contains("CGST"))
        XCTAssertFalse(trustedLines.contains("SGST"))
    }

    func testGermanEvidenceMarksSummeAndVendor() throws {
        let evidence = try buildEvidence(for: "german_rewe", defaultCurrencyCode: "EUR", locale: Locale(identifier: "de_DE"))

        XCTAssertEqual(evidence.vendorCandidates.first?.text, "REWE CITY")
        XCTAssertTrue(
            evidence.amountCandidates.contains {
                $0.role == .finalTotal
                    && $0.amount == Decimal(string: "84.50")!
                    && $0.evidence.contains("SUMME")
                    && $0.supportsModelTotal
            }
        )
    }

    func testFrenchEvidenceMarksTotalTTCAndVendor() throws {
        let evidence = try buildEvidence(for: "french_bakery", defaultCurrencyCode: "EUR", locale: Locale(identifier: "fr_FR"))

        XCTAssertEqual(evidence.vendorCandidates.first?.text, "BOULANGERIE LUMIERE")
        XCTAssertTrue(
            evidence.amountCandidates.contains {
                $0.role == .finalTotal
                    && $0.amount == Decimal(string: "11.00")!
                    && $0.evidence.contains("TOTAL TTC")
                    && $0.supportsModelTotal
            }
        )
    }

    func testSyntheticAirportEvidenceSupportsPayableTotalAndRejectsMetadataNumbers() throws {
        let evidence = try buildEvidence(for: "synthetic_airport_food_stall_ocr", defaultCurrencyCode: "INR")

        XCTAssertEqual(evidence.vendorCandidates.first?.text, "BLR SKY BITES - T1")
        XCTAssertFalse(evidence.vendorCandidates.map(\.text).contains("AIRPORT FOOD SERVICES"))
        XCTAssertFalse(evidence.vendorCandidates.map(\.text).contains("PRIVATE LIMITED"))
        XCTAssertFalse(evidence.vendorCandidates.map(\.text).contains("LOUNGE ATRIUM"))

        let supportedAmounts = evidence.amountCandidates.filter(\.supportsModelTotal)
        XCTAssertTrue(supportedAmounts.contains { $0.amount == Decimal(string: "150.0")! })
        XCTAssertFalse(supportedAmounts.contains { $0.amount == Decimal(string: "420001000900123456")! })
        XCTAssertFalse(supportedAmounts.contains { $0.amount == Decimal(string: "142.86")! })
        XCTAssertFalse(supportedAmounts.contains { $0.amount == Decimal(string: "7.14")! })
    }

    func testCrumpledPartialEvidenceDoesNotSurfaceOCRLetterNoiseAsSupportedAmount() throws {
        let evidence = try buildEvidence(for: "crumpled_partial", defaultCurrencyCode: "USD")

        XCTAssertEqual(evidence.vendorCandidates.first?.text, "CITY KIOSK")
        XCTAssertFalse(evidence.amountCandidates.contains { $0.supportsModelTotal && $0.evidence.contains("9.9O") })
    }

    func testSyntheticChennaiMarketEvidenceAssociatesSplitTotalRejectsQuantityAndPrefersBrand() throws {
        let evidence = try buildEvidence(for: "synthetic_chennai_market_ocr", defaultCurrencyCode: "INR")

        XCTAssertEqual(evidence.vendorCandidates.first?.text, "KAVERI FRESH MART")
        XCTAssertEqual(evidence.vendorCandidates.dropFirst().first?.text, "MYLAPORE")
        let printedTotal = Decimal(string: "1864.30")!
        let totalCandidate = evidence.amountCandidates.first { $0.amount == printedTotal && $0.role == .finalTotal }
        let quantityCandidate = evidence.amountCandidates.first { $0.evidence == "6.495" && $0.role == .quantity }

        XCTAssertEqual(totalCandidate?.supportsModelTotal, true)
        XCTAssertEqual(quantityCandidate?.role, .quantity)
        XCTAssertEqual(quantityCandidate?.supportsModelTotal, false)
    }

    func testLongEvidenceStaysUnderBudgetWhileRetainingTopVendorAndBottomTotal() throws {
        let middle = (0..<120).map { "noise-\($0) 12345" }.joined(separator: "\n")
        let rawText = [
            "TOP MERCHANT",
            middle,
            "GRAND TOTAL USD 44.00"
        ].joined(separator: "\n")
        let parser = ReceiptParser(referenceDate: referenceDate, defaultCurrencyCode: "USD")
        let parsed = parser.parse(rawText)
        let evidence = ReceiptPromptEvidenceBuilder(characterBudget: 500, defaultCurrencyCode: "USD")
            .build(rawText: rawText, deterministicReceipt: parsed)

        XCTAssertLessThanOrEqual(evidence.promptText.count, 500)
        XCTAssertTrue(evidence.promptText.contains("TOP MERCHANT"))
        XCTAssertTrue(evidence.promptText.contains("GRAND TOTAL USD 44.00"))
        XCTAssertFalse(evidence.promptText.contains("noise-50"))
    }

    func testTokenBudgetPathPreservesRequiredSurvivorsAndDropsLowerPrioritySections() {
        let rawText = [
            "TOP MERCHANT",
            (0..<30).map { "noise-\($0) 12345" }.joined(separator: "\n"),
            "GRAND TOTAL USD 44.00"
        ].joined(separator: "\n")
        let parsed = ReceiptParser(referenceDate: referenceDate, defaultCurrencyCode: "USD").parse(rawText)

        let evidence = ReceiptPromptEvidenceBuilder(characterBudget: 4_000, defaultCurrencyCode: "USD").build(
            rawText: rawText,
            deterministicReceipt: parsed,
            tokenBudget: 32,
            tokenCounter: { $0.split(whereSeparator: \.isWhitespace).count }
        )

        XCTAssertLessThanOrEqual(try XCTUnwrap(evidence.tokenCount), 32)
        XCTAssertTrue(evidence.promptText.contains("TOP MERCHANT"))
        XCTAssertTrue(evidence.promptText.contains("GRAND TOTAL USD 44.00"))
        XCTAssertFalse(evidence.promptText.contains("noise-15"))
    }

    private func buildEvidence(
        for fixture: String,
        defaultCurrencyCode: String,
        locale: Locale = Locale(identifier: "en_US")
    ) throws -> ReceiptPromptEvidence {
        let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let parser = ReceiptParser(referenceDate: referenceDate, defaultCurrencyCode: defaultCurrencyCode, locale: locale)
        let parsed = parser.parse(text)
        return ReceiptPromptEvidenceBuilder(defaultCurrencyCode: defaultCurrencyCode)
            .build(rawText: text, deterministicReceipt: parsed)
    }
}
