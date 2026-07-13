import ExpenseCore
import SwiftData
import SwiftUI

// MARK: - Composer model

/// Working state for the Create/Edit folder category composer (SPEC §D4/§D5). Holds the ordered
/// visible set, tracks whether the user has manually edited it (so a profile switch knows whether to
/// ask before replacing), and enforces the Other-last and nine-category invariants via
/// `FolderCategorySnapshot`.
@MainActor
@Observable
final class FolderCategoryComposerModel {
    private(set) var profileID: String
    private(set) var categories: [FolderCategory]
    private(set) var hasUserEditedCategories = false
    private(set) var usedCategoryIDs: Set<String>
    let allowsProfileChange: Bool

    init(
        profileID: String,
        snapshot: FolderCategorySnapshot,
        usedCategoryIDs: Set<String> = [],
        allowsProfileChange: Bool
    ) {
        self.profileID = profileID
        self.categories = CustomCategory.healingGrayCustomCategories(in: snapshot.categories)
        self.usedCategoryIDs = usedCategoryIDs
        self.allowsProfileChange = allowsProfileChange
    }

    var profileForDisplay: String {
        (FolderProfileCatalog.profile(id: profileID) ?? FolderProfileCatalog.workTrip).displayName
    }

    var selectedNonOther: [FolderCategory] {
        categories.filter { $0.isOther == false }
    }

    var otherCategory: FolderCategory {
        categories.first { $0.isOther } ?? CategoryCatalog.otherFolderCategory
    }

    var selectedIDs: Set<String> {
        Set(categories.map(\.id))
    }

    /// Profile-specific add-ons not already selected (SPEC §D4). Empty for the Custom profile.
    var suggestions: [FolderCategory] {
        FolderProfileCatalog.suggestedCategories(forProfileID: profileID, excluding: selectedIDs)
    }

    var hasRoomForMore: Bool {
        categories.count < FolderCategorySnapshot.maximumVisibleCategories
    }

    /// Save requires a name (handled by the editor) and at least one non-Other category (SPEC §D4).
    var hasSelectableCategory: Bool {
        selectedNonOther.isEmpty == false
    }

    func snapshot() -> FolderCategorySnapshot {
        FolderCategorySnapshot(categories: categories)
    }

    func isUsedByReceipts(_ id: String) -> Bool {
        usedCategoryIDs.contains(id)
    }

    /// Adds a category (from suggestions, browse, or a custom definition) directly before Other.
    /// Returns `false` when the nine-category cap is reached.
    @discardableResult
    func add(_ category: FolderCategory) -> Bool {
        guard selectedIDs.contains(category.id) == false else { return true }
        guard hasRoomForMore else { return false }
        let categoryToAdd = CustomCategory.assigningAutoColor(to: category, avoiding: categories)
        var updated = categories
        let insertIndex = updated.firstIndex { $0.isOther } ?? updated.endIndex
        updated.insert(categoryToAdd, at: insertIndex)
        categories = FolderCategorySnapshot.normalized(updated)
        hasUserEditedCategories = true
        return true
    }

    enum RemoveOutcome: Equatable {
        case removed
        case blockedUsed
    }

    /// Attempts to remove a category. A category already used by receipts is blocked and must be
    /// reassigned first (SPEC §D5); an unused category is removed immediately.
    @discardableResult
    func attemptRemove(id: String) -> RemoveOutcome {
        guard id != CategoryCatalog.otherID else { return .blockedUsed }
        if isUsedByReceipts(id) {
            return .blockedUsed
        }
        remove(id: id)
        return .removed
    }

    /// Forcibly removes a category, used after its receipts have been reassigned away.
    func remove(id: String) {
        guard id != CategoryCatalog.otherID else { return }
        categories = FolderCategorySnapshot.normalized(categories.filter { $0.id != id })
        hasUserEditedCategories = true
    }

    func markReassigned(from id: String) {
        usedCategoryIDs.remove(id)
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = selectedNonOther
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        categories = FolderCategorySnapshot.normalized(reordered + [otherCategory])
        hasUserEditedCategories = true
    }

    func changeProfile(to newID: String, replaceCategories: Bool) {
        profileID = newID
        if replaceCategories {
            categories = FolderProfileCatalog.defaultSnapshot(forProfileID: newID).categories
            hasUserEditedCategories = false
        }
    }
}

// MARK: - Composer UI

