import CryptoKit
import ExpenseCore
import Foundation
import SwiftData

enum AgentImportSettings {
    static let requireReviewKey = "agentEntriesRequireReview"
}

enum AgentImportBridge {
    static let protocolVersion = 1
    static let structuredPipelineVersion = "agent-entry-v1"
    static let manifestFilename = "manifest.json"
    static let inboxDirectoryName = "inbox"
    static let processedDirectoryName = "processed"
    static let failedDirectoryName = "failed"
    static let hashLogFilename = "content-hashes.json"
    static let maxReceiptFileBytes = 50 * 1024 * 1024

    static var supportedReceiptExtensions: Set<String> {
        ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "pdf"]
    }

    static func defaultRootURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appendingPathComponent("AgentImportBridge", isDirectory: true)
    }

    static func isoDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func manifestTimestamp(for date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum AgentImportMode: String, Codable, Sendable {
    case structured
    case raw
}

struct AgentImportTripSuggestion: Codable, Equatable, Sendable {
    var id: String?
    var name: String?
}

struct AgentImportSidecar: Codable, Equatable, Sendable {
    var protocolVersion: Int
    var mode: AgentImportMode
    var suggestedTrip: AgentImportTripSuggestion?
    var note: String?
    var sourceLabel: String?
    var receipt: AgentStructuredReceiptRecord?
}

struct AgentStructuredReceiptRecord: Codable, Equatable, Sendable {
    var merchant: String
    var date: String
    var total: String
    var currency: String
    var expenseType: String
    var paymentMethod: String
    var notes: String?
    var userConfirmed: Bool
}

struct AgentValidatedReceiptRecord: Equatable, Sendable {
    var merchant: String
    var date: Date
    var total: Decimal
    /// Stable category ID (SPEC §D12). May be a folder-visible, legacy, or other known built-in ID.
    var categoryID: String
    /// True when the category is a known built-in that is not visible in the target folder, so the
    /// entry must be drafted for review rather than saved directly (SPEC §D12).
    var categoryNeedsReview: Bool
    var currency: String
    var paymentMethod: PaymentMethod
    var notes: String?
    var userConfirmed: Bool
}

struct AgentPendingReceiptPayload: Codable, Equatable {
    var protocolVersion: Int
    var sourceLabel: String?
    var suggestedTrip: AgentImportTripSuggestion?
    var resolvedTripID: String?
    var resolvedTripName: String?
    var sidecarRawJSON: String
    var record: AgentStructuredReceiptRecord
    var fileName: String
    var contentHash: String
}

enum AgentImportFailureReason: String, Codable, Equatable {
    case unsupportedVersion = "version.unsupported"
    case invalidJSON = "sidecar.invalidJSON"
    case missingReceiptRecord = "record.missing"
    case invalidMode = "mode.invalid"
    case unsupportedFileType = "file.unsupportedType"
    case fileTooLarge = "file.tooLarge"
    case unreadableFile = "file.unreadable"
    case duplicate = "file.duplicate"
    case merchantInvalid = "record.merchant.invalid"
    case dateInvalid = "record.date.invalid"
    case dateOutOfRange = "record.date.outOfRange"
    case totalInvalid = "record.total.invalid"
    case currencyInvalid = "record.currency.invalid"
    case expenseTypeInvalid = "record.expenseType.invalid"
    case paymentMethodInvalid = "record.paymentMethod.invalid"
    case ingestionFailed = "ingestion.failed"
}

struct AgentImportFailure: Codable, Equatable {
    var protocolVersion: Int = AgentImportBridge.protocolVersion
    var reason: AgentImportFailureReason
    var message: String
    var createdAt: String = AgentImportBridge.manifestTimestamp()
}

struct AgentImportDrop: Identifiable, Equatable {
    var id: String
    var receiptFileURL: URL
    var sidecarURL: URL?
}

struct AgentImportRawReview {
    var form: ReceiptReviewForm
    var defaultGroup: ExpenseGroup?
}

struct AgentImportProcessingResult {
    var rawReview: AgentImportRawReview?
}

struct AgentImportManifest: Codable, Equatable {
    var protocolVersion: Int
    var generatedAt: String
    var inboxPath: String
    var processedPath: String
    var failedPath: String
    var trips: [Trip]

    struct Trip: Codable, Equatable {
        var id: String
        var name: String
        var startDate: String?
        var endDate: String?
        var receiptCount: Int
        var currenciesPresent: [String]
        var archived: Bool
        /// Folder profile and visible categories so trusted agents do not have to guess (SPEC §D12).
        var profileID: String
        var visibleCategories: [Category]
    }

    struct Category: Codable, Equatable {
        var id: String
        var name: String
    }
}

struct AgentImportInbox {
    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootURL = try rootURL ?? AgentImportBridge.defaultRootURL(fileManager: fileManager)
    }

    var manifestURL: URL { rootURL.appendingPathComponent(AgentImportBridge.manifestFilename) }
    var inboxURL: URL { rootURL.appendingPathComponent(AgentImportBridge.inboxDirectoryName, isDirectory: true) }
    var processedURL: URL { rootURL.appendingPathComponent(AgentImportBridge.processedDirectoryName, isDirectory: true) }
    var failedURL: URL { rootURL.appendingPathComponent(AgentImportBridge.failedDirectoryName, isDirectory: true) }
    private var hashLogURL: URL { rootURL.appendingPathComponent(AgentImportBridge.hashLogFilename) }

    func ensureDirectories() throws {
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: processedURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: failedURL, withIntermediateDirectories: true)
    }

    func pendingDrops() throws -> [AgentImportDrop] {
        try ensureDirectories()
        return try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
                && url.pathExtension.lowercased() != "json"
        }
        .sorted { lhs, rhs in
            let lhsDate = candidateDate(for: lhs)
            let rhsDate = candidateDate(for: rhs)
            if lhsDate == rhsDate {
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
            return lhsDate < rhsDate
        }
        .map { fileURL in
            let id = fileURL.deletingPathExtension().lastPathComponent
            let sidecar = inboxURL.appendingPathComponent("\(id).json")
            return AgentImportDrop(
                id: id,
                receiptFileURL: fileURL,
                sidecarURL: fileManager.fileExists(atPath: sidecar.path) ? sidecar : nil
            )
        }
    }

    func contentHash(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func hasSeenContentHash(_ hash: String) -> Bool {
        contentHashes().contains(hash)
    }

    func recordContentHash(_ hash: String) throws {
        var hashes = contentHashes()
        hashes.insert(hash)
        let data = try JSONEncoder.prettySorted.encode(Array(hashes).sorted())
        try data.write(to: hashLogURL, options: [.atomic])
    }

    func markProcessed(_ drop: AgentImportDrop) throws {
        try move(drop, to: processedURL, failure: nil)
    }

    func markFailed(_ drop: AgentImportDrop, reason: AgentImportFailureReason, message: String) throws {
        try move(drop, to: failedURL, failure: AgentImportFailure(reason: reason, message: message))
    }

    @MainActor
    func writeManifest(groups: [ExpenseGroup]) throws {
        try ensureDirectories()
        let formatter = AgentImportBridge.isoDateFormatter()
        let manifest = AgentImportManifest(
            protocolVersion: AgentImportBridge.protocolVersion,
            generatedAt: AgentImportBridge.manifestTimestamp(),
            inboxPath: inboxURL.path,
            processedPath: processedURL.path,
            failedPath: failedURL.path,
            trips: groups.sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }.map { group in
                let receipts = group.receipts ?? []
                let visibleReceipts = receipts.filter { $0.isArchived == false }
                return AgentImportManifest.Trip(
                    id: Self.stableID(for: group),
                    name: group.name,
                    startDate: group.startDate.map { formatter.string(from: $0) },
                    endDate: group.endDate.map { formatter.string(from: $0) },
                    receiptCount: visibleReceipts.count,
                    currenciesPresent: Array(Set(visibleReceipts.map { $0.currencyCode.uppercased() })).sorted(),
                    archived: group.isArchived,
                    profileID: group.profileID,
                    visibleCategories: group.visibleCategories.map {
                        AgentImportManifest.Category(id: $0.id, name: $0.displayName)
                    }
                )
            }
        )
        try JSONEncoder.prettySorted.encode(manifest).write(to: manifestURL, options: [.atomic])
    }

    @MainActor
    static func stableID(for group: ExpenseGroup) -> String {
        String(describing: group.persistentModelID)
    }

    private func move(_ drop: AgentImportDrop, to parentURL: URL, failure: AgentImportFailure?) throws {
        try ensureDirectories()
        let destination = parentURL.appendingPathComponent("\(drop.id)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try moveIfPresent(drop.receiptFileURL, to: destination.appendingPathComponent(drop.receiptFileURL.lastPathComponent))
        if let sidecarURL = drop.sidecarURL {
            try moveIfPresent(sidecarURL, to: destination.appendingPathComponent(sidecarURL.lastPathComponent))
        }
        if let failure {
            try JSONEncoder.prettySorted.encode(failure).write(
                to: destination.appendingPathComponent("reason.json"),
                options: [.atomic]
            )
        }
    }

    private func moveIfPresent(_ sourceURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func contentHashes() -> Set<String> {
        guard let data = try? Data(contentsOf: hashLogURL),
              let hashes = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(hashes)
    }

    private func candidateDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }
}

