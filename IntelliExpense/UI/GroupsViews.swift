import ExpenseCore
import SwiftData
import SwiftUI

struct GroupsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(DefaultCurrencySettings.defaultCodeKey) private var defaultCurrencyCode = DefaultCurrencySettings.fallbackCode
    @AppStorage("defaultPaymentMethod") private var defaultPaymentMethodRawValue = PaymentMethod.card.rawValue
    @Query(sort: \ExpenseGroup.createdAt, order: .reverse) private var groups: [ExpenseGroup]
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \ReceiptDraft.createdAt, order: .reverse) private var drafts: [ReceiptDraft]

    var onAdd: () -> Void
    var onCaptureForGroup: (ExpenseGroup) -> Void
    var onAttachPhoto: (Receipt) -> Void
    var onViewingGroupChange: (ExpenseGroup?) -> Void = { _ in }
    @State private var isShowingCreateGroup = false
    @State private var agentReviewForm: ReceiptReviewForm?
    @State private var agentReviewDefaultGroup: ExpenseGroup?

    var body: some View {
        NavigationStack {
            List {
                if sortedGroups.isEmpty && unfiledReceipts.isEmpty && archivedGroups.isEmpty && pendingAgentEntries.isEmpty {
                    AppEmptyStateView(
                        "groups.empty.title",
                        systemImage: "folder",
                        message: "groups.empty.message"
                    ) {
                        Button("groups.create") { isShowingCreateGroup = true }
                    }
                } else {
                    AgentEntryConfirmationSection(
                        entries: pendingAgentEntries,
                        groups: groups,
                        onConfirm: confirmAgentEntry,
                        onReview: reviewAgentEntry
                    )

                    if featuredGroup != nil {
                        Section {
                            ForEach(featuredGroups) { group in
                                NavigationLink {
                                    GroupDetailView(
                                        group: group,
                                        onCapture: { onCaptureForGroup(group) },
                                        onAttachPhoto: onAttachPhoto,
                                        onViewingGroupChange: onViewingGroupChange
                                    )
                                } label: {
                                    FeaturedTripCard(group: group)
                                }
                                .accessibilityIdentifier("groups.featured.card")
                                .contextMenu {
                                    pinButton(for: group)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    archiveButton(for: group)
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(compactGroups) { group in
                            NavigationLink {
                                GroupDetailView(
                                    group: group,
                                    onCapture: { onCaptureForGroup(group) },
                                    onAttachPhoto: onAttachPhoto,
                                    onViewingGroupChange: onViewingGroupChange
                                )
                            } label: {
                                GroupRow(group: group)
                            }
                            .contextMenu {
                                pinButton(for: group)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                archiveButton(for: group)
                            }
                        }
                        Button {
                            isShowingCreateGroup = true
                        } label: {
                            Label("groups.create.row", systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("groups.create.row")
                    }

                    if unfiledReceipts.isEmpty == false {
                        Section("groups.unfiled.section") {
                            NavigationLink {
                                UnfiledReceiptsView(receipts: unfiledReceipts, onAttachPhoto: onAttachPhoto)
                            } label: {
                                HStack {
                                    Label("groups.unfiled.title", systemImage: "tray")
                                    Spacer()
                                    Text("\(unfiledReceipts.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("groups.unfiled.link")
                        }
                    }

                    if archivedGroups.isEmpty == false {
                        Section {
                            NavigationLink {
                                ArchivedTripsView(
                                    onAttachPhoto: onAttachPhoto,
                                    onViewingGroupChange: onViewingGroupChange
                                )
                            } label: {
                                HStack {
                                    Label("trips.archived.title", systemImage: "archivebox")
                                    Spacer()
                                    Text(
                                        String.localizedStringWithFormat(
                                            String(localized: "trips.archived.row"),
                                            archivedGroups.count
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("trips.archived.link")
                        }
                    }
                }
            }
            .navigationTitle("tab.groups")
            .animation(
                accessibilityReduceMotion ? nil : .easeInOut(duration: 0.22),
                value: sortedGroupIDs
            )
            .sheet(isPresented: $isShowingCreateGroup) {
                GroupEditorSheet()
            }
            .sheet(item: $agentReviewForm) { form in
                NavigationStack {
                    ReceiptReviewView(
                        form: form,
                        defaultGroup: agentReviewDefaultGroup,
                        onSaved: {
                            agentReviewForm = nil
                            agentReviewDefaultGroup = nil
                        }
                    )
                }
            }
        }
    }

    private var sortedGroups: [ExpenseGroup] {
        ExpenseGroup.sortedPinnedFirst(groups)
    }

    private var featuredGroup: ExpenseGroup? {
        sortedGroups.first
    }

    private var featuredGroups: [ExpenseGroup] {
        featuredGroup.map { [$0] } ?? []
    }

    private var compactGroups: [ExpenseGroup] {
        Array(sortedGroups.dropFirst())
    }

    private var archivedGroups: [ExpenseGroup] {
        ExpenseGroup.sortedByMostRecentArchive(groups)
    }

    private var pendingAgentEntries: [AgentPendingEntry] {
        AgentPendingEntry.entries(from: drafts)
    }

    private var defaultPaymentMethod: PaymentMethod {
        PaymentMethod(rawValue: defaultPaymentMethodRawValue) ?? .card
    }

    private var sortedGroupIDs: [String] {
        (sortedGroups + archivedGroups).map { String(describing: $0.persistentModelID) }
    }

    private var unfiledReceipts: [Receipt] {
        receipts.filter { $0.group == nil && $0.isEffectivelyArchived == false }
    }

    private func archive(group: ExpenseGroup) {
        try? ReceiptStore.archive(group, in: modelContext)
    }

    private func confirmAgentEntry(_ entry: AgentPendingEntry) {
        let group = entry.resolvedGroup(in: groups)
        guard let form = entry.makeReviewForm(
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod,
            visibleCategoryIDs: group.map { Set($0.visibleCategoryIDs) }
        ) else { return }
        _ = try? form.save(in: modelContext, group: group)
    }

    private func reviewAgentEntry(_ entry: AgentPendingEntry) {
        let group = entry.resolvedGroup(in: groups)
        guard let form = entry.makeReviewForm(
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod,
            visibleCategoryIDs: group.map { Set($0.visibleCategoryIDs) }
        ) else { return }
        agentReviewDefaultGroup = group
        agentReviewForm = form
    }

    private func archiveButton(for group: ExpenseGroup) -> some View {
        Button {
            archive(group: group)
        } label: {
            Label("trip.archive", systemImage: "archivebox")
        }
        .tint(Color("LedgerGreen"))
        .accessibilityIdentifier("trip.action.archive")
    }

    @ViewBuilder
    private func pinButton(for group: ExpenseGroup) -> some View {
        if group.pinnedAt == nil {
            Button {
                try? ReceiptStore.pin(group, in: modelContext)
            } label: {
                Label("folder.pin", systemImage: "pin")
            }
            .accessibilityIdentifier("folder.action.pin")
        } else {
            Button {
                try? ReceiptStore.unpin(group, in: modelContext)
            } label: {
                Label("folder.unpin", systemImage: "pin.slash")
            }
            .accessibilityIdentifier("folder.action.unpin")
        }
    }
}

private struct ArchivedTripsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseGroup.createdAt, order: .reverse) private var groups: [ExpenseGroup]
    var onAttachPhoto: (Receipt) -> Void
    var onViewingGroupChange: (ExpenseGroup?) -> Void

    @State private var pendingDeletionGroup: ExpenseGroup?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        List {
            if archivedGroups.isEmpty {
                AppEmptyStateView(
                    "trips.archived.empty.title",
                    systemImage: "archivebox",
                    message: "trips.archived.empty.message"
                )
            } else {
                ForEach(archivedGroups) { group in
                    NavigationLink {
                        GroupDetailView(
                            group: group,
                            onCapture: {},
                            onAttachPhoto: onAttachPhoto,
                            onViewingGroupChange: onViewingGroupChange,
                            allowsCapture: false
                        )
                    } label: {
                        GroupRow(group: group)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            restore(group: group)
                        } label: {
                            Label("trip.restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(Color("LedgerGreen"))
                        .accessibilityIdentifier("trip.action.restore")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletionGroup = group
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("common.delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("trips.archived.list")
        .navigationTitle("trips.archived.title")
        .onChange(of: archivedGroupIDs) { _, ids in
            if ids.isEmpty {
                dismiss()
            }
        }
        .confirmationDialog(groupDeleteTitle, isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("group.delete.keep") {
                confirmDeleteGroup(receiptPolicy: .keepReceiptsUnfiled)
            }
            Button(
                String.localizedStringWithFormat(
                    String(localized: "group.delete.deleteAll"),
                    pendingDeletionReceiptCount
                )
            ) {
                confirmDeleteGroup(receiptPolicy: .deleteReceipts)
            }
            Button("common.cancel", role: .cancel) {
                pendingDeletionGroup = nil
            }
        }
    }

    private var archivedGroups: [ExpenseGroup] {
        ExpenseGroup.sortedByMostRecentArchive(groups)
    }

    private var archivedGroupIDs: [String] {
        archivedGroups.map { String(describing: $0.persistentModelID) }
    }

    private var pendingDeletionReceiptCount: Int {
        pendingDeletionGroup?.receipts?.count ?? 0
    }

    private var groupDeleteTitle: String {
        String.localizedStringWithFormat(String(localized: "group.delete.title"), pendingDeletionGroup == nil ? 0 : 1)
    }

    private func restore(group: ExpenseGroup) {
        try? ReceiptStore.restore(group, in: modelContext)
        if archivedGroups.count <= 1 {
            dismiss()
        }
    }

    private func confirmDeleteGroup(receiptPolicy: ExpenseGroupReceiptDeletionPolicy) {
        guard let group = pendingDeletionGroup else { return }
        ReceiptStore.delete(group: group, receiptPolicy: receiptPolicy, in: modelContext)
        pendingDeletionGroup = nil
        try? modelContext.save()
        if archivedGroups.count <= 1 {
            dismiss()
        }
    }
}

struct GroupRow: View {
    var group: ExpenseGroup
    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var iconTileSize = 26
    #else
    @ScaledMetric(relativeTo: .body) private var iconTileSize = 34
    #endif

    var body: some View {
        let summary = ExpenseGroupSummary.make(for: group)
        let totals = ExpenseFormatters.totalPresentation(summary.totals)
        #if os(macOS)
        HStack(spacing: 4) {
            FolderProfileGlyph(profileID: group.profileID, size: iconTileSize, cornerRadius: 7, imageScale: .small)
            Text(group.name)
                .contentScaledFont(.body.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if group.pinnedAt != nil {
                PinnedFolderIndicator()
            }
            Text(totals.primary)
                .contentScaledFont(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .help(sidebarHelp(totals: totals))
        .accessibilityElement(children: .combine)
        .accessibilityValue(group.pinnedAt == nil ? Text("") : Text("folder.pinned"))
        #else
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                FolderProfileGlyph(profileID: group.profileID, size: iconTileSize, cornerRadius: 9, imageScale: .medium)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .contentScaledFont(.body.weight(.semibold))
                    Text(groupSubtitle)
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if group.pinnedAt != nil {
                        PinnedFolderIndicator()
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(totals.primary)
                            .contentScaledFont(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        ForEach(totals.secondary, id: \.self) { total in
                            Text(total)
                                .contentScaledFont(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .multilineTextAlignment(.trailing)
                }
            }

            if group.pinnedAt != nil, summary.breakdown.isEmpty == false {
                FeaturedBreakdownRail(summary: summary, receipts: group.activeReceipts)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(group.pinnedAt == nil ? Text("") : Text("folder.pinned"))
        #endif
    }

    private var groupSubtitle: String {
        GroupMetadata.subtitle(for: group)
    }

    private func sidebarHelp(totals: CurrencyTotalsPresentation) -> String {
        let fullTotals = ([totals.primary] + totals.secondary).joined(separator: String(localized: "metadata.separator"))
        let baseHelp = String.localizedStringWithFormat(
            String(localized: "mac.sidebar.trip.help"),
            groupSubtitle,
            fullTotals
        )
        guard group.pinnedAt != nil else { return baseHelp }
        return [baseHelp, String(localized: "folder.pinned")]
            .joined(separator: String(localized: "list.separator"))
    }
}

private struct PinnedFolderIndicator: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .contentScaledFont(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("folder.pinned.indicator")
            .accessibilityHidden(true)
    }
}

private struct FeaturedTripCard: View {
    var group: ExpenseGroup
    @ScaledMetric(relativeTo: .body) private var iconTileSize = 34

    var body: some View {
        let receipts = group.activeReceipts.sorted { $0.date > $1.date }
        let summary = ExpenseGroupSummary.make(for: group)
        let thumbnailReceipts = FeaturedThumbnailSelection.receipts(from: receipts)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                FolderProfileGlyph(profileID: group.profileID, size: iconTileSize, cornerRadius: 9, imageScale: .large)

                Text(group.name)
                    .contentScaledFont(.title3.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupTotalsHero(
                    summary: summary,
                    metadata: GroupMetadata.detailMeta(for: group),
                    isPinned: group.pinnedAt != nil
                )

                if summary.breakdown.isEmpty == false {
                    FeaturedBreakdownRail(summary: summary, receipts: receipts)
                        .accessibilityHidden(true)
                }
            }

            if thumbnailReceipts.isEmpty == false {
                FeaturedReceiptThumbnailStrip(receipts: thumbnailReceipts)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(group.pinnedAt == nil ? Text("") : Text("folder.pinned"))
    }
}

enum FeaturedThumbnailSelection {
    static func receipts(from receipts: [Receipt], limit: Int = 3) -> [Receipt] {
        guard limit > 0 else {
            return []
        }
        return Array(receipts.lazy.filter { imageData(for: $0) != nil }.prefix(limit))
    }

    static func imageData(for receipt: Receipt) -> Data? {
        let attachments = receipt.attachments?.sorted { $0.pageIndex < $1.pageIndex } ?? []
        for attachment in attachments {
            if let thumbnailData = nonEmptyData(attachment.thumbnailData) {
                return thumbnailData
            }
            if let imageData = nonEmptyData(attachment.imageData) {
                return imageData
            }
        }
        return nil
    }

    private static func nonEmptyData(_ data: Data?) -> Data? {
        guard let data, data.isEmpty == false else {
            return nil
        }
        return data
    }
}

private struct FeaturedReceiptThumbnailStrip: View {
    var receipts: [Receipt]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(receipts) { receipt in
                FeaturedReceiptThumbnail(receipt: receipt)
            }
        }
    }
}

private struct FeaturedReceiptThumbnail: View {
    var receipt: Receipt
    @ScaledMetric(relativeTo: .body) private var thumbnailSize = 44

    var body: some View {
        if let data = FeaturedThumbnailSelection.imageData(for: receipt),
           let image = ReceiptPlatformImage.receiptImage(data: data) {
            Image(receiptImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.receiptSeparator, lineWidth: 0.5)
                }
        }
    }
}

struct ReceiptDateSection {
    var day: Date
    var receipts: [Receipt]
}

enum ReceiptDateSections {
    static func sections(for receipts: [Receipt], calendar: Calendar = .current) -> [ReceiptDateSection] {
        let grouped = Dictionary(grouping: receipts) { receipt in
            calendar.startOfDay(for: receipt.date)
        }
        return grouped
            .map { day, receipts in
                ReceiptDateSection(day: day, receipts: receipts.sorted { $0.date > $1.date })
            }
            .sorted { $0.day > $1.day }
    }
}

private enum GroupMetadata {
    static func subtitle(for group: ExpenseGroup) -> String {
        let receipts = group.activeReceipts
        guard let interval = receiptDateInterval(for: receipts) else {
            return String.localizedStringWithFormat(String(localized: "groups.receipt.count"), receipts.count)
        }
        return String.localizedStringWithFormat(
            String(localized: "groups.row.subtitle.dated"),
            interval,
            receipts.count
        )
    }

    static func detailMeta(for group: ExpenseGroup) -> String {
        let receipts = group.activeReceipts
        guard let interval = receiptDateInterval(for: receipts) else {
            return String.localizedStringWithFormat(String(localized: "groups.receipt.count"), receipts.count)
        }
        return String.localizedStringWithFormat(
            String(localized: "group.detail.meta"),
            receipts.count,
            interval
        )
    }

    private static func receiptDateInterval(for receipts: [Receipt]) -> String? {
        guard let first = receipts.map(\.date).min(), let last = receipts.map(\.date).max() else {
            return nil
        }
        return ExpenseFormatters.dateInterval(first, last)
    }
}

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var group: ExpenseGroup
    var onCapture: () -> Void
    var onAttachPhoto: (Receipt) -> Void
    var onViewingGroupChange: (ExpenseGroup?) -> Void = { _ in }
    var allowsCapture = true

    @State private var typeFilter: String?
    @State private var paymentFilter: PaymentMethod?
    @State private var exportShareItem: ExportShareItem?
    @State private var exportProgress: ExportProgressState?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError = false
    @State private var isShowingEditGroup = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    GroupTotalsHero(summary: summary, metadata: GroupMetadata.detailMeta(for: group))
                    BreakdownRowsView(summary: summary, group: group, typeFilter: $typeFilter)
                }
                .padding(.vertical, 8)
            }

            Section {
                FilterStrip(
                    typeFilter: $typeFilter,
                    paymentFilter: $paymentFilter,
                    categories: CategoryUsage.filterCategories(for: group)
                )
                if filteredReceipts.isEmpty {
                    if allowsCapture {
                        AppEmptyStateView(
                            "group.detail.empty.title",
                            systemImage: "receipt",
                            message: "group.detail.empty.message"
                        ) {
                            Button("capture.accessory.title", action: onCapture)
                        }
                    } else {
                        AppEmptyStateView(
                            "group.detail.empty.title",
                            systemImage: "receipt",
                            message: "group.detail.empty.message"
                        )
                    }
                }
            }

            if filteredReceipts.isEmpty == false {
                ForEach(daySections, id: \.day) { section in
                    Section(ExpenseFormatters.dayHeader(section.day)) {
                        ForEach(section.receipts) { receipt in
                            NavigationLink {
                                ReceiptDetailView(receipt: receipt, onAddPhoto: onAttachPhoto)
                            } label: {
                                ReceiptRow(receipt: receipt)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    try? ReceiptStore.archive(receipt, in: modelContext)
                                } label: {
                                    Label("receipt.archive", systemImage: "archivebox")
                                }
                                .tint(Color("LedgerGreen"))
                                .accessibilityIdentifier("receipt.action.archive")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .expenseLeadingAction) {
                Button { isShowingEditGroup = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(Text("common.edit"))
                .accessibilityIdentifier("group.edit")
            }
            ToolbarItem(placement: .expenseTrailingAction) {
                Button { exportGroup() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("export.button"))
                .accessibilityIdentifier("group.export")
            }
        }
        .sheet(isPresented: $isShowingEditGroup) {
            GroupEditorSheet(group: group) {
                dismiss()
            }
        }
        .sheet(item: $exportShareItem, onDismiss: {
            cleanupExportShareItem()
        }) { item in
            #if os(iOS)
            ActivityView(activityItems: [item.url])
            #elseif os(macOS)
            MacExportReadyView(item: item)
            #endif
        }
        .alert("export.error.title", isPresented: $exportError) {
            Button("common.ok", role: .cancel) {}
        }
        .overlay {
            if let exportProgress {
                ExportProgressOverlay(state: exportProgress) {
                    cancelExport()
                }
            }
        }
        .onDisappear {
            cancelExport()
            onViewingGroupChange(nil)
        }
        .onAppear {
            onViewingGroupChange(group.isArchived ? nil : group)
        }
    }

    private var summary: ExpenseGroupSummary {
        ExpenseGroupSummary.make(for: group)
    }

    private var filteredReceipts: [Receipt] {
        group.activeReceipts
            .filter { typeFilter == nil || $0.categoryID == typeFilter }
            .filter { paymentFilter == nil || $0.paymentMethod == paymentFilter }
            .sorted { $0.date > $1.date }
    }

    private var daySections: [ReceiptDateSection] {
        ReceiptDateSections.sections(for: filteredReceipts)
    }

    private func exportGroup() {
        startExport(receipts: group.activeReceipts, archiveName: group.name)
    }

    private func startExport(receipts: [Receipt], archiveName: String) {
        exportTask?.cancel()
        cleanupExportShareItem()

        let exportReceipts = ReceiptExportMapper.exportReceipts(from: receipts)
        let fileName = ExportFilenameBuilder().archiveFilename(
            for: archiveName,
            fallbackSlug: String(localized: "export.unfiled.filename")
        )
        let csvCommentRow = String(localized: "export.csv.comment")
        let manualEntryStub = ExportManualEntryStub.localized
        exportProgress = ExportProgressState(fileName: fileName, completedReceipts: 0, totalReceipts: exportReceipts.count)

        exportTask = Task {
            do {
                for try await event in exportPreparationEvents(
                    receipts: exportReceipts,
                    csvCommentRow: csvCommentRow,
                    manualEntryStub: manualEntryStub,
                    fileName: fileName
                ) {
                    switch event {
                    case .progress(let progress):
                        exportProgress = ExportProgressState(
                            fileName: fileName,
                            completedReceipts: progress.completedReceipts,
                            totalReceipts: progress.totalReceipts
                        )
                    case .completed(let url):
                        exportProgress = nil
                        exportShareItem = ExportShareItem(url: url)
                    }
                }
            } catch is CancellationError {
                exportProgress = nil
            } catch {
                exportProgress = nil
                exportError = true
            }
            exportTask = nil
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportProgress = nil
    }

    private func cleanupExportShareItem() {
        if let url = exportShareItem?.url {
            try? FileManager.default.removeItem(at: url)
        }
        exportShareItem = nil
    }
}

private struct GroupTotalsHero: View {
    var summary: ExpenseGroupSummary
    var metadata: String
    var isPinned = false

    var body: some View {
        let totals = ExpenseFormatters.totalPresentation(summary.totals)
        VStack(alignment: .leading, spacing: 4) {
            Text(totals.primary)
                .contentScaledFont(.title.weight(.light))
                .monospacedDigit()
            ForEach(totals.secondary, id: \.self) { secondary in
                Text(secondary)
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                if isPinned {
                    PinnedFolderIndicator()
                }
                Text(metadata)
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BreakdownRowItem: Equatable, Identifiable {
    var category: FolderCategory
    var caption: String
    var amountText: String
    var accessibilityLabel: String
    var accessibilityIdentifier: String
    var id: String { category.id }
}

enum BreakdownRows {
    /// Rows for categories used by active receipts, in folder order, with used-but-hidden categories
    /// appended afterward. No empty rows for visible-but-unused categories (SPEC §D7).
    static func items(for summary: ExpenseGroupSummary, in group: ExpenseGroup) -> [BreakdownRowItem] {
        let snapshot = group.categorySnapshot
        let orderedIDs = CategoryOrdering.usedCategoryIDs(
            visibleOrder: group.visibleCategoryIDs,
            usedIDs: Set(summary.breakdown.keys)
        )
        return orderedIDs.compactMap { id in
            guard let breakdown = summary.breakdown[id] else { return nil }
            let category = CategoryResolver.category(forID: id, in: snapshot)
            let name = category.displayName
            let amountText = ExpenseFormatters.compactTotals(breakdown.totals)
            let caption = String.localizedStringWithFormat(
                String(localized: "group.breakdown.cell.caption"),
                breakdown.count,
                name
            )
            let receiptCount = String.localizedStringWithFormat(
                String(localized: "groups.receipt.count"),
                breakdown.count
            )
            let separator = String(localized: "list.separator")

            return BreakdownRowItem(
                category: category,
                caption: caption,
                amountText: amountText,
                accessibilityLabel: [name, receiptCount, amountText].joined(separator: separator),
                accessibilityIdentifier: "group.breakdown.\(id)"
            )
        }
    }

    static func toggledFilter(current: String?, tapped id: String) -> String? {
        current == id ? nil : id
    }
}

private struct BreakdownRowsView: View {
    var summary: ExpenseGroupSummary
    var group: ExpenseGroup
    @Binding var typeFilter: String?
    @State private var selectionFeedbackTrigger = 0

    var body: some View {
        VStack(spacing: 8) {
            ForEach(BreakdownRows.items(for: summary, in: group)) { row in
                Button {
                    typeFilter = BreakdownRows.toggledFilter(current: typeFilter, tapped: row.category.id)
                    selectionFeedbackTrigger += 1
                } label: {
                    BreakdownRowLabel(row: row, isSelected: typeFilter == row.category.id)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(row.accessibilityIdentifier)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(row.accessibilityLabel))
                .accessibilityAddTraits(typeFilter == row.category.id ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }
}

private struct FeaturedBreakdownRail: View {
    var summary: ExpenseGroupSummary
    var receipts: [Receipt]

    var body: some View {
        let categories = CategoryUsage.orderedCategories(for: receipts, in: receipts.first?.group)
        WrappingHStackLayout(spacing: 8) {
            ForEach(categories) { category in
                if let breakdown = summary.breakdown[category.id] {
                    FeaturedBreakdownChipLabel(category: category, count: breakdown.count)
                }
            }
        }
    }
}

private struct WrappingHStackLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(subviews: subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (
            CGSize(width: usedWidth, height: subviews.isEmpty ? 0 : y + rowHeight),
            points
        )
    }
}

private struct FeaturedBreakdownChipLabel: View {
    var category: FolderCategory
    var count: Int

    var body: some View {
        Label {
            Text(count, format: .number)
        } icon: {
            Image(systemName: category.symbolName)
        }
        .contentScaledFont(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(category.color.opacity(0.14), in: Capsule())
        .foregroundStyle(category.color)
    }
}

private struct BreakdownRowLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var row: BreakdownRowItem
    var isSelected: Bool
    @ScaledMetric(relativeTo: .body) private var glyphTileSize = 28
    @ScaledMetric(relativeTo: .caption) private var glyphSize = 15

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 8) {
            Image(systemName: row.category.symbolName)
                .contentScaledFont(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: glyphTileSize, height: glyphTileSize)
                .background(row.category.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    caption
                    amount
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                caption
                Spacer(minLength: 8)
                amount
                    .multilineTextAlignment(.trailing)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var caption: some View {
        Text(row.caption)
            .contentScaledFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var amount: some View {
        Text(row.amountText)
            .contentScaledFont(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rowBackground: Color {
        isSelected ? row.category.color.opacity(0.14) : .receiptQuaternaryFill
    }
}

private struct FilterStrip: View {
    @Binding var typeFilter: String?
    @Binding var paymentFilter: PaymentMethod?
    var categories: [FolderCategory]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if typeFilter == nil && paymentFilter == nil {
                    FilterChip(title: String(localized: "filter.all"), isSelected: false)
                }
                if let typeFilter {
                    FilterChip(title: filterCategoryName(typeFilter), isSelected: true) {
                        self.typeFilter = nil
                    }
                }
                if let paymentFilter {
                    FilterChip(title: ExpenseFormatters.paymentName(paymentFilter), isSelected: true) {
                        self.paymentFilter = nil
                    }
                }
                Menu {
                    Section("filter.type.section") {
                        Button("filter.allTypes") { typeFilter = nil }
                        ForEach(categories) { category in
                            Button(category.displayName) { typeFilter = category.id }
                        }
                    }
                    Section("filter.payment.section") {
                        Button("filter.allPayments") { paymentFilter = nil }
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Button(ExpenseFormatters.paymentName(method)) { paymentFilter = method }
                        }
                    }
                } label: {
                    Label("filter.add", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
    }

    private func filterCategoryName(_ id: String) -> String {
        categories.first { $0.id == id }?.displayName
            ?? CategoryResolver.category(forID: id, in: nil).displayName
    }
}

private struct FilterChip: View {
    var title: String
    var isSelected: Bool
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("filter.remove"))
            }
        }
        .contentScaledFont(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color("LedgerGreen") : Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(isSelected ? .white : .primary)
    }
}

private struct UnfiledReceiptsView: View {
    @Environment(\.modelContext) private var modelContext
    var receipts: [Receipt]
    var onAttachPhoto: (Receipt) -> Void
    @State private var exportShareItem: ExportShareItem?
    @State private var exportProgress: ExportProgressState?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError = false

    var body: some View {
        List(receipts) { receipt in
            NavigationLink {
                ReceiptDetailView(receipt: receipt, onAddPhoto: onAttachPhoto)
            } label: {
                ReceiptRow(receipt: receipt)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    try? ReceiptStore.archive(receipt, in: modelContext)
                } label: {
                    Label("receipt.archive", systemImage: "archivebox")
                }
                .tint(Color("LedgerGreen"))
                .accessibilityIdentifier("receipt.action.archive")
            }
        }
        .navigationTitle("groups.unfiled.title")
        .toolbar {
            ToolbarItem(placement: .expenseTrailingAction) {
                Button { exportUnfiled() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("export.button"))
                .accessibilityIdentifier("group.export")
            }
        }
        .sheet(item: $exportShareItem, onDismiss: {
            cleanupExportShareItem()
        }) { item in
            #if os(iOS)
            ActivityView(activityItems: [item.url])
            #elseif os(macOS)
            MacExportReadyView(item: item)
            #endif
        }
        .alert("export.error.title", isPresented: $exportError) {
            Button("common.ok", role: .cancel) {}
        }
        .overlay {
            if let exportProgress {
                ExportProgressOverlay(state: exportProgress) {
                    cancelExport()
                }
            }
        }
        .onDisappear {
            cancelExport()
        }
    }

    private func exportUnfiled() {
        exportTask?.cancel()
        cleanupExportShareItem()

        let exportReceipts = ReceiptExportMapper.exportReceipts(from: receipts)
        let fileName = ExportFilenameBuilder().archiveFilename(
            for: String(localized: "export.unfiled.filename"),
            fallbackSlug: "unfiled-receipts"
        )
        let csvCommentRow = String(localized: "export.csv.comment")
        let manualEntryStub = ExportManualEntryStub.localized
        exportProgress = ExportProgressState(fileName: fileName, completedReceipts: 0, totalReceipts: exportReceipts.count)

        exportTask = Task {
            do {
                for try await event in exportPreparationEvents(
                    receipts: exportReceipts,
                    csvCommentRow: csvCommentRow,
                    manualEntryStub: manualEntryStub,
                    fileName: fileName
                ) {
                    switch event {
                    case .progress(let progress):
                        exportProgress = ExportProgressState(
                            fileName: fileName,
                            completedReceipts: progress.completedReceipts,
                            totalReceipts: progress.totalReceipts
                        )
                    case .completed(let url):
                        exportProgress = nil
                        exportShareItem = ExportShareItem(url: url)
                    }
                }
            } catch is CancellationError {
                exportProgress = nil
            } catch {
                exportProgress = nil
                exportError = true
            }
            exportTask = nil
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportProgress = nil
    }

    private func cleanupExportShareItem() {
        if let url = exportShareItem?.url {
            try? FileManager.default.removeItem(at: url)
        }
        exportShareItem = nil
    }
}

struct ExportProgressState: Equatable {
    var fileName: String
    var completedReceipts: Int
    var totalReceipts: Int
}

enum ExportPreparationEvent: Sendable {
    case progress(ExportArchiveProgress)
    case completed(URL)
}

func exportPreparationEvents(
    receipts: [ExportReceipt],
    csvCommentRow: String,
    manualEntryStub: ExportManualEntryStub,
    fileName: String
) -> AsyncThrowingStream<ExportPreparationEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try ExportArchiveBuilder(
                    csvCommentRow: csvCommentRow,
                    manualEntryStub: manualEntryStub
                ).archiveData(for: receipts) { progress in
                    continuation.yield(.progress(progress))
                }
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
                continuation.yield(.completed(url))
                continuation.finish()
            } catch {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

struct ExportProgressOverlay: View {
    var state: ExportProgressState
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Label(state.fileName, systemImage: "doc.zipper")
                    .contentScaledFont(.headline)
                ProgressView(value: Double(state.completedReceipts), total: Double(max(state.totalReceipts, 1)))
                    .tint(Color("LedgerGreen"))
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "export.progress.subtitle"),
                        state.completedReceipts,
                        state.totalReceipts
                    )
                )
                .contentScaledFont(.footnote)
                .foregroundStyle(.secondary)
                Button("common.cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(24)
        }
        .accessibilityIdentifier("export.progress")
    }
}

extension ExportManualEntryStub {
    static var localized: ExportManualEntryStub {
        ExportManualEntryStub(
            unavailableMessage: String(localized: "export.stub.noImage"),
            receiptIDLabel: String(localized: "export.stub.receiptID"),
            vendorLabel: String(localized: "export.stub.vendor"),
            manualEntryVendor: String(localized: "export.stub.manualVendor"),
            dateLabel: String(localized: "export.stub.date"),
            amountLabel: String(localized: "export.stub.amount")
        )
    }
}

struct GroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let group: ExpenseGroup?
    private let onDelete: () -> Void

    @State private var name = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var includeDates = false
    @State private var userToggledDates = false
    @State private var notes = ""
    @State private var isShowingDeleteConfirmation = false
    @State private var composer: FolderCategoryComposerModel
    @State private var pendingProfileID: String?
    @FocusState private var isNameFocused: Bool

    init(group: ExpenseGroup? = nil, onDelete: @escaping () -> Void = {}) {
        self.group = group
        self.onDelete = onDelete
        _name = State(initialValue: group?.name ?? "")
        _startDate = State(initialValue: group?.startDate ?? Date())
        _endDate = State(initialValue: group?.endDate ?? group?.startDate ?? Date())
        _notes = State(initialValue: group?.notes ?? "")

        let profileID = group?.profileID ?? FolderProfileCatalog.workTripID
        let snapshot = group?.categorySnapshot ?? FolderProfileCatalog.defaultSnapshot(forProfileID: profileID)
        let usedIDs = Set((group?.receipts ?? []).map(\.categoryID))
        _composer = State(initialValue: FolderCategoryComposerModel(
            profileID: profileID,
            snapshot: snapshot,
            usedCategoryIDs: usedIDs,
            allowsProfileChange: group == nil
        ))

        let profile = FolderProfileCatalog.profile(id: profileID) ?? FolderProfileCatalog.workTrip
        let hasDates = group?.startDate != nil || group?.endDate != nil
        _includeDates = State(initialValue: group == nil ? profile.isDateBound : hasDates)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("group.editor.section.details") {
                    TextField("group.editor.name", text: $name)
                        .focused($isNameFocused)
                        .accessibilityIdentifier("group.editor.name")
                    profileRow
                    Toggle("group.editor.includeDates", isOn: Binding(
                        get: { includeDates },
                        set: { includeDates = $0; userToggledDates = true }
                    ))
                    if includeDates {
                        ConfirmedDatePickerRow(
                            "group.editor.start",
                            selection: $startDate,
                            accessibilityIdentifier: "group.editor.startDate"
                        )
                        ConfirmedDatePickerRow(
                            "group.editor.end",
                            selection: $endDate,
                            accessibilityIdentifier: "group.editor.endDate"
                        )
                    }
                    TextField("receipt.field.notes", text: $notes, axis: .vertical)
                }

                CategoryComposerSections(
                    model: composer,
                    receiptCount: receiptCount(using:)
                ) { category, destination in
                    reassignReceipts(from: category.id, to: destination.id)
                }

                if group != nil {
                    Section {
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("group.editor.delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("group.editor.delete")
                    }
                }
            }
            .macGroupedForm(accessibilityIdentifier: "mac.folderEditor.form")
            .navigationTitle(group == nil ? "groups.create" : "group.editor.edit.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                        .macCancelAction()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(canSave == false)
                        .macDefaultAction()
                }
            }
            .confirmationDialog(profileChangeTitle, isPresented: profileChangeBinding, titleVisibility: .visible) {
                Button("folder.profile.change.replace") { resolvePendingProfile(replace: true) }
                Button("folder.profile.change.keep") { resolvePendingProfile(replace: false) }
                Button("common.cancel", role: .cancel) { pendingProfileID = nil }
            }
            .confirmationDialog(groupDeleteTitle, isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
                Button("group.delete.keep") {
                    confirmDeleteGroup(receiptPolicy: .keepReceiptsUnfiled)
                }
                Button(
                    String.localizedStringWithFormat(
                        String(localized: "group.delete.deleteAll"),
                        pendingDeletionReceiptCount
                    )
                ) {
                    confirmDeleteGroup(receiptPolicy: .deleteReceipts)
                }
                Button("common.cancel", role: .cancel) {}
            }
        }
        .macFormPresentation(
            accessibilityIdentifier: "mac.folderEditor.sheet",
            minHeight: 560,
            idealHeight: 680
        )
        .onAppear {
            #if os(macOS)
            if group == nil {
                isNameFocused = true
            }
            #endif
        }
    }

    @ViewBuilder
    private var profileRow: some View {
        if composer.allowsProfileChange {
            Picker("group.editor.profile", selection: Binding(
                get: { composer.profileID },
                set: { requestProfileChange(to: $0) }
            )) {
                ForEach(FolderProfileCatalog.all) { profile in
                    HStack(spacing: 10) {
                        FolderProfileGlyph(identity: profile.identity, size: 24, cornerRadius: 6, imageScale: .small)
                        Text(profile.displayName)
                    }
                    .tag(profile.id)
                }
            }
            .accessibilityIdentifier("group.editor.profile")
        } else {
            LabeledContent("group.editor.profile") {
                HStack(spacing: 8) {
                    FolderProfileGlyph(profileID: composer.profileID, size: 24, cornerRadius: 6, imageScale: .small)
                    Text(composer.profileForDisplay)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("group.editor.profile")
        }
    }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && composer.hasSelectableCategory
    }

    private func requestProfileChange(to newID: String) {
        guard newID != composer.profileID else { return }
        if composer.hasUserEditedCategories {
            pendingProfileID = newID
        } else {
            composer.changeProfile(to: newID, replaceCategories: true)
            syncDatesToProfileIfUntouched()
        }
    }

    private func resolvePendingProfile(replace: Bool) {
        guard let newID = pendingProfileID else { return }
        composer.changeProfile(to: newID, replaceCategories: replace)
        pendingProfileID = nil
        syncDatesToProfileIfUntouched()
    }

    private func syncDatesToProfileIfUntouched() {
        guard group == nil, userToggledDates == false else { return }
        includeDates = FolderProfileCatalog.profile(id: composer.profileID)?.isDateBound ?? includeDates
    }

    private var profileChangeBinding: Binding<Bool> {
        Binding(
            get: { pendingProfileID != nil },
            set: { if $0 == false { pendingProfileID = nil } }
        )
    }

    private var profileChangeTitle: String {
        guard let pendingProfileID, let profile = FolderProfileCatalog.profile(id: pendingProfileID) else {
            return String(localized: "folder.profile.change.title")
        }
        return String.localizedStringWithFormat(String(localized: "folder.profile.change.title"), profile.displayName)
    }

    private func receiptCount(using categoryID: String) -> Int {
        (group?.receipts ?? []).filter { $0.categoryID == categoryID }.count
    }

    private func reassignReceipts(from oldID: String, to newID: String) {
        guard let group else { return }
        for receipt in group.receipts ?? [] where receipt.categoryID == oldID {
            receipt.categoryID = newID
        }
        try? modelContext.save()
        composer.markReassigned(from: oldID)
        composer.remove(id: oldID)
    }

    private func save() {
        let snapshotJSON = composer.snapshot().jsonString()
        if let group {
            group.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            group.startDate = includeDates ? startDate : nil
            group.endDate = includeDates ? endDate : nil
            group.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
            group.categorySnapshotJSON = snapshotJSON
        } else {
            let group = ExpenseGroup(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: includeDates ? startDate : nil,
                endDate: includeDates ? endDate : nil,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                profileID: composer.profileID,
                categorySnapshotJSON: snapshotJSON
            )
            modelContext.insert(group)
        }
        try? modelContext.save()
        dismiss()
    }

    private var pendingDeletionReceiptCount: Int {
        group?.receipts?.count ?? 0
    }

    private var groupDeleteTitle: String {
        String.localizedStringWithFormat(String(localized: "group.delete.title"), group == nil ? 0 : 1)
    }

    private func confirmDeleteGroup(receiptPolicy: ExpenseGroupReceiptDeletionPolicy) {
        guard let group else { return }
        ReceiptStore.delete(group: group, receiptPolicy: receiptPolicy, in: modelContext)
        try? modelContext.save()
        dismiss()
        onDelete()
    }
}
