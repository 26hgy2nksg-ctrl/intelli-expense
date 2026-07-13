#if os(macOS)
import ExpenseCore
import SwiftData
import SwiftUI

struct MacReceiptDetailPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseGroup.name) private var groups: [ExpenseGroup]
    @Bindable var receipt: Receipt
    var onAddPhoto: (Receipt) -> Void
    var onRemovedFromCurrentList: () -> Void

    @State private var amountText = ""
    @State private var amountEditor: ReceiptDetailAmountEditor?
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            MacReceiptImageColumn(imageDatas: attachmentImageDatas) {
                ReceiptTypePlaceholder(receipt: receipt)
            }
            .frame(minWidth: 320, idealWidth: 440, maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                MacReceiptDetailHero(receipt: receipt)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)
                Form {
                    fieldsSection
                    provenanceSection
                    archiveFootnoteSection
                }
                .formStyle(.grouped)
            }
            .frame(minWidth: 360, idealWidth: 440)
        }
        .navigationTitle(receipt.vendor.isEmpty ? String(localized: "receipt.detail.title") : receipt.vendor)
        .toolbar {
            if sortedAttachments.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onAddPhoto(receipt)
                    } label: {
                        Label("receipt.detail.addPhoto.toolbar", systemImage: "photo.badge.plus")
                    }
                    .accessibilityIdentifier("mac.detail.toolbar.addPhoto")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if receipt.isArchived {
                    Button {
                        restoreReceipt()
                    } label: {
                        Label("receipt.restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(Color("LedgerGreen"))
                    .accessibilityIdentifier("mac.detail.toolbar.restore")
                } else {
                    Button {
                        archiveReceipt()
                    } label: {
                        Label("receipt.archive", systemImage: "archivebox")
                    }
                    .tint(Color("LedgerGreen"))
                    .accessibilityIdentifier("mac.detail.toolbar.archive")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("common.delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("mac.detail.toolbar.delete")
                } label: {
                    Label("common.edit", systemImage: "ellipsis.circle")
                }
            }
        }
        .onChange(of: receipt.persistentModelID, initial: true) {
            let editor = ReceiptDetailAmountEditor(receipt: receipt)
            amountEditor = editor
            amountText = editor.amountText
        }
        .onDisappear {
            try? modelContext.save()
        }
        .confirmationDialog("receipt.delete.title", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                deleteReceipt()
            }
            Button("common.cancel", role: .cancel) {}
        }
    }

    private var fieldsSection: some View {
        Section("review.section.fields") {
            TextField("receipt.field.vendor", text: $receipt.vendor)
            DatePicker("receipt.field.date", selection: $receipt.date, displayedComponents: .date)
            TextField("receipt.field.amount", text: Binding(
                get: { amountEditor?.amountText ?? amountText },
                set: { newValue in
                    amountText = newValue
                    amountEditor?.amountText = newValue
                }
            ))
            .accessibilityIdentifier("mac.detail.amount")
            if let validationMessageKey = amountEditor?.validationMessageKey {
                Text(LocalizedStringKey(validationMessageKey))
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            CurrencyPickerRow(
                title: "receipt.field.currency",
                selectedCode: $receipt.currencyCode,
                accessibilityIdentifier: "mac.detail.currency.row"
            )
            Picker("receipt.field.type", selection: Binding(
                get: { receipt.categoryID },
                set: { receipt.categoryID = $0 }
            )) {
                ForEach(detailCategories) { category in
                    HStack(spacing: 8) {
                        CategoryGlyph(category: category, size: 20, cornerRadius: 5)
                        Text(category.displayName)
                    }
                    .tag(category.id)
                }
            }
            Picker("receipt.field.payment", selection: $receipt.paymentMethod) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Text(ExpenseFormatters.paymentName(method)).tag(method)
                }
            }
            Menu {
                Button("groups.unfiled.title") { receipt.group = nil }
                ForEach(assignableGroups) { group in
                    Button(group.name) {
                        assign(receipt, to: group)
                    }
                }
            } label: {
                LabeledContent("receipt.field.group", value: receipt.group?.name ?? String(localized: "groups.unfiled.title"))
            }
            TextField("receipt.field.notes", text: Binding(
                get: { receipt.notes ?? "" },
                set: { receipt.notes = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
        }
    }

    @ViewBuilder
    private var provenanceSection: some View {
        if let extraction = receipt.extraction {
            Section {
                if extraction.isAgentEntry {
                    Label("receipt.provenance.agentEntry", systemImage: "person.crop.circle.badge.checkmark")
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("receipt.detail.provenance") {
                    Text(extraction.rawOCRText.isEmpty ? String(localized: "receipt.detail.noOCR") : extraction.rawOCRText)
                        .contentScaledFont(.footnote)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var archiveFootnoteSection: some View {
        if receipt.isArchived, let archivedAt = receipt.archivedAt {
            Section {
                Text(String.localizedStringWithFormat(String(localized: "receipt.archived.on"), archivedAt.formatted(date: .abbreviated, time: .omitted)))
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
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

    /// Folder-scoped category options for the Mac detail picker, including the current category when
    /// it falls outside the folder's visible set (SPEC §7).
    private var detailCategories: [FolderCategory] {
        let base = receipt.group?.visibleCategories ?? FolderCategorySnapshot.unfiledDefault.categories
        if base.contains(where: { $0.id == receipt.categoryID }) == false {
            return [receipt.resolvedCategory] + base
        }
        return base
    }

    private func assign(_ receipt: Receipt, to group: ExpenseGroup) {
        receipt.group = group
        var groupReceipts = group.receipts ?? []
        if groupReceipts.contains(where: { $0.persistentModelID == receipt.persistentModelID }) == false {
            groupReceipts.append(receipt)
        }
        group.receipts = groupReceipts
    }

    private func archiveReceipt() {
        try? ReceiptStore.archive(receipt, in: modelContext)
        onRemovedFromCurrentList()
    }

    private func restoreReceipt() {
        try? ReceiptStore.restore(receipt, in: modelContext)
        onRemovedFromCurrentList()
    }

    private func deleteReceipt() {
        modelContext.delete(receipt)
        try? modelContext.save()
        onRemovedFromCurrentList()
    }
}

private struct MacReceiptDetailHero: View {
    var receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(receipt.vendor.isEmpty ? String(localized: "receipt.manual.vendor") : receipt.vendor)
                .contentScaledFont(.body.weight(.semibold))
                .lineLimit(2)
            Text(ExpenseFormatters.money(receipt.totalAmount, currencyCode: receipt.currencyCode))
                .contentScaledFont(.title.weight(.light))
                .monospacedDigit()
                .accessibilityIdentifier("mac.detail.hero.amount")
            Text(receiptMeta)
                .contentScaledFont(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var receiptMeta: String {
        [
            ExpenseFormatters.date(receipt.date),
            receipt.resolvedCategory.displayName,
            ExpenseFormatters.paymentName(receipt.paymentMethod)
        ]
        .joined(separator: String(localized: "metadata.separator"))
    }
}

private struct ReceiptTypePlaceholder: View {
    var receipt: Receipt

    var body: some View {
        let category = receipt.resolvedCategory
        VStack(spacing: 12) {
            Image(systemName: category.symbolName)
                .contentScaledFont(.largeTitle)
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(category.color, in: RoundedRectangle(cornerRadius: 16))
            Text(category.displayName)
                .contentScaledFont(.headline)
            Text("receipt.detail.addPhoto.toolbar")
                .contentScaledFont(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MacReceiptImageColumn<Placeholder: View>: View {
    var imageDatas: [Data]
    var placeholder: Placeholder

    @State private var selectedPage = 0
    @State private var isShowingImageViewer = false

    init(imageDatas: [Data], @ViewBuilder placeholder: () -> Placeholder) {
        self.imageDatas = imageDatas
        self.placeholder = placeholder()
    }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image = currentImage {
                    Button {
                        isShowingImageViewer = true
                    } label: {
                        Image(receiptImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("review.image.open.accessibility"))
                    .accessibilityIdentifier("receipt.image.open")
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if imageDatas.count > 1 {
                HStack(spacing: 12) {
                    Button {
                        selectedPage = max(0, selectedPage - 1)
                    } label: {
                        Label("receipt.pager.previous", systemImage: "chevron.left")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedPage == 0)
                    .accessibilityLabel(Text("receipt.pager.previous"))
                    .accessibilityIdentifier("mac.detail.pager.previous")

                    Text(pageIndicatorText)
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Button {
                        selectedPage = min(imageDatas.count - 1, selectedPage + 1)
                    } label: {
                        Label("receipt.pager.next", systemImage: "chevron.right")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedPage >= imageDatas.count - 1)
                    .accessibilityLabel(Text("receipt.pager.next"))
                    .accessibilityIdentifier("mac.detail.pager.next")
                }
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $isShowingImageViewer) {
            ReceiptImageViewer(pages: imageDatas, initialPage: selectedPage)
        }
        .onChange(of: imageDatas.count) { _, count in
            if selectedPage >= count {
                selectedPage = max(0, count - 1)
            }
        }
    }

    private var currentImage: ReceiptPlatformImage? {
        guard imageDatas.indices.contains(selectedPage) else { return nil }
        return ReceiptPlatformImage.receiptImage(data: imageDatas[selectedPage])
    }

    private var pageIndicatorText: String {
        String.localizedStringWithFormat(
            String(localized: "viewer.page.indicator"),
            selectedPage + 1,
            imageDatas.count
        )
    }
}
#endif
