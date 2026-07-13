import ExpenseCore
import Observation
import SwiftData
import SwiftUI

struct AppEmptyStateView<Actions: View>: View {
    var title: LocalizedStringKey
    var systemImage: String
    var message: LocalizedStringKey
    var showsActions: Bool
    @ViewBuilder var actions: Actions
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 44

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.showsActions = true
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .contentScaledFont(.largeTitle)
                .imageScale(.large)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .contentScaledFont(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
            Text(message)
                .contentScaledFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            if showsActions {
                Divider()
                actions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

extension AppEmptyStateView where Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) {
        self.init(title, systemImage: systemImage, message: message) {
            EmptyView()
        }
        self.showsActions = false
    }
}

enum ReceiptMode: Equatable {
    case active
    case archived
}

enum ReceiptListGroupFilter: Equatable {
    case all
    case unfiled
    case group(PersistentIdentifier)
}

struct ReceiptListFilter: Equatable {
    var searchText: String = ""
    var groupFilter: ReceiptListGroupFilter = .all
    var typeFilter: String?
    var paymentFilter: PaymentMethod?
    var hasPhotoOnly = false
    var receiptMode: ReceiptMode = .active

    func filtered(_ receipts: [Receipt]) -> [Receipt] {
        receipts
            .filter { receipt in
                switch receiptMode {
                case .active:
                    receipt.isEffectivelyArchived == false
                case .archived:
                    receipt.isArchived && receipt.group?.isArchived != true
                }
            }
            .filter(matchesSearch)
            .filter(matchesGroup)
            .filter { typeFilter == nil || $0.categoryID == typeFilter }
            .filter { paymentFilter == nil || $0.paymentMethod == paymentFilter }
            .filter { hasPhotoOnly == false || ($0.attachments?.isEmpty == false) }
    }

    private func matchesSearch(_ receipt: Receipt) -> Bool {
        searchText.isEmpty
            || receipt.vendor.localizedCaseInsensitiveContains(searchText)
            || (receipt.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private func matchesGroup(_ receipt: Receipt) -> Bool {
        switch groupFilter {
        case .all:
            true
        case .unfiled:
            receipt.group == nil
        case .group(let id):
            receipt.group?.persistentModelID == id
        }
    }
}

struct ReceiptsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \ExpenseGroup.name) private var groups: [ExpenseGroup]
    var onAdd: () -> Void
    var onAttachPhoto: (Receipt) -> Void