@MainActor
struct AgentImportProcessor {
    var inbox: AgentImportInbox
    var fileProcessor: ReceiptFileIngestionProcessor
    var context: ModelContext

    @discardableResult
    func processPendingDrops(
        groups: [ExpenseGroup],
        requiresReview: Bool,
        defaultCurrencyCode: String,
        defaultPaymentMethod: PaymentMethod
    ) async -> AgentImportProcessingResult {
        let drops = (try? inbox.pendingDrops()) ?? []
        for drop in drops {
            if let rawReview = await process(
                drop,
                groups: groups,
                requiresReview: requiresReview,
                defaultCurrencyCode: defaultCurrencyCode,
                defaultPaymentMethod: defaultPaymentMethod
            ) {
                return AgentImportProcessingResult(rawReview: rawReview)
            }
        }
        return AgentImportProcessingResult()
    }

    private func process(
        _ drop: AgentImportDrop,
        groups: [ExpenseGroup],
        requiresReview: Bool,
        defaultCurrencyCode: String,
        defaultPaymentMethod: PaymentMethod
    ) async -> AgentImportRawReview? {
        do {
            guard AgentImportBridge.supportedReceiptExtensions.contains(drop.receiptFileURL.pathExtension.lowercased()) else {
                try inbox.markFailed(drop, reason: .unsupportedFileType, message: "Unsupported receipt file type.")
                return nil
            }

            let resourceValues = try drop.receiptFileURL.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize,
               fileSize > AgentImportBridge.maxReceiptFileBytes {
                try inbox.markFailed(drop, reason: .fileTooLarge, message: "Receipt file exceeds the bridge file-size limit.")
                return nil
            }

            let contentHash = try inbox.contentHash(for: drop.receiptFileURL)
            guard inbox.hasSeenContentHash(contentHash) == false else {
                try inbox.markFailed(drop, reason: .duplicate, message: "This receipt file content was already ingested.")
                return nil
            }

            var rawReview: AgentImportRawReview?
            guard let sidecarURL = drop.sidecarURL else {
                let form = try await fileProcessor.process(
                    fileURLs: [drop.receiptFileURL],
                    defaultCurrencyCode: defaultCurrencyCode,
                    defaultPaymentMethod: defaultPaymentMethod
                )
                rawReview = AgentImportRawReview(form: form, defaultGroup: nil)
                try inbox.recordContentHash(contentHash)
                try inbox.markProcessed(drop)
                return rawReview
            }

            let sidecarData = try Data(contentsOf: sidecarURL)
            let sidecarRawJSON = String(data: sidecarData, encoding: .utf8) ?? ""
            let sidecar: AgentImportSidecar
            do {
                sidecar = try JSONDecoder.agentImport.decode(AgentImportSidecar.self, from: sidecarData)
            } catch {
                try inbox.markFailed(drop, reason: .invalidJSON, message: "Sidecar JSON did not match the agent import schema.")
                return nil
            }

            guard sidecar.protocolVersion <= AgentImportBridge.protocolVersion else {
                try inbox.markFailed(drop, reason: .unsupportedVersion, message: "Sidecar protocol version is newer than this app supports.")
                return nil
            }

            switch sidecar.mode {
            case .raw:
                let group = resolveGroup(suggestion: sidecar.suggestedTrip, groups: groups)
                let form = try await fileProcessor.process(
                    fileURLs: [drop.receiptFileURL],
                    defaultCurrencyCode: defaultCurrencyCode,
                    defaultPaymentMethod: defaultPaymentMethod
                )
                rawReview = AgentImportRawReview(form: form, defaultGroup: group)
            case .structured:
                let group = resolveGroup(suggestion: sidecar.suggestedTrip, groups: groups)
                let visibleCategoryIDs = group.map { Set($0.visibleCategoryIDs) }
                let record = try AgentImportRecordValidator.validate(sidecar.receipt, visibleCategoryIDs: visibleCategoryIDs)
                let pages = try await fileProcessor.capturedPages(fromFileURLs: [drop.receiptFileURL])
                let payload = AgentPendingReceiptPayload(
                    protocolVersion: AgentImportBridge.protocolVersion,
                    sourceLabel: sidecar.sourceLabel,
                    suggestedTrip: sidecar.suggestedTrip,
                    resolvedTripID: group.map { AgentImportInbox.stableID(for: $0) },
                    resolvedTripName: group?.name,
                    sidecarRawJSON: sidecarRawJSON,
                    record: sidecar.receipt!,
                    fileName: drop.receiptFileURL.lastPathComponent,
                    contentHash: contentHash
                )

                // A hidden-but-known category is ingested as a draft needing review (SPEC §D12).
                if record.userConfirmed && requiresReview == false && record.categoryNeedsReview == false {
                    try materializeConfirmedReceipt(record: record, pages: pages, sidecarRawJSON: sidecarRawJSON, group: group)
                } else {
                    try materializePendingDraft(payload: payload, pages: pages)
                }
            }

            try inbox.recordContentHash(contentHash)
            try inbox.markProcessed(drop)
            return rawReview
        } catch let error as AgentImportValidationError {
            try? inbox.markFailed(drop, reason: error.reason, message: error.message)
            return nil
        } catch {
            try? inbox.markFailed(drop, reason: .ingestionFailed, message: String(describing: error))
            return nil
        }
    }

