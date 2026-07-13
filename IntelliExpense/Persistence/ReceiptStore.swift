import ExpenseCore
import Foundation
import SwiftData

enum ExpenseGroupReceiptDeletionPolicy {
    case keepReceiptsUnfiled
    case deleteReceipts
}

enum ReceiptStore {
    private static let draftExpirationSeconds: TimeInterval = 48 * 60 * 60

    @MainActor
    static func delete(
        group: ExpenseGroup,
        receiptPolicy: ExpenseGroupReceiptDeletionPolicy,
        in context: ModelContext
    ) {
        let receipts = group.receipts ?? []

        switch receiptPolicy {
        case .keepReceiptsUnfiled:
            receipts.forEach { $0.group = nil }
            group.receipts = []
        case .deleteReceipts:
            receipts.forEach { context.delete($0) }
        }

        context.delete(group)
    }

    @MainActor
    static func archive(_ receipt: Receipt, in context: ModelContext) throws {
        receipt.isArchived = true
        receipt.archivedAt = Date()
        try context.save()
    }

    @MainActor
    static func restore(_ receipt: Receipt, in context: ModelContext) throws {
        receipt.isArchived = false
        receipt.archivedAt = nil
        try context.save()
    }

    @MainActor
    static func archive(_ group: ExpenseGroup, in context: ModelContext) throws {
        group.isArchived = true
        group.archivedAt = Date()
        group.pinnedAt = nil
        try context.save()
    }

    @MainActor
    static func restore(_ group: ExpenseGroup, in context: ModelContext) throws {
        group.isArchived = false
        group.archivedAt = nil
        try context.save()
    }

    @MainActor
    static func pin(_ group: ExpenseGroup, at date: Date = Date(), in context: ModelContext) throws {
        group.pinnedAt = date
        try context.save()
    }

    @MainActor
    static func unpin(_ group: ExpenseGroup, in context: ModelContext) throws {
        group.pinnedAt = nil
        try context.save()
    }

    @MainActor
    static func sweepExpiredDrafts(
        in context: ModelContext,
        now: Date = Date(),
        expirationSeconds: TimeInterval = draftExpirationSeconds
    ) throws {
        let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
        let cutoff = now.addingTimeInterval(-expirationSeconds)
        for draft in drafts {
            let lastActivity = max(draft.createdAt, draft.lastUpdatedAt)
            if lastActivity < cutoff {
                context.delete(draft)
            }
        }
        try context.save()
    }
}

extension ExpenseGroup {
    var activeReceipts: [Receipt] {
        (receipts ?? []).filter { $0.isArchived == false }
    }

    var mostRecentActivityDate: Date {
        let newestReceiptDate = activeReceipts.map(\.date).max()
        return max(createdAt, newestReceiptDate ?? createdAt)
    }

    static func sortedByMostRecentActivity(_ groups: [ExpenseGroup]) -> [ExpenseGroup] {
        groups.filter { $0.isArchived == false }.sorted(by: isMoreRecentlyActive)
    }

    static func sortedPinnedFirst(_ groups: [ExpenseGroup]) -> [ExpenseGroup] {
        groups.filter { $0.isArchived == false }.sorted { lhs, rhs in
            switch (lhs.pinnedAt, rhs.pinnedAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return isMoreRecentlyActive(lhs, rhs)
            }
        }
    }

    static func sortedByMostRecentArchive(_ groups: [ExpenseGroup]) -> [ExpenseGroup] {
        groups.filter(\.isArchived).sorted { lhs, rhs in
            switch (lhs.archivedAt, rhs.archivedAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private static func isMoreRecentlyActive(_ lhs: ExpenseGroup, _ rhs: ExpenseGroup) -> Bool {
        if lhs.mostRecentActivityDate != rhs.mostRecentActivityDate {
            return lhs.mostRecentActivityDate > rhs.mostRecentActivityDate
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

struct ExpenseGroupSummary: Equatable {
    var totals: [CurrencyTotal]
    /// Breakdown keyed by stable category ID (SPEC §6/§D7).
    var breakdown: [String: CategoryBreakdown]

    static func make(for group: ExpenseGroup) -> ExpenseGroupSummary {
        let summaries = group.activeReceipts.map(\.expenseSummary)
        return ExpenseGroupSummary(
            totals: TotalsCalculator.totalsByCurrency(summaries),
            breakdown: TotalsCalculator.breakdownByCategoryID(summaries)
        )
    }
}
