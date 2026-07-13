import Foundation

public struct SummaryCSVExporter: Sendable {
    private let commentRow: String

    public init(commentRow: String) {
        self.commentRow = commentRow
    }

    public func csvData(for receipts: [ExportReceipt]) -> Data {
        var rows: [String] = [
            "# \(commentRow)",
            "date,vendor,expense_type,payment_method,currency,amount,group,notes,has_image"
        ]

        rows.append(
            contentsOf: ExportFormatting.sortedReceipts(receipts).map { receipt in
                [
                    ExportFormatting.isoDate(receipt.date),
                    receipt.vendor,
                    receipt.categoryID,
                    receipt.paymentMethod.rawValue,
                    receipt.currencyCode.uppercased(),
                    ExportFormatting.decimalString(receipt.totalAmount),
                    receipt.groupName ?? "",
                    receipt.notes ?? "",
                    receipt.attachments.isEmpty ? "false" : "true"
                ]
                .map(Self.escape)
                .joined(separator: ",")
            }
        )

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data((rows.joined(separator: "\r\n") + "\r\n").utf8))
        return data
    }

    private static func escape(_ field: String) -> String {
        let requiresQuotes = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")

        guard requiresQuotes else {
            return field
        }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
