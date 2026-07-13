import XCTest
@testable import ExpenseCore

final class ReceiptParserTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-07-05T00:00:00Z")!

    func testLanguageTableContainsNonEnglishTotalAndPaymentKnowledge() {
        let labels = ReceiptLanguageProfiles.allTotalLabels
        XCTAssertTrue(labels.contains("summe"))
        XCTAssertTrue(labels.contains("total ttc"))
        XCTAssertTrue(ReceiptLanguageProfiles.allCashHints.contains("bar"))
        XCTAssertTrue(ReceiptLanguageProfiles.allCardHints.contains("carte"))
        XCTAssertTrue(ReceiptLanguageProfiles.allVendorSkipKeywords.contains("gstin"))
        XCTAssertTrue(ReceiptLanguageProfiles.allMetadataKeywords.contains("cashier"))
        XCTAssertTrue(ReceiptLanguageProfiles.allCurrencyCodes.contains("AUD"))
    }

    func testParsesIndianGSTReceiptWithIndianGroupingAndCardPayment() throws {
        let result = try parseFixture("indian_gst")

        XCTAssertEqual(result.vendor?.value, "ANAND RESTAURANT")
        XCTAssertEqual(result.date?.value, date(2026, 6, 14))
        XCTAssertEqual(result.totalAmount?.value, Decimal(string: "1240.00")!)
        XCTAssertEqual(result.currencyCode?.value, "INR")
        XCTAssertEqual(result.paymentMethod?.value, .card)
        XCTAssertEqual(result.totalAmount?.confidence, .high)
    }

    func testParsesGermanReceiptWithDecimalCommaAndCashHint() throws {
        let result = try parseFixture("german_rewe")

        XCTAssertEqual(result.vendor?.value, "REWE CITY")
        XCTAssertEqual(result.date?.value, date(2026, 6, 14))
        XCTAssertEqual(result.totalAmount?.value, Decimal(string: "84.50")!)
        XCTAssertEqual(result.currencyCode?.value, "EUR")
        XCTAssertEqual(result.paymentMethod?.value, .cash)
    }

    func testParsesFrenchReceiptUsingLanguageTable() throws {
        let result = try parseFixture("french_bakery")

        XCTAssertEqual(result.vendor?.value, "BOULANGERIE LUMIERE")
        XCTAssertEqual(result.date?.value, date(2026, 6, 15))
        XCTAssertEqual(result.totalAmount?.value, Decimal(string: "11.00")!)
        XCTAssertEqual(result.currencyCode?.value, "EUR")
        XCTAssertEqual(result.paymentMethod?.value, .card)
    }

    func testParsesUSReceiptWithAmountDueAndCashPayment() throws {
        let result = try parseFixture("us_market")

        XCTAssertEqual(result.vendor?.value, "ACME MARKET")
        XCTAssertEqual(result.date?.value, date(2026, 6, 15))
        XCTAssertEqual(result.totalAmount?.value, Decimal(string: "13.02")!)
        XCTAssertEqual(result.currencyCode?.value, "USD")
        XCTAssertEqual(result.paymentMethod?.value, .cash)
    }

    func testPartialReceiptDoesNotInventUnsupportedTotal() throws {
        let result = try parseFixture("crumpled_partial")

        XCTAssertEqual(result.vendor?.value, "CITY KIOSK")
        XCTAssertEqual(result.date?.value, date(2026, 6, 16))
        XCTAssertNil(result.totalAmount)
    }

    func testAirportReceiptDoesNotUseInvoiceOrTaxIdentifiersAsTotal() throws {
        let result = try parseFixture("synthetic_airport_food_stall_ocr", defaultCurrencyCode: "INR")

        XCTAssertEqual(result.vendor?.value, "BLR SKY BITES - T1")
        XCTAssertEqual(result.totalAmount?.value, Decimal(string: "150.0")!)
        XCTAssertEqual(result.currencyCode?.value, "INR")
        XCTAssertFalse(result.totalAmount?.evidence.localizedCaseInsensitiveContains("inv no") ?? true)
        XCTAssertNotEqual(result.totalAmount?.value, Decimal(string: "420001000900123456")!)
    }

    func testSyntheticChennaiMarketReceiptUsesBrandAndSplitPrintedTotalInsteadOfQuantity() throws {
        let result = try parseFixture("synthetic_chennai_market_ocr", defaultCurrencyCode: "INR")

        XCTAssertEqual(result.vendor?.value, "KAVERI FRESH MART")
        XCTAssertEqual(result.totalAmount?.value, Decimal(string: "1864.30")!)
        XCTAssertEqual(result.totalAmount?.confidence, .high)
        XCTAssertEqual(result.currencyCode?.value, "INR")
        XCTAssertEqual(result.paymentMethod?.value, .card)
        XCTAssertNotEqual(result.totalAmount?.value, Decimal(string: "6495")!)
    }

    func testVendorDetectionStillScansPastLongMetadataHeaders() throws {
        let parser = ReceiptParser(referenceDate: referenceDate, defaultCurrencyCode: "USD")
        let metadata = Array(repeating: "Receipt", count: 14).joined(separator: "\n")
        let receipt = parser.parse("\(metadata)\nLATE MARKET\nTOTAL 12.50")

        XCTAssertEqual(receipt.vendor?.value, "LATE MARKET")
    }

    func testSanityRejectsFutureAndAncientDates() {
        let parser = ReceiptParser(referenceDate: referenceDate, defaultCurrencyCode: "USD")

        let future = parser.parse("FUTURE STORE\nDate: 01/01/2099\nTOTAL $10.00")
        XCTAssertNil(future.date)

        let ancient = parser.parse("OLD STORE\nDate: 12/31/1998\nTOTAL $10.00")
        XCTAssertNil(ancient.date)
    }

    func testAmbiguousSlashDateUsesLocaleProfileOrderAndExposesAlternate() {
        let germanParser = ReceiptParser(
            referenceDate: referenceDate,
            defaultCurrencyCode: "EUR",
            locale: Locale(identifier: "de_DE")
        )
        let german = germanParser.parse("BERLIN SHOP\nDatum 05/06/2026\nSUMME 10,00 EUR")

        XCTAssertEqual(german.date?.value, date(2026, 6, 5))
        XCTAssertEqual(german.dateAlternates.map(\.value), [date(2026, 5, 6)])

        let usParser = ReceiptParser(
            referenceDate: referenceDate,
            defaultCurrencyCode: "USD",
            locale: Locale(identifier: "en_US")
        )
        let us = usParser.parse("ACME MARKET\nDate 05/06/2026\nTOTAL $10.00")

        XCTAssertEqual(us.date?.value, date(2026, 5, 6))
        XCTAssertEqual(us.dateAlternates.map(\.value), [date(2026, 6, 5)])
    }

    func testMergePolicySurfacesDeterministicDateAlternatesAsChoices() {
        let parser = ReceiptParser(
            referenceDate: referenceDate,
            defaultCurrencyCode: "EUR",
            locale: Locale(identifier: "de_DE")
        )
        let parsed = parser.parse("BERLIN SHOP\nDatum 05/06/2026\nSUMME 10,00 EUR")

        let merged = ReceiptMergePolicy().merge(deterministic: parsed)

        XCTAssertEqual(merged.date.options.map(\.value), [date(2026, 6, 5), date(2026, 5, 6)])
        XCTAssertEqual(merged.date.options.map(\.source), [.deterministic, .deterministic])
    }

    func testAmountParserHandlesIndianGroupingAndDecimalComma() throws {
        let inr = try XCTUnwrap(ReceiptAmountParser.parse("₹1,23,456.78", defaultCurrencyCode: "INR"))
        XCTAssertEqual(inr.amount, Decimal(string: "123456.78")!)
        XCTAssertEqual(inr.currencyCode, "INR")

        let eur = try XCTUnwrap(ReceiptAmountParser.parse("€84,50", defaultCurrencyCode: "EUR"))
        XCTAssertEqual(eur.amount, Decimal(string: "84.50")!)
        XCTAssertEqual(eur.currencyCode, "EUR")
    }

    func testAmountParserPreservesSingleDecimalPlaceBeforeOCRNoise() throws {
        let amount = try XCTUnwrap(ReceiptAmountParser.parse("150.0îŠ†", defaultCurrencyCode: "INR"))

        XCTAssertEqual(amount.amount, Decimal(string: "150.0")!)
        XCTAssertEqual(amount.currencyCode, "INR")
        XCTAssertEqual(amount.evidence, "150.0")
    }

    private func parseFixture(_ name: String, defaultCurrencyCode: String = "USD") throws -> ParsedReceipt {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return ReceiptParser(referenceDate: referenceDate, defaultCurrencyCode: defaultCurrencyCode).parse(text)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}
