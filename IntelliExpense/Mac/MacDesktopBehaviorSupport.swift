#if os(macOS)
import AppKit
import CoreTransferable
import ExpenseCore
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum MacReceiptOperations {
    @MainActor
    static func archive(_ receipts: [Receipt], in context: ModelContext) throws {
        try grouped(receipts, actionName: String(localized: "receipt.archive"), in: context) { receipt in
            receipt.isArchived = true
            receipt.archivedAt = Date()
        }
    }

    @MainActor
    static func restore(_ receipts: [Receipt], in context: ModelContext) throws {
        try grouped(receipts, actionName: String(localized: "receipt.restore"), in: context) { receipt in
            receipt.isArchived = false
            receipt.archivedAt = nil
        }
    }

    @MainActor
    static func move(_ receipts: [Receipt], to group: ExpenseGroup?, in context: ModelContext) throws {
        let changed = receipts.filter { $0.group?.persistentModelID != group?.persistentModelID || $0.isArchived }
        guard changed.isEmpty == false else { return }

        let undoManager = context.undoManager
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        for receipt in changed {
            if let oldGroup = receipt.group {
                oldGroup.receipts?.removeAll { $0.persistentModelID == receipt.persistentModelID }
            }
            receipt.group = group
            receipt.isArchived = false
            receipt.archivedAt = nil
            if let group,
               group.receipts?.contains(where: { $0.persistentModelID == receipt.persistentModelID }) == false {
                group.receipts?.append(receipt)
            }
        }
        try context.save()
        undoManager?.setActionName(String(localized: "receipt.action.moveToTrip"))
    }

    @MainActor
    static func delete(_ receipts: [Receipt], in context: ModelContext) throws {
        guard receipts.isEmpty == false else { return }
        let undoManager = context.undoManager
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        receipts.forEach(context.delete)
        try context.save()
        undoManager?.setActionName(String(localized: "common.delete"))
    }

    @MainActor
    private static func grouped(
        _ receipts: [Receipt],
        actionName: String,
        in context: ModelContext,
        mutation: (Receipt) -> Void
    ) throws {
        guard receipts.isEmpty == false else { return }
        let undoManager = context.undoManager
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        receipts.forEach(mutation)
        try context.save()
        undoManager?.setActionName(actionName)
    }
}

enum MacDockBadge {
    static func pendingCount(in drafts: [ReceiptDraft]) -> Int {
        AgentPendingEntry.entries(from: drafts).count
    }

    static func label(for count: Int) -> String? {
        count > 0 ? String(count) : nil
    }

    @MainActor
    static func update(for drafts: [ReceiptDraft]) {
        NSApp.dockTile.badgeLabel = label(for: pendingCount(in: drafts))
    }
}

struct MacSidebarMetrics: Equatable {
    var unfiledReceiptCount: Int
    var archivedFolderCount: Int
    var showsArchivedDestination: Bool

    init(groups: [ExpenseGroup], receipts: [Receipt]) {
        unfiledReceiptCount = receipts.count { receipt in
            receipt.group == nil && receipt.isEffectivelyArchived == false
        }
        archivedFolderCount = groups.count(where: \.isArchived)
        showsArchivedDestination = archivedFolderCount > 0
            || receipts.contains(where: \.isEffectivelyArchived)
    }
}

enum MacSidebarFoldersExpansion {
    private static let collapsedValue = "collapsed"
    private static let expandedValue = "expanded"

    static func isExpanded(restoredValue: String) -> Bool {
        restoredValue != collapsedValue
    }

    static func restoredValue(isExpanded: Bool) -> String {
        isExpanded ? expandedValue : collapsedValue
    }
}

enum MacReceiptSearch {
    static func matches(_ receipt: Receipt, query: String) -> Bool {
        query.isEmpty
            || receipt.vendor.localizedStandardContains(query)
            || receipt.notes?.localizedStandardContains(query) == true
    }
}

struct MacContentZoom: Equatable {
    static let minimumStep = -2
    static let maximumStep = 8
    private static let factors: [CGFloat] = [0.85, 0.925, 1, 1.1, 1.2, 1.35, 1.5, 1.7, 1.85, 2, 2.2]

    var step: Int {
        didSet { step = min(max(step, Self.minimumStep), Self.maximumStep) }
    }

    init(step: Int) {
        self.step = min(max(step, Self.minimumStep), Self.maximumStep)
    }

    var factor: CGFloat { Self.factors[step - Self.minimumStep] }
    var canZoomIn: Bool { step < Self.maximumStep }
    var canZoomOut: Bool { step > Self.minimumStep }
    var isActualSize: Bool { step == 0 }

