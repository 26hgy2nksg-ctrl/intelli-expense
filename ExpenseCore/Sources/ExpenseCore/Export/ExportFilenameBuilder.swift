import Foundation

public struct ExportEntryPath: Equatable, Sendable {
    public var receiptID: String
    public var pageIndex: Int?
    public var path: String

    public init(receiptID: String, pageIndex: Int?, path: String) {
        self.receiptID = receiptID
        self.pageIndex = pageIndex
        self.path = path
    }
}

public struct ExportFilenameBuilder: Sendable {
    public init() {}

    public func archiveFilename(for name: String, fallbackSlug: String) -> String {
        let fallback = Self.slug(fallbackSlug, fallback: "export")
        return "\(Self.slug(name, fallback: fallback)).zip"
    }

    public func attachmentFilenames(for receipts: [ExportReceipt]) -> [ExportEntryPath] {
        buildPaths(for: ExportFormatting.sortedReceipts(receipts)).flatMap(\.attachmentPaths)
    }

    func fileEntries(
        for receipts: [ExportReceipt],
        manualEntryStub: ExportManualEntryStub,
        onReceiptPrepared: ((Int) -> Void)? = nil
    ) throws -> [(path: String, data: Data)] {
        var entries: [(path: String, data: Data)] = []
        for (index, plannedReceipt) in buildPaths(for: receipts).enumerated() {
            try Task.checkCancellation()
            if plannedReceipt.receipt.attachments.isEmpty {
                entries.append((
                    path: plannedReceipt.stubPath,
                    data: Data(manualEntryStub.text(for: plannedReceipt.receipt).utf8)
                ))
            } else {
                entries.append(contentsOf: zip(plannedReceipt.attachmentPaths, plannedReceipt.receipt.attachments.sorted { $0.pageIndex < $1.pageIndex })
                    .map { path, attachment in
                        (path: path.path, data: attachment.data)
                    })
            }
            onReceiptPrepared?(index + 1)
        }
        return entries
    }

    private func buildPaths(for receipts: [ExportReceipt]) -> [PlannedReceiptPaths] {
        var baseCounts: [String: Int] = [:]

        return receipts.map { receipt in
            let date = ExportFormatting.isoDate(receipt.date)
            let vendor = Self.vendorSlug(receipt.vendor)
            let currency = receipt.currencyCode.uppercased()
            let amount = ExportFormatting.filenameAmount(receipt.totalAmount)
            let baseKey = "\(date)_\(vendor)_\(currency)-\(amount)"
            let duplicateIndex = (baseCounts[baseKey] ?? 0) + 1
            baseCounts[baseKey] = duplicateIndex

            let vendorPart = duplicateIndex == 1 ? vendor : "\(vendor)_\(duplicateIndex)"
            let stem = "\(date)_\(vendorPart)_\(currency)-\(amount)"
            let folder = date
            let orderedAttachments = receipt.attachments.sorted { $0.pageIndex < $1.pageIndex }
            let attachmentPaths = orderedAttachments.map { attachment in
                let extensionValue = Self.sanitizedExtension(attachment.fileExtension)
                let pageSuffix = orderedAttachments.count > 1 ? "_p\(attachment.pageIndex + 1)" : ""
                return ExportEntryPath(
                    receiptID: receipt.id,
                    pageIndex: attachment.pageIndex,
                    path: "\(folder)/\(stem)\(pageSuffix).\(extensionValue)"
                )
            }

            return PlannedReceiptPaths(
                receipt: receipt,
                attachmentPaths: attachmentPaths,
                stubPath: "\(folder)/\(stem).txt"
            )
        }
    }

    private static func vendorSlug(_ vendor: String) -> String {
        slug(vendor, fallback: "manual-entry")
    }

    private static func slug(_ value: String, fallback: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var result = ""
        var previousWasSeparator = false
        for scalar in folded.unicodeScalars {
            let isAlphanumeric = CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
            if isAlphanumeric {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if previousWasSeparator == false {
                result.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func sanitizedExtension(_ fileExtension: String) -> String {
        let trimmed = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let safe = vendorSlug(trimmed).replacingOccurrences(of: "-", with: "")
        return safe.isEmpty ? "jpg" : safe
    }

    private struct PlannedReceiptPaths {
        var receipt: ExportReceipt
        var attachmentPaths: [ExportEntryPath]
        var stubPath: String
    }
}
