import XCTest
@testable import ExpenseCore

final class ExportTests: XCTestCase {
    func testSummaryCSVMatchesPRDContractSortsRowsAndRoundTripsDecimals() throws {
        let laterReceipt = ExportReceipt(
            id: "later",
            date: date(2026, 6, 14),
            vendor: "Cafe, \"Roma\"",
            totalAmount: Decimal(string: "12.34567890123456789")!,
            currencyCode: "eur",
            expenseType: .food,
            paymentMethod: .card,
            groupName: "Berlin",
            notes: "Line one\nLine two",
            attachments: [
                ExportAttachment(data: Data([0x01]), pageIndex: 0, fileExtension: "jpg")
            ]
        )
        let earlierManualReceipt = ExportReceipt(
            id: "earlier",
            date: date(2026, 6, 13),
            vendor: "Manual entry",
            totalAmount: Decimal(string: "9.00")!,
            currencyCode: "USD",
            expenseType: .taxi,
            paymentMethod: .cash,
            groupName: nil,
            notes: nil,
            attachments: []
        )

        let data = SummaryCSVExporter(
            commentRow: "Amounts are per receipt in original currency; calculate totals in your spreadsheet."
        ).csvData(for: [laterReceipt, earlierManualReceipt])

        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let csv = String(decoding: data.dropFirst(3), as: UTF8.self)
        let lines = csv.components(separatedBy: "\r\n")

        XCTAssertEqual(lines[0], "# Amounts are per receipt in original currency; calculate totals in your spreadsheet.")
        XCTAssertEqual(
            lines[1],
            "date,vendor,expense_type,payment_method,currency,amount,group,notes,has_image"
        )
        XCTAssertEqual(lines[2], "2026-06-13,Manual entry,taxi,cash,USD,9.00,,,false")
        XCTAssertTrue(csv.contains(#"2026-06-14,"Cafe, ""Roma""",food,card,EUR,12.34567890123456789,Berlin,"Line one"#))
        XCTAssertTrue(csv.contains("Line two\",true"))
    }

    func testFilenameSanitizerRemovesUnsafeCharactersAndDisambiguatesCollisions() {
        let receipts = [
            ExportReceipt(
                id: "a",
                date: date(2026, 6, 14),
                vendor: "Café/Roma: Central",
                totalAmount: Decimal(string: "12.30")!,
                currencyCode: "EUR",
                expenseType: .food,
                paymentMethod: .card,
                attachments: [
                    ExportAttachment(data: Data([0x01]), pageIndex: 0, fileExtension: "jpg")
                ]
            ),
            ExportReceipt(
                id: "b",
                date: date(2026, 6, 14),
                vendor: "Cafe Roma Central",
                totalAmount: Decimal(string: "12.30")!,
                currencyCode: "EUR",
                expenseType: .food,
                paymentMethod: .cash,
                attachments: [
                    ExportAttachment(data: Data([0x02]), pageIndex: 0, fileExtension: "jpg"),
                    ExportAttachment(data: Data([0x03]), pageIndex: 1, fileExtension: "jpg")
                ]
            )
        ]

        let filenames = ExportFilenameBuilder().attachmentFilenames(for: receipts)

        XCTAssertEqual(
            filenames.map(\.path),
            [
                "2026-06-14/2026-06-14_cafe-roma-central_EUR-12.30_p1.jpg",
                "2026-06-14/2026-06-14_cafe-roma-central_EUR-12.30_p2.jpg",
                "2026-06-14/2026-06-14_cafe-roma-central_2_EUR-12.30.jpg"
            ]
        )
    }

    func testArchiveFilenameUsesASCIISafeSlugWithFallback() {
        let builder = ExportFilenameBuilder()

        XCTAssertEqual(
            builder.archiveFilename(for: "Berlin/June ✈️ 2026", fallbackSlug: "unfiled-receipts"),
            "berlin-june-2026.zip"
        )
        XCTAssertEqual(
            builder.archiveFilename(for: "🧾🧾", fallbackSlug: "unfiled-receipts"),
            "unfiled-receipts.zip"
        )
    }

    func testArchiveContainsSummaryCSVDateFoldersImagesAndPhotoLessTextStubs() throws {
        let receipts = [
            ExportReceipt(
                id: "photo",
                date: date(2026, 6, 14),
                vendor: "Cafe Roma",
                totalAmount: Decimal(string: "12.30")!,
                currencyCode: "EUR",
                expenseType: .food,
                paymentMethod: .card,
                attachments: [
                    ExportAttachment(data: Data([0xCA, 0xFE]), pageIndex: 0, fileExtension: "jpg"),
                    ExportAttachment(data: Data([0xBA, 0xBE]), pageIndex: 1, fileExtension: "jpg")
                ]
            ),
            ExportReceipt(
                id: "manual",
                date: date(2026, 6, 15),
                vendor: "",
                totalAmount: Decimal(string: "9.00")!,
                currencyCode: "USD",
                expenseType: .other,
                paymentMethod: .cash,
                attachments: []
            )
        ]

        let archive = try ExportArchiveBuilder(
            csvCommentRow: "Amounts are per receipt in original currency; calculate totals in your spreadsheet.",
            manualEntryStub: manualStubTemplate
        ).archiveData(for: receipts)
        let entries = try StoredZipInspector.entries(in: archive)

        XCTAssertEqual(Set(entries.keys), [
            "summary.csv",
            "2026-06-14/2026-06-14_cafe-roma_EUR-12.30_p1.jpg",
            "2026-06-14/2026-06-14_cafe-roma_EUR-12.30_p2.jpg",
            "2026-06-15/2026-06-15_manual-entry_USD-9.00.txt"
        ])
        XCTAssertEqual(entries["2026-06-14/2026-06-14_cafe-roma_EUR-12.30_p1.jpg"], Data([0xCA, 0xFE]))
        XCTAssertEqual(entries["2026-06-14/2026-06-14_cafe-roma_EUR-12.30_p2.jpg"], Data([0xBA, 0xBE]))

        let csv = try XCTUnwrap(entries["summary.csv"])
        XCTAssertEqual(Array(csv.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertTrue(String(decoding: csv.dropFirst(3), as: UTF8.self).contains("2026-06-14,Cafe Roma,food,card,EUR,12.30"))

        let stub = try XCTUnwrap(entries["2026-06-15/2026-06-15_manual-entry_USD-9.00.txt"])
        XCTAssertEqual(
            String(decoding: stub, as: UTF8.self),
            """
            No image is attached to this receipt.
            Receipt ID: manual
            Vendor: Manual entry
            Date: 2026-06-15
            Amount: USD 9.00

            """
        )
    }

    func testSummaryCSVWritesStableCategoryIDsIncludingCustomFolderLocal() {
        let receipts = [
            ExportReceipt(
                id: "r1",
                date: date(2026, 6, 14),
                vendor: "AWS Summit",
                totalAmount: Decimal(string: "250.00")!,
                currencyCode: "USD",
                categoryID: "registration",
                paymentMethod: .card
            ),
            ExportReceipt(
                id: "r2",
                date: date(2026, 6, 15),
                vendor: "Print Co",
                totalAmount: Decimal(string: "40.00")!,
                currencyCode: "USD",
                categoryID: "custom_booth_setup",
                paymentMethod: .card
            )
        ]

        let csv = SummaryCSVExporter(commentRow: "comment").csvData(for: receipts)
        let text = String(decoding: csv.dropFirst(3), as: UTF8.self)

        XCTAssertTrue(text.contains("date,vendor,expense_type,payment_method,currency,amount,group,notes,has_image"))
        XCTAssertTrue(text.contains("2026-06-14,AWS Summit,registration,card,USD,250.00"))
        XCTAssertTrue(text.contains("2026-06-15,Print Co,custom_booth_setup,card,USD,40.00"))
    }

    func testArchiveProgressReportsReceiptPreparationInSortedOrder() throws {
        var progress: [ExportArchiveProgress] = []
        let receipts = [
            ExportReceipt(id: "b", date: date(2026, 6, 15), vendor: "B", totalAmount: 2, currencyCode: "EUR", expenseType: .food, paymentMethod: .card),
            ExportReceipt(id: "a", date: date(2026, 6, 14), vendor: "A", totalAmount: 1, currencyCode: "EUR", expenseType: .food, paymentMethod: .card)
        ]

        _ = try ExportArchiveBuilder(
            csvCommentRow: "Amounts are per receipt in original currency; calculate totals in your spreadsheet.",
            manualEntryStub: manualStubTemplate
        ).archiveData(for: receipts) { update in
            progress.append(update)
        }

        XCTAssertEqual(progress.map(\.completedReceipts), [0, 1, 2])
        XCTAssertEqual(progress.map(\.totalReceipts), [2, 2, 2])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }

    private var manualStubTemplate: ExportManualEntryStub {
        ExportManualEntryStub(
            unavailableMessage: "No image is attached to this receipt.",
            receiptIDLabel: "Receipt ID",
            vendorLabel: "Vendor",
            manualEntryVendor: "Manual entry",
            dateLabel: "Date",
            amountLabel: "Amount"
        )
    }
}

private enum StoredZipInspector {
    static func entries(in data: Data) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        var offset = 0

        while offset + 30 <= data.count {
            let signature = readUInt32(data, offset)
            guard signature == 0x04034B50 else {
                break
            }

            let method = readUInt16(data, offset + 8)
            let compressedSize = Int(readUInt32(data, offset + 18))
            let fileNameLength = Int(readUInt16(data, offset + 26))
            let extraLength = Int(readUInt16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + compressedSize

            XCTAssertEqual(method, 0, "M4 writer should use stored ZIP entries for deterministic tests")
            guard dataEnd <= data.count else {
                throw ZipInspectionError.truncatedEntry
            }

            let name = String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
            entries[name] = Data(data[dataStart..<dataEnd])
            offset = dataEnd
        }

        return entries
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private enum ZipInspectionError: Error {
        case truncatedEntry
    }
}
