import ExpenseCore
import Foundation
import SwiftData

enum ReceiptAttachmentSourceType: String, CaseIterable, Codable, Sendable {
    case cameraScan
    case photoImport
    case fileImport
}

@Model
final class ReceiptDraft {
    var rawOCRText: String = ""
    var modelOutputJSON: String?
    var ocrConfidence: Double?
    var pipelineVersion: String = "v1"
    var createdAt: Date = Date()
    var lastUpdatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ReceiptDraftPage.draft)
    var pages: [ReceiptDraftPage]?

    init(
        rawOCRText: String = "",
        modelOutputJSON: String? = nil,
        ocrConfidence: Double? = nil,
        pipelineVersion: String = "v1",
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        pages: [ReceiptDraftPage]? = []
    ) {
        self.rawOCRText = rawOCRText
        self.modelOutputJSON = modelOutputJSON
        self.ocrConfidence = ocrConfidence
        self.pipelineVersion = pipelineVersion
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.pages = pages
    }
}

@Model
final class ReceiptDraftPage {
    @Attribute(.externalStorage)
    var imageData: Data = Data()

    @Attribute(.externalStorage)
    var thumbnailData: Data?

    var pageIndex: Int = 0
    var sourceTypeRawValue: String = ReceiptAttachmentSourceType.cameraScan.rawValue
    var createdAt: Date = Date()

    var draft: ReceiptDraft?

    init(
        imageData: Data = Data(),
        thumbnailData: Data? = nil,
        pageIndex: Int = 0,
        sourceType: ReceiptAttachmentSourceType = .cameraScan,
        createdAt: Date = Date(),
        draft: ReceiptDraft? = nil
    ) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.pageIndex = pageIndex
        self.sourceTypeRawValue = sourceType.rawValue
        self.createdAt = createdAt
        self.draft = draft
    }
}

extension ReceiptDraftPage {
    var sourceType: ReceiptAttachmentSourceType {
        get { ReceiptAttachmentSourceType(rawValue: sourceTypeRawValue) ?? .cameraScan }
        set { sourceTypeRawValue = newValue.rawValue }
    }
}

@Model
final class ExpenseGroup {
    var name: String = ""
    var startDate: Date?
    var endDate: Date?
    var notes: String?
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var archivedAt: Date?
    var pinnedAt: Date?

    /// Stable folder-profile identifier (e.g. `workTrip`, `conference`). Existing folders default to
    /// Work Trip so pre-profile data migrates with no user action (SPEC §D2, §6, §11.1).
    var profileIDRawValue: String = FolderProfileCatalog.workTripID

    /// CloudKit-safe JSON encoding of the folder's ordered visible-category snapshot (SPEC §6). Empty
    /// for pre-profile folders, which lazily resolve to their profile's default set.
    var categorySnapshotJSON: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Receipt.group)
    var receipts: [Receipt]?

    init(
        name: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        pinnedAt: Date? = nil,
        profileID: String = FolderProfileCatalog.workTripID,
        categorySnapshotJSON: String = "",
        receipts: [Receipt]? = []
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.pinnedAt = pinnedAt
        self.profileIDRawValue = profileID
        self.categorySnapshotJSON = categorySnapshotJSON
        self.receipts = receipts
    }
}

extension ExpenseGroup {
    var profileID: String {
        get { profileIDRawValue }
        set { profileIDRawValue = newValue }
    }

    var profile: FolderProfile {
        FolderProfileCatalog.profile(id: profileIDRawValue) ?? FolderProfileCatalog.workTrip
    }

    /// The folder's ordered visible-category snapshot. Pre-profile folders (empty JSON) resolve to
    /// their profile's default set on read; writing re-encodes the JSON.
    var categorySnapshot: FolderCategorySnapshot {
        get {
            FolderCategorySnapshot(jsonString: categorySnapshotJSON)
                ?? FolderProfileCatalog.defaultSnapshot(forProfileID: profileIDRawValue)
        }
        set {
            categorySnapshotJSON = newValue.jsonString()
        }
    }

    var visibleCategories: [FolderCategory] {
        categorySnapshot.categories
    }

    var visibleCategoryIDs: [String] {
        categorySnapshot.categoryIDs
    }
}

@Model
final class Receipt {
    var vendor: String = ""
    var date: Date = Date()
    var totalAmount: Decimal = Decimal.zero
    var currencyCode: String = "USD"
    var expenseTypeRawValue: String = ExpenseType.other.rawValue
    var paymentMethodRawValue: String = PaymentMethod.card.rawValue
    var notes: String?
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var archivedAt: Date?