    private func materializeConfirmedReceipt(
        record: AgentValidatedReceiptRecord,
        pages: [CapturedReceiptPage],
        sidecarRawJSON: String,
        group: ExpenseGroup?
    ) throws {
        let receipt = Receipt(
            vendor: record.merchant,
            date: record.date,
            totalAmount: record.total,
            currencyCode: record.currency,
            paymentMethod: record.paymentMethod,
            notes: record.notes,
            group: group
        )
        receipt.categoryID = record.categoryID
        let attachments = pages.sorted { $0.pageIndex < $1.pageIndex }.map { page in
            ReceiptAttachment(
                imageData: page.imageData,
                thumbnailData: page.thumbnailData,
                pageIndex: page.pageIndex,
                sourceType: .fileImport,
                receipt: receipt
            )
        }
        let extraction = ExtractionRecord(
            rawOCRText: sidecarRawJSON,
            modelOutputJSON: sidecarRawJSON,
            pipelineVersion: AgentImportBridge.structuredPipelineVersion,
            receipt: receipt
        )
        receipt.attachments = attachments
        receipt.extraction = extraction
        context.insert(receipt)
        attachments.forEach { context.insert($0) }
        context.insert(extraction)
        if let group {
            var receipts = group.receipts ?? []
            receipts.append(receipt)
            group.receipts = receipts
        }
        try context.save()
    }