/// The Categories card shown inside the Create/Edit folder sheet: selected categories (removable,
/// reorderable), profile suggestions, Browse Existing Categories, and Add Custom Category.
struct CategoryComposerSections: View {
    @Bindable var model: FolderCategoryComposerModel
    var receiptCount: (String) -> Int
    var onReassign: (FolderCategory, FolderCategory) -> Void

    @State private var isShowingBrowse = false
    @State private var isShowingAddCustom = false
    @State private var showCapReached = false
    @State private var reassignCategory: FolderCategory?
    @FocusState private var focusedAction: ComposerAction?

    var body: some View {
        Section {
            ForEach(model.selectedNonOther) { category in
                SelectedCategoryRow(category: category) {
                    handleRemove(category)
                }
            }
            .onMove { offsets, destination in
                model.move(fromOffsets: offsets, toOffset: destination)
            }
            LockedOtherRow(category: model.otherCategory)
        } header: {
            HStack {
                Text("folder.categories.title")
                Spacer()
                #if os(iOS)
                if model.selectedNonOther.count > 1 {
                    EditButton()
                        .contentScaledFont(.footnote)
                        .textCase(nil)
                }
                #endif
            }
        } footer: {
            Text("folder.categories.footer")
        }

        if model.suggestions.isEmpty == false {
            Section("folder.categories.suggestions") {
                CategorySuggestionFlow(suggestions: model.suggestions) { category in
                    addOrWarn(category)
                }
            }
        }

        Section {
            Button {
                isShowingBrowse = true
            } label: {
                Label("folder.categories.browse", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("folder.categories.browse")
            .focused($focusedAction, equals: .browse)
            .sheet(isPresented: $isShowingBrowse, onDismiss: restoreBrowseFocus) {
                BrowseCategoriesSheet(model: model) {
                    isShowingBrowse = false
                }
            }

            Button {
                isShowingAddCustom = true
            } label: {
                Label("folder.categories.addCustom", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("folder.categories.addCustom")
            .focused($focusedAction, equals: .addCustom)
            .sheet(isPresented: $isShowingAddCustom, onDismiss: restoreAddCustomFocus) {
                AddCustomCategorySheet(model: model)
            }
        }
        .alert("folder.categories.capReached.title", isPresented: $showCapReached) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("folder.categories.capReached.message")
        }
        .sheet(item: $reassignCategory) { category in
            ReassignCategorySheet(
                category: category,
                destinations: model.categories.filter { $0.id != category.id },
                receiptCount: receiptCount(category.id)
            ) { destination in
                onReassign(category, destination)
            }
        }
    }

    private func handleRemove(_ category: FolderCategory) {
        switch model.attemptRemove(id: category.id) {
        case .removed:
            break
        case .blockedUsed:
            reassignCategory = category
        }
    }

    private func addOrWarn(_ category: FolderCategory) {
        if model.add(category) == false {
            showCapReached = true
        }
    }

    private func restoreBrowseFocus() {
        #if os(macOS)
        focusedAction = .browse
        #endif
    }

    private func restoreAddCustomFocus() {
        #if os(macOS)
        focusedAction = .addCustom
        #endif
    }

    private enum ComposerAction: Hashable {
        case browse
        case addCustom
    }
}

private struct SelectedCategoryRow: View {
    var category: FolderCategory
    var onRemove: () -> Void
    @ScaledMetric(relativeTo: .body) private var tileSize = 28

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color("AttentionFieldEdge"))
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String.localizedStringWithFormat(String(localized: "folder.categories.remove"), category.displayName)))
            .accessibilityIdentifier("folder.categories.remove.\(category.id)")

            CategoryGlyph(category: category, size: tileSize)
            Text(category.displayName)
                .contentScaledFont(.body)
            if category.isCustom {
                Text("folder.categories.customBadge")
                    .contentScaledFont(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
        #if os(iOS)
        .accessibilityElement(children: .combine)
        #endif
    }
}

private struct LockedOtherRow: View {
    var category: FolderCategory
    @ScaledMetric(relativeTo: .body) private var tileSize = 28

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .imageScale(.medium)
                .frame(width: 22)
            CategoryGlyph(category: category, size: tileSize)
            Text(category.displayName)
                .contentScaledFont(.body)
            Spacer()
            Text("folder.categories.otherLocked")
                .contentScaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("folder.categories.otherLocked"))
    }
}

