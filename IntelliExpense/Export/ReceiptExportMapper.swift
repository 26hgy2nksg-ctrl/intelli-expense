import ExpenseCore
import Foundation
import SwiftData

@MainActor
enum ReceiptExportMapper {
    static func exportReceipt(from receipt: Receipt) -> ExportReceipt {
        ExportReceipt(
            id: String(describing: receipt.persistentModelID),
            date: receipt.date,
            vendor: receipt.vendor,
            totalAmount: receipt.totalAmount,
            currencyCode: receipt.currencyCode,
            categoryID: receipt.categoryID,
            paymentMethod: receipt.paymentMethod,
            groupName: receipt.group?.name,
            notes: receipt.notes,
            attachments: exportAttachments(from: receipt.attachments ?? [])
        )
    }

    static func exportReceipts(from receipts: [Receipt]) -> [ExportReceipt] {
        receipts.map(exportReceipt)
    }

    private static func exportAttachments(from attachments: [ReceiptAttachment]) -> [ExportAttachment] {
        attachments
            .sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.capturedAt < rhs.capturedAt
                }
                return lhs.pageIndex < rhs.pageIndex
            }
            .map { attachment in
                ExportAttachment(
                    data: attachment.imageData,
                    pageIndex: attachment.pageIndex,
                    fileExtension: "jpg"
                )
            }
    }
}