    var group: ExpenseGroup?

    @Relationship(deleteRule: .cascade, inverse: \ReceiptAttachment.receipt)
    var attachments: [ReceiptAttachment]?

    @Relationship(deleteRule: .cascade, inverse: \ExtractionRecord.receipt)
    var extraction: ExtractionRecord?

    init(
        vendor: String = "",
        date: Date = Date(),
        totalAmount: Decimal = Decimal.zero,
        currencyCode: String = "USD",
        expenseType: ExpenseType = .other,
        paymentMethod: PaymentMethod = .card,
        notes: String? = nil,
        createdAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        group: ExpenseGroup? = nil,
        attachments: [ReceiptAttachment]? = [],
        extraction: ExtractionRecord? = nil
    ) {
        self.vendor = vendor
        self.date = date
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode.uppercased()
        self.expenseTypeRawValue = expenseType.rawValue
        self.paymentMethodRawValue = paymentMethod.rawValue
        self.notes = notes
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.group = group
        self.attachments = attachments
        self.extraction = extraction
    }
}

extension Receipt {
    var isEffectivelyArchived: Bool {
        isArchived || group?.isArchived == true
    }

    /// The user-visible concept is now Category. The persisted field name stays
    /// `expenseTypeRawValue` for migration safety (SPEC §6); the value is a stable category ID.
    var categoryID: String {
        get { expenseTypeRawValue }
        set { expenseTypeRawValue = newValue }
    }

    /// Legacy five-case view of the stored category, falling back to `.other` for any category ID
    /// outside the legacy set. Kept only for compatibility paths.
    var expenseType: ExpenseType {
        get { ExpenseType(rawValue: expenseTypeRawValue) ?? .other }
        set { expenseTypeRawValue = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRawValue) ?? .card }
        set { paymentMethodRawValue = newValue.rawValue }
    }

    var expenseSummary: ExpenseSummary {
        ExpenseSummary(
            amount: totalAmount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            paymentMethod: paymentMethod
        )
    }

    /// Resolves display metadata for this receipt's category, preferring the owning folder's
    /// self-contained snapshot, then the built-in catalog, then a neutral fallback.
    var resolvedCategory: FolderCategory {
        CategoryResolver.category(forID: categoryID, in: group?.categorySnapshot)
    }
}

@Model
final class ReceiptAttachment {
    @Attribute(.externalStorage)
    var imageData: Data = Data()

    @Attribute(.externalStorage)
    var thumbnailData: Data?

    var pageIndex: Int = 0
    var capturedAt: Date = Date()
    var sourceTypeRawValue: String = ReceiptAttachmentSourceType.cameraScan.rawValue

    var receipt: Receipt?

    init(
        imageData: Data = Data(),
        thumbnailData: Data? = nil,
        pageIndex: Int = 0,
        capturedAt: Date = Date(),
        sourceType: ReceiptAttachmentSourceType = .cameraScan,
        receipt: Receipt? = nil
    ) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.pageIndex = pageIndex
        self.capturedAt = capturedAt
        self.sourceTypeRawValue = sourceType.rawValue
        self.receipt = receipt
    }
}

extension ReceiptAttachment {
    var sourceType: ReceiptAttachmentSourceType {
        get { ReceiptAttachmentSourceType(rawValue: sourceTypeRawValue) ?? .cameraScan }
        set { sourceTypeRawValue = newValue.rawValue }
    }
}

@Model
final class ExtractionRecord {
    var rawOCRText: String = ""
    var modelOutputJSON: String?
    var ocrConfidence: Double?
    var pipelineVersion: String = "v1"
    var extractedAt: Date = Date()
    var userCorrectedFields: [String]?

    var receipt: Receipt?

    init(
        rawOCRText: String = "",
        modelOutputJSON: String? = nil,
        ocrConfidence: Double? = nil,
        pipelineVersion: String = "v1",
        extractedAt: Date = Date(),
        userCorrectedFields: [String]? = nil,
        receipt: Receipt? = nil
    ) {
        self.rawOCRText = rawOCRText
        self.modelOutputJSON = modelOutputJSON
        self.ocrConfidence = ocrConfidence
        self.pipelineVersion = pipelineVersion
        self.extractedAt = extractedAt
        self.userCorrectedFields = userCorrectedFields
        self.receipt = receipt
    }
}