/// Suggestion pills that wrap across rows and add themselves on tap.
private struct CategorySuggestionFlow: View {
    var suggestions: [FolderCategory]
    var onAdd: (FolderCategory) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(suggestions) { category in
                Button {
                    onAdd(category)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbolName)
                            .foregroundStyle(category.color)
                            .imageScale(.small)
                        Text(category.displayName)
                            .contentScaledFont(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "plus")
                            .contentScaledFont(.caption.weight(.semibold))
                            .foregroundStyle(Color("LedgerGreen"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String.localizedStringWithFormat(String(localized: "folder.categories.add"), category.displayName)))
                .accessibilityIdentifier("folder.categories.suggestion.\(category.id)")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Browse existing categories

/// Searchable catalog of every built-in category, grouped Suggested / Used in other profiles / All
/// (SPEC §D4). Adding uses the existing category's ID, symbol, and localized name — never a duplicate
/// custom category. When a search matches a built-in it is shown before any custom-creation path.
private struct BrowseCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FolderCategoryComposerModel
    var onAdded: () -> Void
    @State private var searchText = ""
    @State private var showCapReached = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(LocalizedStringKey(section.titleKey)) {
                        ForEach(section.categories) { category in
                            row(for: category)
                        }
                    }
                }
                if sections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .accessibilityIdentifier("mac.folderCategories.browse.list")
            .navigationTitle("folder.categories.browse")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "folder.categories.browse.search")
            .searchFocused($isSearchFocused)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                        .macDefaultAction()
                }
            }
            .alert("folder.categories.capReached.title", isPresented: $showCapReached) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("folder.categories.capReached.message")
            }
        }
        .macCatalogPresentation(accessibilityIdentifier: "mac.folderCategories.browse.sheet")
        .onAppear {
            #if os(macOS)
            isSearchFocused = true
            #endif
        }
    }

    private func row(for category: FolderCategory) -> some View {
        let alreadySelected = model.selectedIDs.contains(category.id)
        return Button {
            if model.add(category) == false {
                showCapReached = true
            } else {
                #if os(macOS)
                onAdded()
                #endif
            }
        } label: {
            HStack(spacing: 12) {
                CategoryGlyph(category: category, size: 26)
                Text(category.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: alreadySelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(alreadySelected ? Color("LedgerGreen") : .secondary)
            }
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
        .disabled(alreadySelected)
        .accessibilityIdentifier("folder.categories.browse.\(category.id)")
    }

    private var sections: [BrowseSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selected = model.selectedIDs
        let suggestedIDs = Set(FolderProfileCatalog.profile(id: model.profileID)?.suggestedCategoryIDs ?? [])
        let profileDefaultIDs = Set(FolderProfileCatalog.profile(id: model.profileID)?.defaultCategoryIDs ?? [])

        func matches(_ category: FolderCategory) -> Bool {
            guard query.isEmpty == false else { return true }
            return category.displayName.lowercased().contains(query) || category.id.contains(query)
        }

        let all = CategoryCatalog.all
            .map { $0.folderCategory }
            .filter { $0.isOther == false }
            .filter { matches($0) }

        let suggested = all.filter { suggestedIDs.contains($0.id) && selected.contains($0.id) == false }
        let otherProfiles = all.filter { id in
            suggestedIDs.contains(id.id) == false
                && profileDefaultIDs.contains(id.id) == false
                && isUsedInOtherProfile(id.id)
        }
        let everything = all.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        var result: [BrowseSection] = []
        if suggested.isEmpty == false {
            result.append(BrowseSection(id: "suggested", titleKey: "folder.categories.browse.suggested", categories: suggested))
        }
        if otherProfiles.isEmpty == false {
            result.append(BrowseSection(id: "otherProfiles", titleKey: "folder.categories.browse.otherProfiles", categories: otherProfiles.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }))
        }
        if everything.isEmpty == false {
            result.append(BrowseSection(id: "all", titleKey: "folder.categories.browse.all", categories: everything))
        }
        return result
    }

    private func isUsedInOtherProfile(_ id: String) -> Bool {
        FolderProfileCatalog.all.contains { profile in
            profile.id != model.profileID && profile.defaultCategoryIDs.contains(id)
        }
    }

    private struct BrowseSection: Identifiable {
        var id: String
        var titleKey: String
        var categories: [FolderCategory]
    }
}

// MARK: - Add custom category

