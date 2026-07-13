import ExpenseCore
import SwiftData
import SwiftUI

private enum ReviewFocusedField: Hashable {
    case vendor
    case amount
    case notes
}

private enum ReviewScrollTarget: Hashable {
    case amount
    case currency
    case expenseType
    case paymentMethod
}

struct ReceiptReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseGroup.name) private var groups: [ExpenseGroup]

    @Bindable var form: ReceiptReviewForm
    var onSaved: () -> Void
    @State private var selectedGroup: ExpenseGroup?
    @State private var initialSelectedGroupID: PersistentIdentifier?
    @State private var showRawText = false
    @State private var showSaveError = false
    @State private var showDiscardConfirmation = false
    @State private var showMissingSaveFields = false
    @State private var saveFeedbackTrigger = 0
    @FocusState private var focusedField: ReviewFocusedField?

    init(form: ReceiptReviewForm, defaultGroup: ExpenseGroup?, onSaved: @escaping () -> Void) {
        self.form = form
        self.onSaved = onSaved
        _selectedGroup = State(initialValue: defaultGroup)
        _initialSelectedGroupID = State(initialValue: defaultGroup?.persistentModelID)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            List {
                if form.pageImageDatas.isEmpty == false {
                    Section {
                        ReceiptReviewImageHeader(form: form)
                    }
                }
                if let notice = form.notice {
                    Section {
                        NoticeBanner(notice: notice)
                    }
                }
                DuplicateNotice(form: form)
                Section("review.section.fields") {
                    ChoiceTextField(
                        title: "receipt.field.vendor",
                        text: $form.vendor,
                        choices: form.vendorChoices,
                        formatter: { $0 },
                        choose: form.chooseVendor,
                        isSelected: { form.isVendorChoiceSelected($0) },
                        identifierPrefix: "review.choice.vendor",
                        focusedField: $focusedField,
                        focusValue: .vendor
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        ConfirmedDatePickerRow(
                            "receipt.field.date",
                            selection: $form.date,
                            accessibilityIdentifier: "review.date"
                        )
                        ChoiceChips(
                            choices: form.dateChoices,
                            formatter: ExpenseFormatters.date,
                            choose: form.chooseDate,
                            isSelected: { form.isDateChoiceSelected($0) },
                            identifierPrefix: "review.choice.date"
                        )
                    }
                    .attentionFieldEdge(needsAttention(form.dateChoices, isSelected: form.isDateChoiceSelected))
                    ChoiceTextField(
                        title: "receipt.field.amount",
                        text: $form.amountText,
                        choices: form.totalAmountChoices,
                        formatter: { ExpenseFormatters.money($0, currencyCode: form.currencyCode) },
                        choose: form.chooseTotalAmount,
                        isSelected: { form.isTotalAmountChoiceSelected($0) },
                        identifierPrefix: "review.choice.totalAmount",
                        focusedField: $focusedField,
                        focusValue: .amount
                    )
                    .receiptDecimalInputKeyboard()
                    .id(ReviewScrollTarget.amount)
                    VStack(alignment: .leading, spacing: 8) {
                        CurrencyPickerRow(
                            title: "receipt.field.currency",
                            selectedCode: $form.currencyCode,
                            accessibilityIdentifier: "review.currency.row"
                        )
                        ChoiceChips(
                            choices: form.currencyChoices,
                            formatter: { $0.uppercased() },
                            choose: form.chooseCurrency,
                            isSelected: { form.isCurrencyChoiceSelected($0) },
                            identifierPrefix: "review.choice.currency"
                        )
                    }
                    .attentionFieldEdge(needsAttention(form.currencyChoices, isSelected: form.isCurrencyChoiceSelected))
                    .id(ReviewScrollTarget.currency)
                    VStack(alignment: .leading, spacing: 8) {
                        CategorySelector(
                            categories: visibleCategories,
                            selection: $form.categoryID,
                            currentOutOfSet: currentOutOfSetCategory
                        )
                        ChoiceChips(
                            choices: form.categoryChoices,
                            formatter: categoryChoiceName,
                            choose: form.chooseCategory,
                            isSelected: { form.isCategoryChoiceSelected($0) },
                            identifierPrefix: "review.choice.category"
                        )
                    }
                    .attentionFieldEdge(currentOutOfSetCategory != nil || needsAttention(form.categoryChoices, isSelected: form.isCategoryChoiceSelected))
                    .id(ReviewScrollTarget.expenseType)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("receipt.field.payment", selection: Binding(
                            get: { form.paymentMethod ?? .card },
                            set: { form.paymentMethod = $0 }
                        )) {
                            ForEach(PaymentMethod.allCases, id: \.self) { method in
                                Text(ExpenseFormatters.paymentName(method)).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        ChoiceChips(
                            choices: form.paymentMethodChoices,
                            formatter: ExpenseFormatters.paymentName,
                            choose: form.choosePaymentMethod,
                            isSelected: { form.isPaymentMethodChoiceSelected($0) },
                            identifierPrefix: "review.choice.paymentMethod"
                        )
                    }
                    .attentionFieldEdge(needsAttention(form.paymentMethodChoices, isSelected: form.isPaymentMethodChoiceSelected))
                    .id(ReviewScrollTarget.paymentMethod)
                    Menu {
                        Button("groups.unfiled.title") { selectedGroup = nil }
                        ForEach(selectableGroups) { group in
                            Button(group.name) { selectedGroup = group }
                        }
                    } label: {
                        HStack {
                            Text("receipt.field.group")
                            Spacer()
                            Text(selectedGroup?.name ?? String(localized: "groups.unfiled.title"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("review.group.row")
                    TextField("receipt.field.notes", text: $form.notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                }
                Section {
                    if let summary = form.modelAuditSummary {
                        ExtractionDiagnosticsDisclosure(summary: summary)
                    }
                    DisclosureGroup("receipt.detail.provenance", isExpanded: $showRawText) {
                        Text(form.provenanceText.isEmpty ? String(localized: "receipt.detail.noOCR") : form.provenanceText)
                            .contentScaledFont(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("review.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        requestDiscard()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(cancelActionTitle))
                    .accessibilityIdentifier("review.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        focusedField = nil
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) {
                if focusedField == nil {
                    saveBar(scrollProxy: scrollProxy)
                }
            }
            .animation(.default, value: focusedField)
            .onDisappear {
                form.discardIfUnsaved(in: modelContext)
            }
            .onChange(of: form.canSave) { _, canSave in
                if canSave {
                    showMissingSaveFields = false
                }
            }
            .onChange(of: form.categoryID) { _, _ in
                focusedField = nil
            }
            .onChange(of: form.paymentMethod) { _, _ in
                focusedField = nil
            }
            .alert("review.save.error", isPresented: $showSaveError) {
                Button("common.ok", role: .cancel) {}
            }
            .alert("review.discard.title", isPresented: $showDiscardConfirmation) {
                Button("common.discard") {
                    discardAndDismiss()
                }
                Button("common.cancel", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
        }
    }

    private func saveBar(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if showMissingSaveFields, form.canSave == false {
                Text(missingSaveMessage)
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("review.save.missing")
            }
            Button {
                saveOrShowMissingFields(scrollProxy: scrollProxy)
            } label: {
                Text("common.save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color("LedgerGreen"))
            .controlSize(.large)
            .opacity(form.canSave ? 1 : 0.6)
            .accessibilityIdentifier("review.save")
            .accessibilityHint(form.canSave ? Text("") : Text(missingSaveMessage))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func saveOrShowMissingFields(scrollProxy: ScrollViewProxy) {
        guard form.canSave else {
            showMissingSaveFields = true
            if let firstMissingRequiredFieldTarget {
                withAnimation {
                    scrollProxy.scrollTo(firstMissingRequiredFieldTarget, anchor: .center)
                }
            }
            return
        }
        save()
    }

    private func save() {
        do {
            _ = try form.save(in: modelContext, group: selectedGroup)
            saveFeedbackTrigger += 1
            onSaved()
            dismiss()
        } catch {
            showSaveError = true
        }
    }

    private var firstMissingRequiredFieldTarget: ReviewScrollTarget? {
        if form.parsedAmount == nil {
            return .amount
        }
        if form.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .currency
        }
        if form.categoryID == nil {
            return .expenseType
        }
        if form.paymentMethod == nil {
            return .paymentMethod
        }
        return nil
    }

    private var selectableGroups: [ExpenseGroup] {
        groups.filter { group in
            group.isArchived == false || group.persistentModelID == selectedGroup?.persistentModelID
        }
    }

    /// The category set the selector offers: the chosen folder's visible categories, or the compact
    /// Unfiled default set when no folder is selected (SPEC §D6).
    private var visibleCategories: [FolderCategory] {
        selectedGroup?.visibleCategories ?? FolderCategorySnapshot.unfiledDefault.categories
    }

    /// The current category when it is not part of the selected folder's set, shown as a "Current"
    /// chip that marks the field for attention (SPEC §D6).
    private var currentOutOfSetCategory: FolderCategory? {
        guard let id = form.categoryID,
              visibleCategories.contains(where: { $0.id == id }) == false else {
            return nil
        }
        return CategoryResolver.category(forID: id, in: selectedGroup?.categorySnapshot)
    }

    private func categoryChoiceName(_ id: String) -> String {
        (visibleCategories.first { $0.id == id }
            ?? CategoryResolver.category(forID: id, in: selectedGroup?.categorySnapshot)).displayName
    }

    private var isDirty: Bool {
        form.isDirty || selectedGroup?.persistentModelID != initialSelectedGroupID
    }

    private var missingSaveMessage: String {
        let fieldList = form.missingRequiredFieldKeys
            .map { String(localized: String.LocalizationValue($0)) }
            .joined(separator: String(localized: "list.separator"))
        return String.localizedStringWithFormat(String(localized: "review.save.missing"), fieldList)
    }

    private var cancelActionTitle: LocalizedStringKey {
        form.preservesPendingDraftOnDiscard ? "common.cancel" : "common.discard"
    }

    private func requestDiscard() {
        if isDirty {
            showDiscardConfirmation = true
        } else {
            discardAndDismiss()
        }
    }

    private func discardAndDismiss() {
        form.discardIfUnsaved(in: modelContext)
        dismiss()
    }

    private func needsAttention<Value: Equatable>(
        _ choices: [ReceiptFieldChoice<Value>],
        isSelected: (ReceiptFieldChoice<Value>) -> Bool
    ) -> Bool {
        choices.count > 1 && choices.contains(where: isSelected) == false
    }
}

struct ExtractionDiagnosticsDisclosure: View {
    var summary: ModelOutputAuditSummary
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("receipt.diagnostic.title", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    summary.imageInputUsed ? "receipt.diagnostic.imageInput" : "receipt.diagnostic.textInput",
                    systemImage: summary.imageInputUsed ? "photo.badge.checkmark" : "text.document"
                )
                LabeledContent("receipt.diagnostic.attachments", value: summary.attachmentCount.formatted())
                LabeledContent("receipt.diagnostic.attempts", value: summary.attemptCount.formatted())
                if let longEdge = summary.attachmentLongEdges.max() {
                    LabeledContent(
                        "receipt.diagnostic.imageSize",
                        value: String.localizedStringWithFormat(
                            String(localized: "receipt.diagnostic.longEdge.format"),
                            longEdge
                        )
                    )
                }
                ForEach(summary.acceptance, id: \.field) { acceptance in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(acceptance.field.localizedName)
                            .fontWeight(.medium)
                        if let primary = acceptance.primary {
                            LabeledContent("receipt.diagnostic.primary", value: primary.localizedName)
                        }
                        if let alternate = acceptance.alternate {
                            LabeledContent("receipt.diagnostic.alternate", value: alternate.localizedName)
                        }
                    }
                }
            }
            .contentScaledFont(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("receipt.diagnostic.disclosure")
    }
}

private extension ModelOutputAuditSummary.Field {
    var localizedName: String {
        switch self {
        case .vendor: String(localized: "receipt.field.vendor")
        case .date: String(localized: "receipt.field.date")
        case .totalAmount: String(localized: "receipt.field.amount")
        case .currencyCode: String(localized: "receipt.field.currency")
        case .paymentMethod: String(localized: "receipt.field.payment")
        case .expenseType: String(localized: "receipt.field.expenseType")
        }
    }
}

private extension ModelOutputAuditSummary.Tier {
    var localizedName: String {
        switch self {
        case .evidenceSupported: String(localized: "receipt.diagnostic.tier.evidenceSupported")
        case .imageGrounded: String(localized: "receipt.diagnostic.tier.imageGrounded")
        case .rejected: String(localized: "receipt.diagnostic.tier.rejected")
        }
    }
}

private struct ReceiptReviewImageHeader: View {
    var form: ReceiptReviewForm
    @State private var isShowingImageViewer = false

    var body: some View {
        Button {
            isShowingImageViewer = true
        } label: {
            headerContent
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .contentScaledFont(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                        .padding(10)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review.image.open")
        .accessibilityLabel(Text("review.image.open.accessibility"))
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingImageViewer) {
            ReceiptImageViewer(pages: form.pageImageDatas, initialPage: 0)
        }
        #elseif os(macOS)
        .sheet(isPresented: $isShowingImageViewer) {
            ReceiptImageViewer(pages: form.pageImageDatas, initialPage: 0)
        }
        #endif
    }

    private var headerContent: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .frame(minHeight: 160)
            if let data = form.fullImageData(at: 0), let image = ReceiptPlatformImage.receiptImage(data: data) {
                Image(receiptImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if form.pageCount > 0 {
                Text(String.localizedStringWithFormat(String(localized: "review.page.count"), form.pageCount))
                    .contentScaledFont(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .accessibilityLabel(Text("receipt.image.accessibility"))
    }
}

private struct NoticeBanner: View {
    var notice: ReceiptProcessingNotice

    var body: some View {
        Label(messageKey, systemImage: "info.circle")
            .contentScaledFont(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private var messageKey: LocalizedStringKey {
        switch notice {
        case .smartExtractionPreparing: "notice.modelPreparing"
        case .smartExtractionTimedOut: "notice.modelTimedOut"
        case .unsupportedReceiptLanguage: "notice.unsupportedLanguage"
        case .smartExtractionUnavailable: "notice.modelUnavailable"
        case .noReceiptTextFound: "notice.noText"
        }
    }
}

private struct DuplicateNotice: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    var form: ReceiptReviewForm
    @State private var warningFeedbackTrigger = 0
    @State private var receiptToPeek: Receipt?
    @State private var isShowingReceiptPeek = false

    var body: some View {
        if let duplicateReceipt {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color("DuplicateBannerText"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("review.duplicate.notice")
                            .contentScaledFont(.footnote.weight(.semibold))
                        Text(duplicateDetail(for: duplicateReceipt))
                            .contentScaledFont(.caption)
                            .foregroundStyle(Color("DuplicateBannerText").opacity(0.82))
                    }
                    Spacer()
                    Button("review.duplicate.view") {
                        receiptToPeek = duplicateReceipt
                        isShowingReceiptPeek = true
                    }
                    .contentScaledFont(.footnote.weight(.semibold))
                    .foregroundStyle(Color("LedgerGreen"))
                    .accessibilityIdentifier("review.duplicate.view")
                }
                .foregroundStyle(Color("DuplicateBannerText"))
                .padding(12)
                .background(Color("DuplicateBannerBackground"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear {
                    if warningFeedbackTrigger == 0 {
                        warningFeedbackTrigger = 1
                    }
                }
                .sensoryFeedback(.warning, trigger: warningFeedbackTrigger)
            }
            .sheet(isPresented: $isShowingReceiptPeek) {
                if let receiptToPeek {
                    NavigationStack {
                        ReceiptDetailView(receipt: receiptToPeek)
                    }
                }
            }
        }
    }

    private var duplicateReceipt: Receipt? {
        guard let amount = form.parsedAmount else { return nil }
        return receipts.first { receipt in
            receipt.vendor.caseInsensitiveCompare(form.vendor) == .orderedSame
                && Calendar.current.isDate(receipt.date, inSameDayAs: form.date)
                && receipt.totalAmount == amount
                && receipt.currencyCode.uppercased() == form.currencyCode.uppercased()
        }
    }

    private func duplicateDetail(for receipt: Receipt) -> String {
        String.localizedStringWithFormat(
            String(localized: "review.duplicate.detail"),
            receipt.vendor,
            ExpenseFormatters.date(receipt.date),
            ExpenseFormatters.money(receipt.totalAmount, currencyCode: receipt.currencyCode)
        )
    }
}

private struct ChoiceTextField<Value: Equatable>: View {
    var title: LocalizedStringKey
    @Binding var text: String
    var choices: [ReceiptFieldChoice<Value>]
    var formatter: (Value) -> String
    var choose: (ReceiptFieldChoice<Value>) -> Void
    var isSelected: (ReceiptFieldChoice<Value>) -> Bool
    var identifierPrefix: String
    var focusedField: FocusState<ReviewFocusedField?>.Binding
    var focusValue: ReviewFocusedField

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(title, text: $text)
                .focused(focusedField, equals: focusValue)
            ChoiceChips(
                choices: choices,
                formatter: formatter,
                choose: choose,
                isSelected: isSelected,
                identifierPrefix: identifierPrefix
            )
        }
        .attentionFieldEdge(choices.count > 1 && choices.contains(where: isSelected) == false)
    }
}

private extension View {
    func attentionFieldEdge(_ isActive: Bool) -> some View {
        modifier(AttentionFieldEdgeModifier(isActive: isActive))
    }
}

private struct AttentionFieldEdgeModifier: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, isActive ? 9 : 0)
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color("AttentionFieldEdge"))
                        .frame(width: 2.5)
                        .padding(.vertical, 3)
                }
            }
    }
}

private struct ChoiceChips<Value: Equatable>: View {
    var choices: [ReceiptFieldChoice<Value>]
    var formatter: (Value) -> String
    var choose: (ReceiptFieldChoice<Value>) -> Void
    var isSelected: (ReceiptFieldChoice<Value>) -> Bool
    var identifierPrefix: String
    @State private var selectionFeedbackTrigger = 0

    var body: some View {
        if choices.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                prompt
                HStack(spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                        let selected = isSelected(choice)
                        Button {
                            choose(choice)
                            selectionFeedbackTrigger += 1
                        } label: {
                            choiceLabel(choice, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(formatter(choice.value)))
                        .accessibilityValue(Text(choice.reason ?? ""))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("\(identifierPrefix).\(index)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
        }
    }

    @ViewBuilder
    private var prompt: some View {
        if choices.contains(where: isSelected) {
            Label("review.choice.confirmed", systemImage: "checkmark.circle.fill")
                .contentScaledFont(.caption.weight(.semibold))
                .foregroundStyle(Color("LedgerGreen"))
        } else {
            Text("review.choice.prompt")
                .contentScaledFont(.caption.weight(.semibold))
                .foregroundStyle(Color("AttentionFieldEdge"))
        }
    }

    private func choiceLabel(_ choice: ReceiptFieldChoice<Value>, selected: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .contentScaledFont(.caption)
                }
                Text(formatter(choice.value))
                    .contentScaledFont(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? Color("LedgerGreen") : Color.primary)

            if let reason = choice.reason {
                Text(reason)
                    .contentScaledFont(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Color("LedgerGreenSoft") : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(selected ? Color("LedgerGreen") : Color.secondary.opacity(0.25), lineWidth: 1.5)
        )
    }
}