    mutating func zoomIn() { step = min(step + 1, Self.maximumStep) }
    mutating func zoomOut() { step = max(step - 1, Self.minimumStep) }
    mutating func reset() { step = 0 }
}

extension UTType {
    static let intelliExpenseReceipt = UTType(exportedAs: "com.nags.intelliexpense.receipt-transfer")
}

struct MacReceiptTransferItem: Codable, Transferable {
    var receiptKey: String
    private var preparedURL: URL?
    private var vendor: String
    private var pages: [Data]

    init?(receipt: Receipt) {
        let attachments = (receipt.attachments ?? []).sorted { $0.pageIndex < $1.pageIndex }
        guard attachments.isEmpty == false else { return nil }
        receiptKey = MacReceiptFileMaterializer.key(for: receipt)
        preparedURL = nil
        vendor = receipt.vendor
        pages = attachments.map(\.imageData)
    }

    init(receiptKey: String, url: URL) {
        self.receiptKey = receiptKey
        preparedURL = url
        vendor = url.deletingPathExtension().lastPathComponent
        pages = []
    }

    private enum CodingKeys: String, CodingKey {
        case receiptKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        receiptKey = try container.decode(String.self, forKey: .receiptKey)
        preparedURL = nil
        vendor = ""
        pages = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(receiptKey, forKey: .receiptKey)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .intelliExpenseReceipt)
        FileRepresentation(contentType: .data) { item in
            SentTransferredFile(try item.exportURL())
        } importing: { received in
            MacReceiptTransferItem(receiptKey: "", url: received.file)
        }
        ProxyRepresentation(exporting: { try $0.exportURL() })
    }

    private func exportURL() throws -> URL {
        if let preparedURL { return preparedURL }
        return try MacReceiptFileMaterializer.transferURL(vendor: vendor, pages: pages)
    }
}

enum MacReceiptFileMaterializer {
    static func materialize(_ receipts: [Receipt], purpose: String) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "IntelliExpense-\(purpose)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try receipts.flatMap { receipt in
            try (receipt.attachments ?? [])
                .sorted { $0.pageIndex < $1.pageIndex }
                .map { attachment in
                    let fileExtension = imageFileExtension(for: attachment.imageData)
                    let vendor = sanitized(receipt.vendor.isEmpty ? "receipt" : receipt.vendor)
                    let url = directory.appending(path: "\(vendor)-page-\(attachment.pageIndex + 1).\(fileExtension)")
                    try attachment.imageData.write(to: url, options: .atomic)
                    return url
                }
        }
    }

    static func transferURL(vendor: String, pages: [Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "IntelliExpense-drag-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeVendor = sanitized(vendor.isEmpty ? "receipt" : vendor)
        let urls = try pages.enumerated().map { pageIndex, data in
            let fileExtension = imageFileExtension(for: data)
            let url = directory.appending(path: "\(safeVendor)-page-\(pageIndex + 1).\(fileExtension)")
            try data.write(to: url, options: .atomic)
            return url
        }
        guard let first = urls.first else { throw CocoaError(.fileNoSuchFile) }
        if urls.count == 1 {
            return first
        }

        let folder = directory.appending(path: safeVendor, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in urls {
            try FileManager.default.moveItem(at: url, to: folder.appending(path: url.lastPathComponent))
        }
        return folder
    }

    static func key(for receipt: Receipt) -> String {
        String(describing: receipt.persistentModelID)
    }

    private static func imageFileExtension(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

struct MacMultiSelectionSummary: View {
    var receipts: [Receipt]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(selectedTitle)
                .contentScaledFont(.title.bold())

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    totals
                }
                VStack(alignment: .leading, spacing: 12) {
                    totals
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("mac.detail.multiSummary")
    }

    @ViewBuilder
    private var totals: some View {
        ForEach(Array(currencyTotals.enumerated()), id: \.element.currencyCode) { index, total in
            Text(ExpenseFormatters.money(total.amount, currencyCode: total.currencyCode))
                .contentScaledFont((index == 0 ? Font.title : Font.title3).weight(index == 0 ? .light : .regular))
                .monospacedDigit()
                .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .accessibilityIdentifier("mac.detail.multiSummary.total")
        }
    }

    private var selectedTitle: String {
        String.localizedStringWithFormat(String(localized: "receipts.selected.count"), receipts.count)
    }

    private var currencyTotals: [CurrencyTotal] {
        TotalsCalculator.totalsByCurrency(receipts.map(\.expenseSummary))
    }

    private var accessibilitySummary: String {
        ([selectedTitle] + currencyTotals.map { ExpenseFormatters.money($0.amount, currencyCode: $0.currencyCode) })
            .joined(separator: String(localized: "metadata.separator"))
    }
}
#endif
