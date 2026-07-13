import Foundation

public struct ExportAttachment: Equatable, Sendable {
    public var data: Data
    public var pageIndex: Int
    public var fileExtension: String

    public init(data: Data, pageIndex: Int, fileExtension: String) {
        self.data = data
        self.pageIndex = pageIndex
        self.fileExtension = fileExtension
    }
}

public struct ExportReceipt: Equatable, Sendable {
    public var id: String
    public var date: Date
    public var vendor: String
    public var totalAmount: Decimal
    public var currencyCode: String
    /// Stable category identifier written to the `expense_type` CSV column (SPEC §D11).
    public var categoryID: String
    public var paymentMethod: PaymentMethod
    public var groupName: String?
    public var notes: String?
    public var attachments: [ExportAttachment]

    public init(
        id: String,
        date: Date,
        vendor: String,
        totalAmount: Decimal,
        currencyCode: String,
        categoryID: String,
        paymentMethod: PaymentMethod,
        groupName: String? = nil,
        notes: String? = nil,
        attachments: [ExportAttachment] = []
    ) {
        self.id = id
        self.date = date
        self.vendor = vendor
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode.uppercased()
        self.categoryID = categoryID
        self.paymentMethod = paymentMethod
        self.groupName = groupName
        self.notes = notes
        self.attachments = attachments
    }

    /// Legacy convenience initializer mapping a five-case `ExpenseType` onto its category ID.
    public init(
        id: String,
        date: Date,
        vendor: String,
        totalAmount: Decimal,
        currencyCode: String,
        expenseType: ExpenseType,
        paymentMethod: PaymentMethod,
        groupName: String? = nil,
        notes: String? = nil,
        attachments: [ExportAttachment] = []
    ) {
        self.init(
            id: id,
            date: date,
            vendor: vendor,
            totalAmount: totalAmount,
            currencyCode: currencyCode,
            categoryID: expenseType.categoryID,
            paymentMethod: paymentMethod,
            groupName: groupName,
            notes: notes,
            attachments: attachments
        )
    }
}

public struct ExportManualEntryStub: Equatable, Sendable {
    public var unavailableMessage: String
    public var receiptIDLabel: String
    public var vendorLabel: String
    public var manualEntryVendor: String
    public var dateLabel: String
    public var amountLabel: String

    public init(
        unavailableMessage: String,
        receiptIDLabel: String,
        vendorLabel: String,
        manualEntryVendor: String,
        dateLabel: String,
        amountLabel: String
    ) {
        self.unavailableMessage = unavailableMessage
        self.receiptIDLabel = receiptIDLabel
        self.vendorLabel = vendorLabel
        self.manualEntryVendor = manualEntryVendor
        self.dateLabel = dateLabel
        self.amountLabel = amountLabel
    }

    func text(for receipt: ExportReceipt) -> String {
        """
        \(unavailableMessage)
        \(receiptIDLabel): \(receipt.id)
        \(vendorLabel): \(receipt.vendor.isEmpty ? manualEntryVendor : receipt.vendor)
        \(dateLabel): \(ExportFormatting.isoDate(receipt.date))
        \(amountLabel): \(receipt.currencyCode.uppercased()) \(ExportFormatting.decimalString(receipt.totalAmount))

        """
    }
}

public struct ExportArchiveProgress: Equatable, Sendable {
    public var completedReceipts: Int
    public var totalReceipts: Int

    public init(completedReceipts: Int, totalReceipts: Int) {
        self.completedReceipts = completedReceipts
        self.totalReceipts = totalReceipts
    }
}

enum ExportFormatting {
    static func sortedReceipts(_ receipts: [ExportReceipt]) -> [ExportReceipt] {
        receipts.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }

            let vendorComparison = lhs.vendor.localizedStandardCompare(rhs.vendor)
            if vendorComparison != .orderedSame {
                return vendorComparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }

    static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func decimalString(_ decimal: Decimal) -> String {
        let raw = NSDecimalNumber(decimal: decimal).stringValue
        guard raw.contains(".") else {
            return raw + ".00"
        }

        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 1 else {
            return raw
        }
        return raw + "0"
    }

    static func filenameAmount(_ decimal: Decimal) -> String {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return decimalString(rounded)
    }
}
