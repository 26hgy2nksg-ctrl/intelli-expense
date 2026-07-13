import ExpenseCore
import XCTest
@testable import IntelliExpense

@MainActor
final class ExportShimTests: XCTestCase {
    func testReceiptExportMapperConvertsSwiftDataReceiptGraphToCoreDTO() {
        let group = ExpenseGroup(name: "Berlin June")
        let attachment = ReceiptAttachment(
            imageData: Data([0xCA, 0xFE]),
            thumbnailData: Data([0x01]),
            pageIndex: 0,
            sourceType: .cameraScan
        )
        let receipt = Receipt(
            vendor: "REWE CITY",
            date: date(2026, 6, 14),
            totalAmount: Decimal(string: "84.50")!,
            currencyCode: "eur",
            expenseType: .food,
            paymentMethod: .cash,
            notes: "Dinner supplies",
            group: group,
            attachments: [attachment]
        )
        attachment.receipt = receipt

        let exportReceipt = ReceiptExportMapper.exportReceipt(from: receipt)

        XCTAssertEqual(exportReceipt.vendor, "REWE CITY")
        XCTAssertEqual(exportReceipt.currencyCode, "EUR")
        XCTAssertEqual(exportReceipt.categoryID, "food")
        XCTAssertEqual(exportReceipt.paymentMethod, .cash)
        XCTAssertEqual(exportReceipt.groupName, "Berlin June")
        XCTAssertEqual(exportReceipt.notes, "Dinner supplies")
        XCTAssertEqual(exportReceipt.attachments, [
            ExportAttachment(data: Data([0xCA, 0xFE]), pageIndex: 0, fileExtension: "jpg")
        ])
    }

    func testExportReceiptsFromActiveGroupReceiptsExcludesArchivedReceipts() {
        let group = ExpenseGroup(name: "Berlin June")
        group.receipts = [
            Receipt(vendor: "Active Cafe", totalAmount: 10, currencyCode: "EUR", expenseType: .food, paymentMethod: .card, group: group),
            Receipt(vendor: "Archived Taxi", totalAmount: 5, currencyCode: "EUR", expenseType: .taxi, paymentMethod: .cash, isArchived: true, group: group)
        ]

        let exports = ReceiptExportMapper.exportReceipts(from: group.activeReceipts)

        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports.first?.vendor, "Active Cafe")
        XCTAssertFalse(exports.contains { $0.vendor == "Archived Taxi" })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}