    private func materializePendingDraft(payload: AgentPendingReceiptPayload, pages: [CapturedReceiptPage]) throws {
        let draftPages = pages.sorted { $0.pageIndex < $1.pageIndex }.map { page in
            ReceiptDraftPage(
                imageData: page.imageData,
                thumbnailData: page.thumbnailData,
                pageIndex: page.pageIndex,
                sourceType: .fileImport
            )
        }
        let draft = ReceiptDraft(
            rawOCRText: try String(decoding: JSONEncoder.prettySorted.encode(payload), as: UTF8.self),
            modelOutputJSON: payload.sidecarRawJSON,
            pipelineVersion: AgentImportBridge.structuredPipelineVersion,
            pages: draftPages
        )
        draftPages.forEach { page in
            page.draft = draft
            context.insert(page)
        }
        context.insert(draft)
        try context.save()
    }

    private func resolveGroup(suggestion: AgentImportTripSuggestion?, groups: [ExpenseGroup]) -> ExpenseGroup? {
        guard let suggestion else { return nil }
        let activeGroups = groups.filter { $0.isArchived == false }
        if let id = suggestion.id?.trimmingCharacters(in: .whitespacesAndNewlines), id.isEmpty == false,
           let match = activeGroups.first(where: { AgentImportInbox.stableID(for: $0) == id }) {
            return match
        }
        if let name = suggestion.name?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false,
           let match = activeGroups.first(where: { $0.name == name }) {
            return match
        }
        return nil
    }
}

