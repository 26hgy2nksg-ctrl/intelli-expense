import ExpenseCore
import SwiftData
import SwiftUI

struct AgentEntryConfirmationSection: View {
    var entries: [AgentPendingEntry]
    var groups: [ExpenseGroup]
    var onConfirm: (AgentPendingEntry) -> Void
    var onReview: (AgentPendingEntry) -> Void

    var body: some View {
        if entries.isEmpty == false {
            Section {
                ForEach(entries) { entry in
                    let group = entry.resolvedGroup(in: groups)
                    AgentEntryConfirmationCard(
                        entry: entry,
                        groupName: group?.name ?? String(localized: "groups.unfiled.title"),
                        visibleCategoryIDs: group.map { Set($0.visibleCategoryIDs) },
                        categorySnapshot: group?.categorySnapshot,
                        onConfirm: { onConfirm(entry) },
                        onReview: { onReview(entry) }
                    )
                }
            } header: {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "agent.entries.section.title"),
                        entries.count
                    )
                )
            }
        }
    }
}

private struct AgentEntryConfirmationCard: View {
    var entry: AgentPendingEntry
    var groupName: String
    var visibleCategoryIDs: Set<String>?
    var categorySnapshot: FolderCategorySnapshot?
    var onConfirm: () -> Void
    var onReview: () -> Void

    private var record: AgentValidatedReceiptRecord? {
        try? AgentImportRecordValidator.validate(entry.payload.record, visibleCategoryIDs: visibleCategoryIDs)
    }

    private var displayCategory: FolderCategory {
        CategoryResolver.category(
            forID: entry.payload.record.expenseType.trimmingCharacters(in: .whitespacesAndNewlines),
            in: categorySnapshot
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onReview) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record?.merchant ?? entry.payload.record.merchant)
                            .contentScaledFont(.body.weight(.semibold))
                            .lineLimit(2)
                        Text(metaLine)
                            .contentScaledFont(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(groupName)
                            .contentScaledFont(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text(amountText)
                        .contentScaledFont(.headline.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("receipt.provenance.agentEntry")
                .contentScaledFont(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("agent.entries.confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("LedgerGreen"))
                    .controlSize(.small)
                    .accessibilityIdentifier("agent.entry.confirm")
                Button("agent.entries.reviewDetails", action: onReview)
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .accessibilityIdentifier("agent.entry.review")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = entry.thumbnailData,
           let image = ReceiptPlatformImage.receiptImage(data: data) {
            Image(receiptImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.receiptSeparator, lineWidth: 0.5)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: displayCategory.symbolName)
                .imageScale(.medium)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(displayCategory.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var amountText: String {
        guard let record else {
            return entry.payload.record.total
        }
        return ExpenseFormatters.money(record.total, currencyCode: record.currency)
    }

    private var metaLine: String {
        guard let record else {
            return entry.payload.record.date
        }
        return [
            ExpenseFormatters.date(record.date),
            displayCategory.displayName,
            ExpenseFormatters.paymentName(record.paymentMethod)
        ].joined(separator: String(localized: "metadata.separator"))
    }
}

extension AgentPendingEntry {
    var thumbnailData: Data? {
        let sortedPages = (draft.pages ?? []).sorted { $0.pageIndex < $1.pageIndex }
        return sortedPages.first?.thumbnailData ?? sortedPages.first?.imageData
    }
}
