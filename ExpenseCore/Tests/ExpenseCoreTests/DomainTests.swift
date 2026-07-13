import XCTest
@testable import ExpenseCore

final class DomainTests: XCTestCase {
    func testExpenseTypeRawValuesMatchPRD() {
        XCTAssertEqual(
            ExpenseType.allCases.map(\.rawValue),
            ["food", "hotel", "flight", "taxi", "other"]
        )
    }

    func testPaymentMethodRawValuesMatchPRD() {
        XCTAssertEqual(PaymentMethod.allCases.map(\.rawValue), ["card", "cash"])
    }

    func testTotalsAreGroupedByCurrencyAndNeverConverted() {
        let receipts = [
            ExpenseSummary(amount: Decimal(string: "10.10")!, currencyCode: "EUR", expenseType: .food, paymentMethod: .card),
            ExpenseSummary(amount: Decimal(string: "2.20")!, currencyCode: "EUR", expenseType: .taxi, paymentMethod: .cash),
            ExpenseSummary(amount: Decimal(string: "5.00")!, currencyCode: "USD", expenseType: .food, paymentMethod: .cash)
        ]

        XCTAssertEqual(
            TotalsCalculator.totalsByCurrency(receipts),
            [
                CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "12.30")!),
                CurrencyTotal(currencyCode: "USD", amount: Decimal(string: "5.00")!)
            ]
        )
    }

    func testCategoryBreakdownCountsAndTotalsPerCurrency() {
        let receipts = [
            ExpenseSummary(amount: Decimal(string: "8.00")!, currencyCode: "EUR", categoryID: "food", paymentMethod: .card),
            ExpenseSummary(amount: Decimal(string: "4.00")!, currencyCode: "EUR", categoryID: "food", paymentMethod: .cash),
            ExpenseSummary(amount: Decimal(string: "22.00")!, currencyCode: "USD", categoryID: "taxi", paymentMethod: .cash),
            ExpenseSummary(amount: Decimal(string: "9.00")!, currencyCode: "USD", categoryID: "registration", paymentMethod: .card)
        ]

        let breakdown = TotalsCalculator.breakdownByCategoryID(receipts)

        XCTAssertEqual(breakdown["food"]?.count, 2)
        XCTAssertEqual(breakdown["food"]?.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "12.00")!)])
        XCTAssertEqual(breakdown["taxi"]?.count, 1)
        XCTAssertEqual(breakdown["taxi"]?.totals, [CurrencyTotal(currencyCode: "USD", amount: Decimal(string: "22.00")!)])
        // Dynamic, non-legacy category IDs group just like the built-in five.
        XCTAssertEqual(breakdown["registration"]?.count, 1)
        XCTAssertEqual(breakdown["registration"]?.totals, [CurrencyTotal(currencyCode: "USD", amount: Decimal(string: "9.00")!)])
    }

    func testLegacyExpenseTypeInitializerMapsToCategoryID() {
        let summary = ExpenseSummary(amount: 5, currencyCode: "usd", expenseType: .hotel, paymentMethod: .card)
        XCTAssertEqual(summary.categoryID, "hotel")
        XCTAssertEqual(summary.currencyCode, "USD")
    }

    func testUsedCategoryOrderingKeepsVisibleOrderThenAppendsLeftovers() {
        let ordered = CategoryOrdering.usedCategoryIDs(
            visibleOrder: ["flight", "hotel", "food", "taxi", "other"],
            usedIDs: ["food", "other", "materials", "flight"]
        )
        // Visible-and-used keep folder order; used-but-hidden ("materials") come last, sorted.
        XCTAssertEqual(ordered, ["flight", "food", "other", "materials"])
    }
}
