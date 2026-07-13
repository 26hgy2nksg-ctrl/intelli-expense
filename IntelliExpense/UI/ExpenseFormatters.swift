import ExpenseCore
import Foundation

struct CurrencyTotalsPresentation: Equatable {
    var primary: String
    var secondary: [String]
}

enum ExpenseFormatters {
    static func money(_ amount: Decimal, currencyCode: String) -> String {
        money(amount, currencyCode: currencyCode, locale: .current)
    }

    static func money(_ amount: Decimal, currencyCode: String, locale: Locale) -> String {
        amount.formatted(
            .currency(code: currencyCode.uppercased())
                .locale(locale)
                .precision(.fractionLength(2))
        )
    }

    static func compactTotals(_ totals: [CurrencyTotal]) -> String {
        guard totals.isEmpty == false else {
            return String(localized: "totals.none")
        }
        return totals
            .map { money($0.amount, currencyCode: $0.currencyCode) }
            .joined(separator: String(localized: "totals.separator"))
    }

    static func totalPresentation(
        _ totals: [CurrencyTotal],
        locale: Locale = .current
    ) -> CurrencyTotalsPresentation {
        let ordered = totals.sorted { lhs, rhs in
            if lhs.amount != rhs.amount {
                return lhs.amount > rhs.amount
            }
            return lhs.currencyCode.localizedStandardCompare(rhs.currencyCode) == .orderedAscending
        }
        guard let primary = ordered.first else {
            return CurrencyTotalsPresentation(primary: String(localized: "totals.none"), secondary: [])
        }
        return CurrencyTotalsPresentation(
            primary: money(primary.amount, currencyCode: primary.currencyCode, locale: locale),
            secondary: ordered.dropFirst().map { money($0.amount, currencyCode: $0.currencyCode, locale: locale) }
        )
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func dayHeader(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month().day())
    }

    static func dateInterval(_ startDate: Date, _ endDate: Date) -> String {
        (startDate..<endDate)
            .formatted(.interval.year().month(.abbreviated).day())
    }

    static func typeName(_ type: ExpenseType) -> String {
        switch type {
        case .food: String(localized: "expense.type.food")
        case .hotel: String(localized: "expense.type.hotel")
        case .flight: String(localized: "expense.type.flight")
        case .taxi: String(localized: "expense.type.taxi")
        case .other: String(localized: "expense.type.other")
        }
    }

    static func paymentName(_ paymentMethod: PaymentMethod) -> String {
        switch paymentMethod {
        case .card: String(localized: "payment.card")
        case .cash: String(localized: "payment.cash")
        }
    }
}

extension ExpenseType {
    var systemImageName: String {
        switch self {
        case .food: "fork.knife"
        case .hotel: "bed.double.fill"
        case .flight: "airplane"
        case .taxi: "car.fill"
        case .other: "tag.fill"
        }
    }

    var colorName: String {
        switch self {
        case .food: "CategoryOrange"
        case .hotel: "CategoryIndigo"
        case .flight: "CategoryBlue"
        case .taxi: "CategoryTeal"
        case .other: "CategoryGray"
        }
    }
}