enum AgentImportRecordValidator {
    /// Validates a structured sidecar against the target folder's category context (SPEC §D12).
    /// - Category IDs visible in the folder, and legacy/known built-in IDs, are accepted.
    /// - A known built-in ID that is not visible in the folder is accepted but flagged for review.
    /// - Unknown IDs are rejected. When `visibleCategoryIDs` is nil (no folder context), only
    ///   built-in IDs are accepted and nothing is flagged for review.
    static func validate(
        _ record: AgentStructuredReceiptRecord?,
        visibleCategoryIDs: Set<String>? = nil
    ) throws -> AgentValidatedReceiptRecord {
        guard let record else {
            throw AgentImportValidationError(.missingReceiptRecord, "Structured sidecar is missing receipt record.")
        }

        let merchant = record.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard merchant.isEmpty == false, merchant.count <= 160 else {
            throw AgentImportValidationError(.merchantInvalid, "Merchant is required and must be 160 characters or fewer.")
        }

        guard let date = AgentImportBridge.isoDateFormatter().date(from: record.date) else {
            throw AgentImportValidationError(.dateInvalid, "Date must use yyyy-MM-dd ISO format.")
        }
        guard isSaneReceiptDate(date) else {
            throw AgentImportValidationError(.dateOutOfRange, "Date is outside the supported receipt range.")
        }

        guard isCanonicalDecimalString(record.total),
              let total = Decimal(string: record.total, locale: Locale(identifier: "en_US_POSIX")),
              total >= Decimal.zero else {
            throw AgentImportValidationError(.totalInvalid, "Total must be a non-negative string decimal using a dot separator.")
        }

        guard let currency = CurrencyCatalog.normalizedISOCode(record.currency) else {
            throw AgentImportValidationError(.currencyInvalid, "Currency must be a known ISO 4217 code.")
        }

        let categoryID = record.expenseType.trimmingCharacters(in: .whitespacesAndNewlines)
        let isVisible = visibleCategoryIDs?.contains(categoryID) ?? false
        let isKnown = isVisible || CategoryCatalog.isBuiltIn(categoryID)
        guard isKnown else {
            throw AgentImportValidationError(.expenseTypeInvalid, "Category ID is not recognized for this folder.")
        }
        let categoryNeedsReview = (visibleCategoryIDs != nil) && isVisible == false

        guard let paymentMethod = PaymentMethod(rawValue: record.paymentMethod) else {
            throw AgentImportValidationError(.paymentMethodInvalid, "Payment method is not recognized.")
        }

        return AgentValidatedReceiptRecord(
            merchant: merchant,
            date: date,
            total: total,
            categoryID: categoryID,
            categoryNeedsReview: categoryNeedsReview,
            currency: currency,
            paymentMethod: paymentMethod,
            notes: record.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            userConfirmed: record.userConfirmed
        )
    }

    private static func isCanonicalDecimalString(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.isEmpty == false else { return false }
        var dotCount = 0
        for scalar in scalars {
            if scalar == "." {
                dotCount += 1
                if dotCount > 1 { return false }
            } else if CharacterSet.decimalDigits.contains(scalar) == false {
                return false
            }
        }
        return value.first != "." && value.last != "."
    }