    @State private var searchText = ""
    @State private var groupFilter: ReceiptListGroupFilter = .all
    @State private var typeFilter: String?
    @State private var paymentFilter: PaymentMethod?
    @State private var hasPhotoOnly = false
    @State private var receiptMode: ReceiptMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ReceiptFilterStrip(
                        groupFilter: $groupFilter,
                        groups: activeGroups,
                        typeFilter: $typeFilter,
                        paymentFilter: $paymentFilter,
                        hasPhotoOnly: $hasPhotoOnly,
                        typeFilterCategories: typeFilterCategories
                    )
                }
                if groupedReceipts.isEmpty {
                    AppEmptyStateView(
                        emptyTitle,
                        systemImage: "receipt",
                        message: emptyMessage
                    )
                } else {
                    ForEach(groupedReceipts, id: \.month) { group in
                        Section(ExpenseFormatters.month(group.month)) {
                            ForEach(group.receipts) { receipt in
                                receiptNavigationLink(for: receipt)
                            }
                        }
                    }
                }
            }
            .navigationTitle("tab.receipts")
            .searchable(text: $searchText, prompt: "receipts.search.prompt")
            .toolbar {
                ToolbarItem(placement: .expenseLeadingAction) {
                    Menu {
                        Button {
                            receiptMode = .active
                        } label: {
                            menuSelectionLabel(String(localized: "receipts.filter.active"), isSelected: receiptMode == .active)
                        }
                        .accessibilityIdentifier("receipts.filter.active")
                        Button {
                            receiptMode = .archived
                        } label: {
                            menuSelectionLabel(String(localized: "receipts.filter.archivedMode"), isSelected: receiptMode == .archived)
                        }
                        .accessibilityIdentifier("receipts.filter.archived")
                    } label: {
                        Image(systemName: receiptMode == .archived ? "archivebox" : "tray.full")
                    }
                    .accessibilityLabel(Text("receipts.mode.menu"))
                    .accessibilityIdentifier("receipts.filter.menu")
                }
                ToolbarItem(placement: .expenseTrailingAction) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("capture.add.title"))
                }
            }
        }
    }

    private var filteredReceipts: [Receipt] {
        ReceiptListFilter(
            searchText: searchText,
            groupFilter: groupFilter,
            typeFilter: typeFilter,
            paymentFilter: paymentFilter,
            hasPhotoOnly: hasPhotoOnly,
            receiptMode: receiptMode
        )
        .filtered(receipts)
    }

    private func receiptNavigationLink(for receipt: Receipt) -> some View {
        NavigationLink {
            ReceiptDetailView(receipt: receipt, onAddPhoto: onAttachPhoto)
        } label: {
            ReceiptRow(receipt: receipt)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            receiptSwipeAction(receipt)
        }
    }

    private var activeGroups: [ExpenseGroup] {
        groups.filter { $0.isArchived == false }
    }

    /// Category options for the type filter: the selected folder's categories when scoped to a
    /// folder, otherwise the categories actually used by receipts in recency order — never the full
    /// built-in preset list (SPEC §D7).
    private var typeFilterCategories: [FolderCategory] {
        if case let .group(id) = groupFilter,
           let group = groups.first(where: { $0.persistentModelID == id }) {
            return CategoryUsage.filterCategories(for: group)
        }
        var seen = Set<String>()
        var result: [FolderCategory] = []
        for receipt in receipts where receipt.isEffectivelyArchived == false {
            if seen.insert(receipt.categoryID).inserted {
                result.append(receipt.resolvedCategory)
            }
        }
        return result
    }

    private var groupedReceipts: [(month: Date, receipts: [Receipt])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredReceipts) { receipt in
            calendar.date(from: calendar.dateComponents([.year, .month], from: receipt.date)) ?? receipt.date
        }
        return grouped
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.month > $1.month }
    }

    private var emptyTitle: LocalizedStringKey {
        if receiptMode == .archived { return "receipts.archived.empty.title" }
        return LocalizedStringKey(searchText.isEmpty ? "receipts.empty.title" : "receipts.search.empty.title")
    }

    private var emptyMessage: LocalizedStringKey {
        if receiptMode == .archived { return "receipts.archived.empty.message" }
        return LocalizedStringKey(searchText.isEmpty ? "receipts.empty.message" : "receipts.search.empty.message")
    }

    @ViewBuilder
    private func menuSelectionLabel(_ text: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    @ViewBuilder
    private func receiptSwipeAction(_ receipt: Receipt) -> some View {
        if receipt.isArchived {
            Button {
                try? ReceiptStore.restore(receipt, in: modelContext)
            } label: {
                Label("receipt.restore", systemImage: "arrow.uturn.backward")
            }
            .tint(Color("LedgerGreen"))
            .accessibilityIdentifier("receipt.action.restore")
        } else {
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

private struct ReceiptFilterStrip: View {
    @Binding var groupFilter: ReceiptListGroupFilter
    var groups: [ExpenseGroup]
    @Binding var typeFilter: String?
    @Binding var paymentFilter: PaymentMethod?
    @Binding var hasPhotoOnly: Bool
    var typeFilterCategories: [FolderCategory]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasActiveFilters == false {
                    ReceiptFilterChip(title: String(localized: "filter.all"), isSelected: false)
                }
                if groupFilter != .all {
                    ReceiptFilterChip(title: groupFilterTitle, isSelected: true) {
                        groupFilter = .all
                    }
                }
                if let typeFilter {
                    ReceiptFilterChip(title: typeFilterName(typeFilter), isSelected: true) {
                        self.typeFilter = nil
                    }
                }
                if let paymentFilter {
                    ReceiptFilterChip(title: ExpenseFormatters.paymentName(paymentFilter), isSelected: true) {
                        self.paymentFilter = nil
                    }
                }
                if hasPhotoOnly {
                    ReceiptFilterChip(title: String(localized: "filter.hasPhoto"), isSelected: true) {
                        hasPhotoOnly = false
                    }
                }
                Menu {
                    Section("filter.group.section") {
                        Button("filter.allGroups") { groupFilter = .all }
                        Button("groups.unfiled.title") { groupFilter = .unfiled }
                        ForEach(groups) { group in
                            Button(group.name) { groupFilter = .group(group.persistentModelID) }
                        }
                    }
                    Section("filter.type.section") {
                        Button("filter.allTypes") { typeFilter = nil }
                        ForEach(typeFilterCategories) { category in
                            Button(category.displayName) { typeFilter = category.id }
                        }
                    }
                    Section("filter.payment.section") {
                        Button("filter.allPayments") { paymentFilter = nil }
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Button(ExpenseFormatters.paymentName(method)) { paymentFilter = method }
                        }
                    }
                    Section("filter.photo.section") {
                        Button("filter.hasPhoto") { hasPhotoOnly = true }
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

    private var hasActiveFilters: Bool {
        groupFilter != .all || typeFilter != nil || paymentFilter != nil || hasPhotoOnly
    }

    private func typeFilterName(_ id: String) -> String {
        typeFilterCategories.first { $0.id == id }?.displayName
            ?? CategoryResolver.category(forID: id, in: nil).displayName
    }

    private var groupFilterTitle: String {
        switch groupFilter {
        case .all:
            String(localized: "filter.allGroups")
        case .unfiled:
            String(localized: "groups.unfiled.title")
        case .group(let id):
            groups.first { $0.persistentModelID == id }?.name ?? String(localized: "filter.group")
        }
    }
}

private struct ReceiptFilterChip: View {
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

struct ReceiptRow: View {
    var receipt: Receipt

    var body: some View {
        let category = receipt.resolvedCategory
        #if os(macOS)
        HStack(spacing: 10) {
            ReceiptThumbnail(receipt: receipt)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.vendor.isEmpty ? String(localized: "receipt.manual.vendor") : receipt.vendor)
                    .contentScaledFont(.body.weight(.semibold))
                    .lineLimit(1)
                Text(receiptSubtitle)
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(ExpenseFormatters.money(receipt.totalAmount, currencyCode: receipt.currencyCode))
                .contentScaledFont(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
            Image(systemName: category.symbolName)
                .contentScaledFont(.caption.weight(.semibold))
                .foregroundStyle(category.color)
                .frame(width: 18, alignment: .trailing)
                .help(category.displayName)
        }
        .accessibilityElement(children: .combine)
        #else
        HStack(spacing: 12) {
            ReceiptThumbnail(receipt: receipt)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.vendor.isEmpty ? String(localized: "receipt.manual.vendor") : receipt.vendor)
                    .contentScaledFont(.body.weight(.semibold))
                Text(receiptSubtitle)
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
                if receipt.isArchived {
                    Label("receipt.archived.badge", systemImage: "archivebox")
                        .contentScaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ExpenseFormatters.money(receipt.totalAmount, currencyCode: receipt.currencyCode))
                    .contentScaledFont(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Label(category.displayName, systemImage: category.symbolName)
                    .contentScaledFont(.caption.weight(.semibold))
                    .foregroundStyle(category.color)
            }
            .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        #endif
    }

    private var receiptSubtitle: String {
        String.localizedStringWithFormat(
            String(localized: "receipt.row.subtitle"),
            ExpenseFormatters.date(receipt.date),
            receipt.group?.name ?? String(localized: "groups.unfiled.title")
        )
    }
}

private struct ReceiptThumbnail: View {
    var receipt: Receipt
    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var thumbnailSize = 34
    #else
    @ScaledMetric(relativeTo: .body) private var thumbnailSize = 44
    #endif

    var body: some View {
        if let data = receipt.attachments?.sorted(by: { $0.pageIndex < $1.pageIndex }).first?.thumbnailData ?? receipt.attachments?.first?.imageData,
           let image = ReceiptPlatformImage.receiptImage(data: data) {
            Image(receiptImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            let category = receipt.resolvedCategory
            Image(systemName: category.symbolName)
                .imageScale(.medium)
                .foregroundStyle(.white)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .background(category.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

@MainActor
@Observable
final class ReceiptDetailAmountEditor {
    private let receipt: Receipt
    private let locale: Locale

    var amountText: String {
        didSet {
            applyAmountText()
        }
    }
    private(set) var validationMessageKey: String?

    init(receipt: Receipt, locale: Locale = .current) {
        self.receipt = receipt
        self.locale = locale
        self.amountText = Self.formatAmount(receipt.totalAmount, locale: locale)
    }

    func resetFromReceipt() {
        amountText = Self.formatAmount(receipt.totalAmount, locale: locale)
        validationMessageKey = nil
    }

    private func applyAmountText() {
        guard let amount = AmountInputParser.parse(amountText, locale: locale) else {
            validationMessageKey = "receipt.amount.invalid"
            return
        }
        receipt.totalAmount = amount
        validationMessageKey = nil
    }

    private static func formatAmount(_ amount: Decimal, locale: Locale) -> String {
        amount.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(2))
        )
    }
}

struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExpenseGroup.name) private var groups: [ExpenseGroup]
    @Bindable var receipt: Receipt
    var onAddPhoto: (Receipt) -> Void = { _ in }

    @State private var amountText = ""
    @State private var amountEditor: ReceiptDetailAmountEditor?
    @State private var showDeleteConfirm = false
    @State private var isShowingImageViewer = false
    @State private var imageViewerPage = 0

    var body: some View {
        Form {
            Section {
                if sortedAttachments.isEmpty == false {
                    TabView {
                        ForEach(sortedAttachments.indices, id: \.self) { index in
                            let attachment = sortedAttachments[index]
                            if let image = ReceiptPlatformImage.receiptImage(data: attachment.imageData) {
                                Button {
                                    imageViewerPage = index
                                    isShowingImageViewer = true
                                } label: {
                                    Image(receiptImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "magnifyingglass")
                                                .contentScaledFont(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(8)
                                                .background(.thinMaterial, in: Circle())
                                                .padding(10)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("review.image.open.accessibility"))
                                .accessibilityIdentifier("receipt.image.open")
                            }
                        }
                    }
                    .frame(minHeight: 260)
                    .receiptPageTabViewStyle()
                } else {
                    Button("receipt.detail.addPhoto") {
                        onAddPhoto(receipt)
                    }
                }
            }

            Section("review.section.fields") {
                TextField("receipt.field.vendor", text: $receipt.vendor)
                ConfirmedDatePickerRow(
                    "receipt.field.date",
                    selection: $receipt.date,
                    accessibilityIdentifier: "receipt.detail.date"
                )
                TextField("receipt.field.amount", text: Binding(
                    get: { amountEditor?.amountText ?? amountText },
                    set: { newValue in
                        amountText = newValue
                        amountEditor?.amountText = newValue
                    }
                ))
                .receiptDecimalInputKeyboard()
                if let validationMessageKey = amountEditor?.validationMessageKey {
                    Text(LocalizedStringKey(validationMessageKey))
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                CurrencyPickerRow(
                    title: "receipt.field.currency",
                    selectedCode: $receipt.currencyCode,
                    accessibilityIdentifier: "receipt.currency.row"
                )
                CategorySelector(
                    categories: detailVisibleCategories,
                    selection: Binding(
                        get: { receipt.categoryID },
                        set: { receipt.categoryID = $0 ?? receipt.categoryID }
                    ),
                    currentOutOfSet: detailCurrentOutOfSetCategory
                )
                Picker("receipt.field.payment", selection: $receipt.paymentMethod) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        Text(ExpenseFormatters.paymentName(method)).tag(method)
                    }
                }
                Menu {
                    Button("groups.unfiled.title") { receipt.group = nil }
                    ForEach(assignableGroups) { group in
                        Button(group.name) {
                            receipt.group = group
                            var groupReceipts = group.receipts ?? []
                            if groupReceipts.contains(where: { $0.persistentModelID == receipt.persistentModelID }) == false {
                                groupReceipts.append(receipt)
                            }
                            group.receipts = groupReceipts
                        }
                    }
                } label: {
                    HStack {
                        Text("receipt.field.group")
                        Spacer()
                        Text(receipt.group?.name ?? String(localized: "groups.unfiled.title"))
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("receipt.field.notes", text: Binding(
                    get: { receipt.notes ?? "" },
                    set: { receipt.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
            }

            if let extraction = receipt.extraction {
                Section {
                    if extraction.isAgentEntry {
                        Label("receipt.provenance.agentEntry", systemImage: "person.crop.circle.badge.checkmark")
                            .contentScaledFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = ModelOutputAuditSummary(json: extraction.modelOutputJSON) {
                        ExtractionDiagnosticsDisclosure(summary: summary)
                    }
                    DisclosureGroup("receipt.detail.provenance") {
                        Text(extraction.rawOCRText.isEmpty ? String(localized: "receipt.detail.noOCR") : extraction.rawOCRText)
                            .contentScaledFont(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                if receipt.isArchived {
                    Button {
                        try? ReceiptStore.restore(receipt, in: modelContext)
                        dismiss()
                    } label: {
                        Label("receipt.restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(Color("LedgerGreen"))
                    .accessibilityIdentifier("receipt.action.restore")
                    if let archivedAt = receipt.archivedAt {
                        Text(String.localizedStringWithFormat(String(localized: "receipt.archived.on"), archivedAt.formatted(date: .abbreviated, time: .omitted)))
                            .contentScaledFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        try? ReceiptStore.archive(receipt, in: modelContext)
                        dismiss()
                    } label: {
                        Label("receipt.archive", systemImage: "archivebox")
                    }
                    .tint(Color("LedgerGreen"))
                    .accessibilityIdentifier("receipt.action.archive")
                }
            }

            Section {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("common.delete", systemImage: "trash")
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(receipt.vendor.isEmpty ? String(localized: "receipt.detail.title") : receipt.vendor)
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingImageViewer) {
            ReceiptImageViewer(pages: attachmentImageDatas, initialPage: imageViewerPage)
        }
        #elseif os(macOS)
        .sheet(isPresented: $isShowingImageViewer) {
            ReceiptImageViewer(pages: attachmentImageDatas, initialPage: imageViewerPage)
        }
        #endif
        .onAppear {
            if amountEditor == nil {
                amountEditor = ReceiptDetailAmountEditor(receipt: receipt)
            }
            amountEditor?.resetFromReceipt()
            amountText = amountEditor?.amountText ?? NSDecimalNumber(decimal: receipt.totalAmount).stringValue
        }
        .onDisappear { try? modelContext.save() }
        .confirmationDialog("receipt.delete.title", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("common.delete") {
                modelContext.delete(receipt)
                try? modelContext.save()
            }
        }
    }

    private var sortedAttachments: [ReceiptAttachment] {
        (receipt.attachments ?? []).sorted { $0.pageIndex < $1.pageIndex }
    }

    private var attachmentImageDatas: [Data] {
        sortedAttachments.map(\.imageData)
    }

    private var assignableGroups: [ExpenseGroup] {
        groups.filter { group in
            group.isArchived == false || group.persistentModelID == receipt.group?.persistentModelID
        }
    }

    /// Category set for the receipt's assigned folder; the Unfiled default set when unfiled (SPEC §7).
    private var detailVisibleCategories: [FolderCategory] {
        receipt.group?.visibleCategories ?? FolderCategorySnapshot.unfiledDefault.categories
    }

    /// When the receipt's category is not visible in its folder (e.g. after moving folders), surface
    /// it as a "Current" chip marked for attention so the user can reassign inline (SPEC §7).
    private var detailCurrentOutOfSetCategory: FolderCategory? {
        guard detailVisibleCategories.contains(where: { $0.id == receipt.categoryID }) == false else {
            return nil
        }
        return receipt.resolvedCategory
    }
}