/// Creates a folder-local custom category with a short name and a curated symbol (SPEC §D9). If the
/// typed name matches a built-in, the existing category is offered first to avoid a duplicate.
private struct AddCustomCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FolderCategoryComposerModel
    @State private var name = ""
    @State private var symbolName = CustomCategory.defaultSymbolName
    @State private var showCapReached = false
    @FocusState private var isNameFocused: Bool

    private static let curatedSymbols = [
        "tag.fill", "bag.fill", "cart.fill", "creditcard.fill", "doc.text.fill",
        "wrench.and.screwdriver.fill", "cross.case.fill", "car.fill", "fork.knife",
        "gift.fill", "book.fill", "ticket.fill", "shippingbox.fill", "bolt.fill", "wifi", "banknote.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("folder.categories.custom.nameSection") {
                    TextField("folder.categories.custom.namePlaceholder", text: $name)
                        .focused($isNameFocused)
                        .accessibilityIdentifier("folder.categories.custom.name")
                }

                if let existing = matchingBuiltIn {
                    Section("folder.categories.custom.existingMatch") {
                        Button {
                            add(existing)
                        } label: {
                            HStack(spacing: 12) {
                                CategoryGlyph(category: existing, size: 26)
                                Text(existing.displayName)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color("LedgerGreen"))
                            }
                        }
                        .accessibilityIdentifier("folder.categories.custom.useExisting")
                    }
                }

                Section("folder.categories.custom.symbolSection") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 12) {
                        ForEach(Self.curatedSymbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .imageScale(.medium)
                                    .foregroundStyle(symbol == symbolName ? .white : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(symbol == symbolName ? Color("LedgerGreen") : Color.secondary.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(symbol))
                            .accessibilityAddTraits(symbol == symbolName ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .macGroupedForm(accessibilityIdentifier: "mac.folderCategories.custom.form")
            .navigationTitle("folder.categories.addCustom")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                        .macCancelAction()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("folder.categories.add.action") { addCustom() }
                        .disabled(customCategory == nil)
                        .macDefaultAction()
                }
            }
            .alert("folder.categories.capReached.title", isPresented: $showCapReached) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("folder.categories.capReached.message")
            }
        }
        .macFormPresentation(
            accessibilityIdentifier: "mac.folderCategories.custom.sheet",
            minHeight: 400,
            idealHeight: 480,
            maxHeight: 640
        )
        .onAppear {
            #if os(macOS)
            isNameFocused = true
            #endif
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// If the typed name resolves to a built-in category ID, surface that built-in first (SPEC §D4).
    private var matchingBuiltIn: FolderCategory? {
        guard trimmedName.isEmpty == false else { return nil }
        let query = trimmedName.lowercased()
        return CategoryCatalog.all
            .map { $0.folderCategory }
            .filter { $0.isOther == false }
            .first { $0.displayName.lowercased() == query }
    }

    private var customCategory: FolderCategory? {
        CustomCategory.make(
            name: trimmedName,
            symbolName: symbolName,
            existingIDs: model.selectedIDs,
            existingCategories: model.categories
        )
    }

    private func addCustom() {
        guard let category = customCategory else { return }
        add(category)
    }

    private func add(_ category: FolderCategory) {
        if model.add(category) {
            dismiss()
        } else {
            showCapReached = true
        }
    }
}

// MARK: - Reassign receipts before removing a used category

/// Presented when the user removes a category that receipts already use (SPEC §D5). Offers to
/// reassign those receipts to another visible category, or to keep the category.
struct ReassignCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    var category: FolderCategory
    var destinations: [FolderCategory]
    var receiptCount: Int
    /// Reassign all receipts from `category` to the chosen destination, then remove the category.
    var onReassign: (FolderCategory) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String.localizedStringWithFormat(
                        String(localized: "folder.categories.usedByReceipts"),
                        category.displayName
                    ))
                    .contentScaledFont(.subheadline)
                    Text(String.localizedStringWithFormat(
                        String(localized: "groups.receipt.count"),
                        receiptCount
                    ))
                    .contentScaledFont(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("folder.categories.reassign") {
                    ForEach(destinations) { destination in
                        Button {
                            onReassign(destination)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                CategoryGlyph(category: destination, size: 26)
                                Text(destination.displayName)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        #if os(macOS)
                        .buttonStyle(.borderless)
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .accessibilityIdentifier("folder.categories.reassign.\(destination.id)")
                    }
                }
            }
            .accessibilityIdentifier("mac.folderCategories.reassign.list")
            .navigationTitle("folder.categories.reassign.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("folder.categories.keep") { dismiss() }
                        .accessibilityIdentifier("folder.categories.keep")
                        .macCancelAction()
                }
            }
        }
        .macCatalogPresentation(
            accessibilityIdentifier: "mac.folderCategories.reassign.sheet",
            minWidth: 520,
            idealWidth: 560,
            maxWidth: 680,
            minHeight: 360,
            idealHeight: 440,
            maxHeight: 600
        )
    }
}