    private static func isSaneReceiptDate(_ date: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)
        let earliest = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let latest = calendar.startOfDay(for: Date()).addingTimeInterval(2 * 24 * 60 * 60)
        return startOfDay >= earliest && startOfDay <= latest
    }
}

struct AgentPendingEntry: Identifiable {
    var draft: ReceiptDraft
    var payload: AgentPendingReceiptPayload

    var id: PersistentIdentifier { draft.persistentModelID }

    static func entries(from drafts: [ReceiptDraft]) -> [AgentPendingEntry] {
        drafts.compactMap { draft in
            guard draft.pipelineVersion == AgentImportBridge.structuredPipelineVersion,
                  let data = draft.rawOCRText.data(using: .utf8),
                  let payload = try? JSONDecoder.agentImport.decode(AgentPendingReceiptPayload.self, from: data) else {
                return nil
            }
            return AgentPendingEntry(draft: draft, payload: payload)
        }
        .sorted { lhs, rhs in
            if lhs.draft.createdAt == rhs.draft.createdAt {
                return lhs.payload.fileName < rhs.payload.fileName
            }
            return lhs.draft.createdAt > rhs.draft.createdAt
        }
    }

    @MainActor
    func resolvedGroup(in groups: [ExpenseGroup]) -> ExpenseGroup? {
        guard let resolvedTripID = payload.resolvedTripID else { return nil }
        return groups.first { AgentImportInbox.stableID(for: $0) == resolvedTripID && $0.isArchived == false }
    }

    @MainActor
    func makeReviewForm(
        defaultCurrencyCode: String,
        defaultPaymentMethod: PaymentMethod,
        visibleCategoryIDs: Set<String>? = nil
    ) -> ReceiptReviewForm? {
        guard let record = try? AgentImportRecordValidator.validate(payload.record, visibleCategoryIDs: visibleCategoryIDs) else {
            return nil
        }
        return ReceiptReviewForm(
            draft: draft,
            mergedReceipt: MergedReceipt.agentEntry(record: record, rawText: payload.sidecarRawJSON),
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod,
            initialCategoryID: record.categoryID
        )
    }
}

struct AgentImportValidationError: Error {
    var reason: AgentImportFailureReason
    var message: String

    init(_ reason: AgentImportFailureReason, _ message: String) {
        self.reason = reason
        self.message = message
    }
}

extension MergedReceipt {
    static func agentEntry(record: AgentValidatedReceiptRecord, rawText: String) -> MergedReceipt {
        // The legacy expenseType field only carries the category when it maps to one of the five
        // legacy types; the actual category ID is seeded separately via `initialCategoryID`.
        let expenseTypeField: MergedField<ExpenseType>
        if let legacyType = ExpenseType(rawValue: record.categoryID) {
            expenseTypeField = MergedField(options: [MergedFieldOption(value: legacyType, source: .deterministic, reason: "agent-entry")])
        } else {
            expenseTypeField = MergedField()
        }
        return MergedReceipt(
            vendor: MergedField(options: [MergedFieldOption(value: record.merchant, source: .deterministic, reason: "agent-entry")]),
            date: MergedField(options: [MergedFieldOption(value: record.date, source: .deterministic, reason: "agent-entry")]),
            totalAmount: MergedField(options: [MergedFieldOption(value: record.total, source: .deterministic, reason: "agent-entry")]),
            currencyCode: MergedField(options: [MergedFieldOption(value: record.currency, source: .deterministic, reason: "agent-entry")]),
            paymentMethod: MergedField(options: [MergedFieldOption(value: record.paymentMethod, source: .deterministic, reason: "agent-entry")]),
            expenseType: expenseTypeField,
            rawText: rawText
        )
    }
}

extension ReceiptDraft {
    var isAgentStructuredDraft: Bool {
        pipelineVersion == AgentImportBridge.structuredPipelineVersion
    }
}

extension ExtractionRecord {
    var isAgentEntry: Bool {
        pipelineVersion == AgentImportBridge.structuredPipelineVersion
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var agentImport: JSONDecoder {
        JSONDecoder()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
