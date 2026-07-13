import Foundation

/// The five raw values that predate folder profiles. Kept for legacy compatibility only — new
/// domain and UI logic operates on category IDs (`String`) via `CategoryCatalog`, not this enum
/// (SPEC §D3). The AI extraction pipeline still classifies into these five, and the review layer
/// maps the result onto the folder's visible category set.
public enum ExpenseType: String, CaseIterable, Codable, Sendable {
    case food
    case hotel
    case flight
    case taxi
    case other

    /// The stable category ID for this legacy type. The raw values are already the canonical IDs.
    public var categoryID: String { rawValue }
}

public enum PaymentMethod: String, CaseIterable, Codable, Sendable {
    case card
    case cash
}

public struct ExpenseSummary: Equatable, Sendable {
    public var amount: Decimal
    public var currencyCode: String
    /// Stable category identifier (SPEC §6). Built-in or folder-local custom.
    public var categoryID: String
    public var paymentMethod: PaymentMethod

    public init(amount: Decimal, currencyCode: String, categoryID: String, paymentMethod: PaymentMethod) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.categoryID = categoryID
        self.paymentMethod = paymentMethod
    }

    /// Legacy convenience initializer that maps a five-case `ExpenseType` onto its category ID.
    public init(amount: Decimal, currencyCode: String, expenseType: ExpenseType, paymentMethod: PaymentMethod) {
        self.init(
            amount: amount,
            currencyCode: currencyCode,
            categoryID: expenseType.categoryID,
            paymentMethod: paymentMethod
        )
    }
}

public struct CurrencyTotal: Equatable, Sendable {
    public var currencyCode: String
    public var amount: Decimal

    public init(currencyCode: String, amount: Decimal) {
        self.currencyCode = currencyCode.uppercased()
        self.amount = amount
    }
}

public struct CategoryBreakdown: Equatable, Sendable {
    public var count: Int
    public var totals: [CurrencyTotal]

    public init(count: Int, totals: [CurrencyTotal]) {
        self.count = count
        self.totals = totals
    }
}

/// Legacy alias retained so existing call sites keep compiling while the codebase moves to
/// category-ID breakdowns.
public typealias ExpenseTypeBreakdown = CategoryBreakdown

public enum TotalsCalculator {
    public static func totalsByCurrency(_ receipts: [ExpenseSummary]) -> [CurrencyTotal] {
        let grouped = Dictionary(grouping: receipts, by: { $0.currencyCode.uppercased() })
        return grouped
            .map { currencyCode, receipts in
                CurrencyTotal(
                    currencyCode: currencyCode,
                    amount: receipts.reduce(Decimal.zero) { $0 + $1.amount }
                )
            }
            .sorted { $0.currencyCode < $1.currencyCode }
    }

    /// Breakdown keyed by stable category ID, preserving per-currency math (SPEC §6, §10).
    public static func breakdownByCategoryID(_ receipts: [ExpenseSummary]) -> [String: CategoryBreakdown] {
        Dictionary(grouping: receipts, by: \.categoryID).mapValues { receipts in
            CategoryBreakdown(
                count: receipts.count,
                totals: totalsByCurrency(receipts)
            )
        }
    }
}

/// Ordering helper for breakdowns and filters (SPEC §D7): visible categories keep their folder order;
/// categories used by receipts but no longer visible are appended afterward, sorted stably by ID.
public enum CategoryOrdering {
    /// Returns the category IDs to display, given the folder's ordered visible IDs and the set of IDs
    /// actually used by receipts. Only used categories appear; visible-but-unused IDs are omitted.
    public static func usedCategoryIDs(visibleOrder: [String], usedIDs: Set<String>) -> [String] {
        var result: [String] = []
        var placed = Set<String>()

        for id in visibleOrder where usedIDs.contains(id) {
            result.append(id)
            placed.insert(id)
        }

        let leftovers = usedIDs.subtracting(placed).sorted()
        result.append(contentsOf: leftovers)
        return result
    }
}
