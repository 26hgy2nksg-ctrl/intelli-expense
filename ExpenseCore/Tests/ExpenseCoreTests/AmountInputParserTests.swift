import XCTest
@testable import ExpenseCore

final class AmountInputParserTests: XCTestCase {
    func testParsesLocaleAwareAmountTextStrictly() {
        let cases: [(String, String, Decimal?)] = [
            ("12.50", "en_US", Decimal(string: "12.50")!),
            ("12,50", "de_DE", Decimal(string: "12.50")!),
            ("12.50", "de_DE", Decimal(string: "12.50")!),
            ("1,234.56", "en_US", Decimal(string: "1234.56")!),
            ("1.234,56", "de_DE", Decimal(string: "1234.56")!),
            ("1.234.567", "de_DE", Decimal(string: "1234567")!),
            ("12,345", "en_US", Decimal(string: "12345")!),
            ("12,345", "de_DE", Decimal(string: "12.345")!),
            ("1.2.3", "en_US", nil),
            ("12,50abc", "de_DE", nil),
            ("-5", "en_US", nil),
            ("", "en_US", nil),
            ("   ", "en_US", nil),
            (",5", "de_DE", Decimal(string: "0.5")!)
        ]

        for (text, localeIdentifier, expected) in cases {
            XCTAssertEqual(
                AmountInputParser.parse(text, locale: Locale(identifier: localeIdentifier)),
                expected,
                "Expected \(String(describing: expected)) for \(text) in \(localeIdentifier)"
            )
        }
    }

    func testRoundTripsTwoFractionDigitValuesAcrossLaunchLocales() throws {
        let values = [
            Decimal(string: "0")!,
            Decimal(string: "0.50")!,
            Decimal(string: "12.05")!,
            Decimal(string: "1234.50")!,
            Decimal(string: "999999.99")!
        ]
        let locales = ["en_US", "de_DE", "fr_FR", "en_IN", "ja_JP"].map(Locale.init(identifier:))

        for locale in locales {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.usesGroupingSeparator = false

            for value in values {
                let text = try XCTUnwrap(formatter.string(from: value as NSDecimalNumber))
                XCTAssertEqual(AmountInputParser.parse(text, locale: locale), value)
            }
        }
    }
}
