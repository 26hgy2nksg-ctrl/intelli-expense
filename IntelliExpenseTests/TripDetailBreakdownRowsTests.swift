import ExpenseCore
import XCTest
@testable import IntelliExpense

final class TripDetailBreakdownRowsTests: XCTestCase {
    @MainActor
    func testBreakdownRowsFollowFolderOrderAndOmitAbsentCategories() {
        let summary = ExpenseGroupSummary(
            totals: [],
            breakdown: [
                "taxi": CategoryBreakdown(count: 1, totals: [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "31.50")!)]),
                "other": CategoryBreakdown(count: 1, totals: [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "5.00")!)]),
                "food": CategoryBreakdown(count: 2, totals: [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "20.50")!)])
            ]
        )

        // A default Work Trip folder orders visible categories flight, hotel, food, taxi, other;
        // rows keep that order for the used subset and omit unused categories.
        let group = ExpenseGroup(name: "Berlin")
        let rows = BreakdownRows.items(for: summary, in: group)

        XCTAssertEqual(rows.map(\.category.id), ["food", "taxi", "other"])
        XCTAssertEqual(rows.map(\.caption), ["2 Food", "1 Taxi", "1 Other"])
        XCTAssertEqual(rows.map(\.accessibilityIdentifier), [
            "group.breakdown.food",
            "group.breakdown.taxi",
            "group.breakdown.other"
        ])
        XCTAssertTrue(rows[0].accessibilityLabel.contains("2 receipts"))
    }

    func testBreakdownRowTapTogglesTheCategoryFilter() {
        XCTAssertEqual(BreakdownRows.toggledFilter(current: nil, tapped: "food"), "food")
        XCTAssertEqual(BreakdownRows.toggledFilter(current: "taxi", tapped: "food"), "food")
        XCTAssertNil(BreakdownRows.toggledFilter(current: "food", tapped: "food"))
    }

    func testBreakdownRowCatalogKeyReplacesRetiredCapsuleKey() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpense/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        XCTAssertEqual(try localizedValue(for: "group.breakdown.cell.caption", in: catalog), "%1$ld %2$@")
        XCTAssertNil(strings["group.breakdown.item"])
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func stringCatalog(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func localizedValue(for key: String, in catalog: [String: Any]) throws -> String {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let english = try XCTUnwrap(localizations["en"] as? [String: Any])
        let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
