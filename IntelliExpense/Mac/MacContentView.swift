#if os(macOS)
import AppKit
import ExpenseCore
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MacContentView: View {
    var services: AppServices = .make()

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("mac.contentZoomStep") private var contentZoomStep = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: ModelAvailabilityStatus?
    @State private var didAcknowledgeModelNotReadyNotice = false

    var body: some View {
        Group {
            if services.launchConfiguration.skipOnboarding == false && hasSeenWelcome == false {
                OnboardingWelcomeView {
                    hasSeenWelcome = true
                    Task { await refreshAvailability() }
                }
            } else if let availability, availability.blocksCapture {
                AppleIntelligenceGateView(status: availability) {
                    openSystemSettings()
                }
            } else if availability == .modelNotReady && didAcknowledgeModelNotReadyNotice == false {
                AppleIntelligencePreparingNoticeView {
                    didAcknowledgeModelNotReadyNotice = true
                }
            } else {
                MacLibraryView(services: services, contentZoomStep: $contentZoomStep)
                    .contentScaledFont(.body)
                    .environment(\.macContentZoomFactor, contentZoom.factor)
            }
        }
        .task {
            if services.launchConfiguration.resetOnboarding {
                hasSeenWelcome = false
            }
            await refreshAvailability()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshAvailability() }
        }
    }

    private var contentZoom: MacContentZoom {
        MacContentZoom(step: contentZoomStep)
    }

    private func refreshAvailability() async {
        availability = await services.availabilityProvider.currentAvailability()
    }

    private func openSystemSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

private enum MacLibrarySelection: Hashable {
    case group(PersistentIdentifier)
    case unfiled
    case archived
}

struct MacLibraryView: View {
    private let foldersDisclosureChildIndent: CGFloat = 24

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @AppStorage(DefaultCurrencySettings.defaultCodeKey) private var defaultCurrencyCode = DefaultCurrencySettings.fallbackCode
    @AppStorage("defaultPaymentMethod") private var defaultPaymentMethodRawValue = PaymentMethod.card.rawValue
    @AppStorage(AgentImportSettings.requireReviewKey) private var agentEntriesRequireReview = true
    @Query(sort: \ExpenseGroup.createdAt, order: .reverse) private var groups: [ExpenseGroup]
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \ReceiptDraft.createdAt, order: .reverse) private var drafts: [ReceiptDraft]

    var services: AppServices
    @Binding var contentZoomStep: Int

    @SceneStorage("mac.sidebar.selection") private var restoredSidebarSelection = "all"
    @SceneStorage("mac.sidebar.foldersExpansion") private var restoredFoldersExpansion = "expanded"
    @State private var selection: MacLibrarySelection?
    @State private var selectedReceiptIDs: Set<PersistentIdentifier> = []
    @State private var searchText = ""
    @State private var undoGeneration = 0
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isReceiptListFocused: Bool
    @FocusState private var isSidebarFocused: Bool
    @FocusState private var renamingGroupID: PersistentIdentifier?
    @State private var renamingGroupName = ""
    @State private var isShowingFileImporter = false
    @State private var isShowingCreateGroup = false
    @State private var editingGroup: ExpenseGroup?
    @State private var isDropTargeted = false
    @State private var reviewForm: ReceiptReviewForm?
    @State private var reviewDefaultGroup: ExpenseGroup?
    @State private var processingState: ReceiptProcessingOverlayState?
    @State private var ingestTask: Task<Void, Never>?
    @State private var captureErrorMessage: String?
    @State private var attachmentTargetReceipt: Receipt?
    @State private var attachmentResultMessage: String?
    @State private var exportShareItem: ExportShareItem?
    @State private var exportProgress: ExportProgressState?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError = false
    @State private var pendingReceiptDeletion: [Receipt] = []
    @State private var quickLookURLs: [URL] = []
    @State private var quickLookSelection: URL?

    var body: some View {
        lifecycleView
    }

    private var baseView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } content: {
            receiptList
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                if let attachmentTargetReceipt {
                    attach(fileURLs: urls, to: attachmentTargetReceipt)
                } else {
                    ingest(fileURLs: urls)
                }
            } else if case .failure = result {
                captureErrorMessage = String(localized: "capture.error.generic")
                attachmentTargetReceipt = nil
            }
        }
        .importsItemProviders([.image, .pdf], onImport: importFromNearbyDevice)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color("LedgerGreen"), lineWidth: 3)
                    .padding(18)
                    .allowsHitTesting(false)
            }
            if let processingState {
                MacProcessingOverlay(state: processingState) {
                    cancelIngestion()
                }
            }
            if let exportProgress {
                ExportProgressOverlay(state: exportProgress) {
                    cancelExport()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("menu.importReceipts", systemImage: "square.and.arrow.down")
                }
                Button {
                    exportSelectedTrip()
                } label: {
                    Label("group.export", systemImage: "square.and.arrow.up")
                }
                .disabled(exportableReceipts.isEmpty)
            }
        }
    }

    private var commandView: some View {
        baseView
        .focusedSceneValue(
            \.macExpenseCommands,
            MacExpenseCommands(
                newTrip: { isShowingCreateGroup = true },
                importReceipts: { isShowingFileImporter = true },
                exportTrip: exportSelectedTrip,
                focusSearch: { isSearchFocused = true },
                selectAll: selectAllVisibleReceipts,
                archiveOrDeleteSelection: archiveOrDeleteSelection,
                quickLookSelection: showQuickLook,
                renameSelectedTrip: beginSelectedGroupRename,
                showArchived: { selection = .archived },
                undo: performUndo,
                redo: performRedo,
                archiveTitle: selectionActionTitle,
                undoTitle: modelContext.undoManager?.undoMenuItemTitle ?? "",
                redoTitle: modelContext.undoManager?.redoMenuItemTitle ?? "",
                moveDestinations: moveDestinations,
                canSelectAll: filteredReceipts.isEmpty == false && isReceiptListFocused,
                canActOnSelection: selectedBatchReceipts.isEmpty == false && isReceiptListFocused,
                canQuickLook: isReceiptListFocused && selectedBatchReceipts.isEmpty == false,
                canRenameTrip: selectedGroup != nil && isSidebarFocused,
                canUndo: canUndo,
                canRedo: canRedo
            )
        )
        .focusedSceneValue(
            \.macZoomCommands,
            MacZoomCommands(
                zoomIn: zoomInContent,
                zoomOut: zoomOutContent,
                reset: resetContentZoom,
                canZoomIn: contentZoom.canZoomIn,
                canZoomOut: contentZoom.canZoomOut,
                canReset: contentZoom.isActualSize == false
            )
        )
        .quickLookPreview($quickLookSelection, in: quickLookURLs)
    }

    private func performUndo() {
        modelContext.undoManager?.undo()
        try? modelContext.save()
        undoGeneration += 1
    }

    private var canUndo: Bool {
        _ = undoGeneration
        return modelContext.undoManager?.canUndo == true
    }

    private var canRedo: Bool {
        _ = undoGeneration
        return modelContext.undoManager?.canRedo == true
    }

    private func performRedo() {
        modelContext.undoManager?.redo()
        try? modelContext.save()
        undoGeneration += 1
    }

    private var presentationView: some View {
        commandView
        .sheet(isPresented: $isShowingCreateGroup) {
            GroupEditorSheet()
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(group: group)
        }
        .sheet(item: $exportShareItem, onDismiss: cleanupExportShareItem) { item in
            MacExportReadyView(item: item)
        }
        .alert("capture.error.title", isPresented: captureErrorAlertBinding) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(captureErrorMessage ?? "")
        }
        .alert("receipt.attach.result.title", isPresented: attachmentResultAlertBinding) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(attachmentResultMessage ?? "")
        }
        .alert("export.error.title", isPresented: $exportError) {
            Button("common.ok", role: .cancel) {}
        }
        .confirmationDialog(deleteConfirmationTitle, isPresented: receiptDeletionDialogBinding, titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                delete(pendingReceiptDeletion)
            }
            Button("common.cancel", role: .cancel) {
                pendingReceiptDeletion = []
            }
        }
    }

    private var lifecycleView: some View {
        presentationView
        .onDisappear {
            cancelIngestion()
            cancelExport()
            cleanupQuickLookFiles()
        }
        .task {
            seedMacVisualPolishLibraryIfNeeded()
            seedMacFolderEditorLibraryIfNeeded()
            modelContext.undoManager = undoManager
            if services.launchConfiguration.isUITesting == false {
                restoreSidebarSelection()
            }
            MacDockBadge.update(for: drafts)
        }
        .task(id: agentEntriesRequireReview) {
            await runAgentInboxLoop()
        }
        .onChange(of: selection) { _, newSelection in
            restoredSidebarSelection = restorationKey(for: newSelection)
            selectedReceiptIDs = []
        }
        .onChange(of: searchText) { _, _ in
            pruneSelectionToVisibleReceipts()
        }
        .onChange(of: receipts.count) { _, _ in
            pruneSelectionToVisibleReceipts()
        }
        .onChange(of: drafts.count) { _, _ in
            MacDockBadge.update(for: drafts)
        }
        .onChange(of: reviewForm == nil) { _, isReviewClosed in
            modelContext.undoManager = isReviewClosed ? undoManager : nil
        }
        .onChange(of: quickLookSelection) { _, selection in
            if selection == nil { cleanupQuickLookFiles() }
        }
    }

    private var sidebar: some View {
        let metrics = MacSidebarMetrics(groups: groups, receipts: receipts)

        return List(selection: $selection) {
            DisclosureGroup(isExpanded: foldersExpansionBinding) {
                ForEach(activeGroups) { group in
                    groupSidebarRow(group)
                        .padding(.leading, -foldersDisclosureChildIndent)
                        .tag(MacLibrarySelection.group(group.persistentModelID))
                        .contentShape(Rectangle())
                        .dropDestination(for: MacReceiptTransferItem.self) { items, _ in
                            return handleReceiptDrop(items, destination: group)
                        }
                        .contextMenu {
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
                            Button("common.edit") {
                                editingGroup = group
                            }
                            Button("trip.rename") {
                                beginRename(group)
                            }
                            Button("trip.archive") {
                                try? ReceiptStore.archive(group, in: modelContext)
                            }
                            Button("group.export") {
                                export(group: group)
                            }
                            .disabled(group.activeReceipts.isEmpty)
                        }
                }
            } label: {
                Text("tab.groups")
                    .accessibilityIdentifier("mac.sidebar.folders.header")
            }
            if unfiledReceipts.isEmpty == false {
                Section {
                    Label("groups.unfiled.title", systemImage: "tray")
                        .badge(metrics.unfiledReceiptCount)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(
                            badgeAccessibilityValue(
                                key: "mac.sidebar.unfiled.badge.ax",
                                count: metrics.unfiledReceiptCount
                            )
                        )
                        .accessibilityIdentifier("mac.sidebar.unfiled.row")
                        .tag(MacLibrarySelection.unfiled)
                        .dropDestination(for: MacReceiptTransferItem.self) { items, _ in
                            return handleReceiptDrop(items, destination: nil)
                        }
                }
            }
            if metrics.showsArchivedDestination {
                Section {
                    Label("trips.archived.title", systemImage: "archivebox")
                        .badge(metrics.archivedFolderCount)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(
                            badgeAccessibilityValue(
                                key: "mac.sidebar.archived.badge.ax",
                                count: metrics.archivedFolderCount
                            )
                        )
                        .accessibilityIdentifier("mac.sidebar.archived.row")
                        .tag(MacLibrarySelection.archived)
                        .dropDestination(for: MacReceiptTransferItem.self) { items, _ in
                            return handleArchiveDrop(items)
                        }
                }
            }
        }
        .safeAreaBar(edge: .bottom, alignment: .leading) {
            Button {
                isShowingCreateGroup = true
            } label: {
                Label("groups.create.row", systemImage: "folder.badge.plus")
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("mac.sidebar.newFolder")
        }
        .navigationTitle("app.name")
        .focused($isSidebarFocused)
    }

    @ViewBuilder
    private func groupSidebarRow(_ group: ExpenseGroup) -> some View {
        if renamingGroupID == group.persistentModelID {
            TextField("trip.rename", text: $renamingGroupName)
                .textFieldStyle(.plain)
                .focused($renamingGroupID, equals: group.persistentModelID)
                .onSubmit { commitRename(group) }
                .onExitCommand { cancelRename() }
                .accessibilityIdentifier("mac.sidebar.rename.field")
        } else {
            GroupRow(group: group)
                .background {
                    MacDoubleClickActionView { beginRename(group) }
                }
        }
    }

    @ViewBuilder
    private var receiptList: some View {
        List(selection: $selectedReceiptIDs) {
            AgentEntryConfirmationSection(
                entries: pendingAgentEntries,
                groups: groups,
                onConfirm: confirmAgentEntry,
                onReview: reviewAgentEntry
            )

            if filteredReceipts.isEmpty {
                if pendingAgentEntries.isEmpty {
                    if searchText.isEmpty {
                        AppEmptyStateView(emptyTitle, systemImage: "receipt", message: emptyMessage) {
                            Button("menu.importReceipts") {
                                isShowingFileImporter = true
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "receipts.search.empty.title",
                            systemImage: "magnifyingglass",
                            description: Text("receipts.search.empty.message")
                        )
                    }
                }
            } else {
                ForEach(ReceiptDateSections.sections(for: filteredReceipts), id: \.day) { section in
                    Section(ExpenseFormatters.dayHeader(section.day)) {
                        ForEach(section.receipts) { receipt in
                            draggableReceiptRow(receipt)
                                .tag(receipt.persistentModelID)
                                .contextMenu {
                                    receiptContextMenu(for: receipt)
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle(contentTitle)
        .focused($isReceiptListFocused)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: Text("receipts.search.prompt")
        )
        .searchFocused($isSearchFocused)
        .accessibilityIdentifier("mac.list.search")
        .onExitCommand {
            if searchText.isEmpty == false {
                searchText = ""
            }
            isReceiptListFocused = true
        }
    }

    @ViewBuilder
    private func draggableReceiptRow(_ receipt: Receipt) -> some View {
        if let item = MacReceiptTransferItem(receipt: receipt) {
            ReceiptRow(receipt: receipt)
                .draggable(item)
        } else {
            ReceiptRow(receipt: receipt)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let reviewForm {
            MacReceiptReviewPane(
                form: reviewForm,
                defaultGroup: reviewDefaultGroup,
                onSaved: {
                    self.reviewForm = nil
                    self.reviewDefaultGroup = nil
                },
                onDiscard: {
                    reviewForm.discardIfUnsaved(in: modelContext)
                    self.reviewForm = nil
                    self.reviewDefaultGroup = nil
                }
            )
        } else if selectedBatchReceipts.count > 1 {
            MacMultiSelectionSummary(receipts: selectedBatchReceipts)
        } else if let selectedReceipt {
            MacReceiptDetailPane(
                receipt: selectedReceipt,
                onAddPhoto: startAttachmentImport,
                onRemovedFromCurrentList: {
                    selectedReceiptIDs = []
                }
            )
        } else {
            ContentUnavailableView("mac.detail.empty.title", systemImage: "receipt", description: Text("mac.detail.empty.message"))
        }
    }

    private var captureErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { captureErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    captureErrorMessage = nil
                }
            }
        )
    }

    private var attachmentResultAlertBinding: Binding<Bool> {
        Binding(
            get: { attachmentResultMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    attachmentResultMessage = nil
                }
            }
        )
    }

    private var receiptDeletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingReceiptDeletion.isEmpty == false },
            set: { isPresented in
                if isPresented == false {
                    pendingReceiptDeletion = []
                }
            }
        )
    }

    private var defaultPaymentMethod: PaymentMethod {
        PaymentMethod(rawValue: defaultPaymentMethodRawValue) ?? .card
    }

    private var activeGroups: [ExpenseGroup] {
        ExpenseGroup.sortedPinnedFirst(groups)
    }

    private var archivedGroups: [ExpenseGroup] {
        ExpenseGroup.sortedByMostRecentArchive(groups)
    }

    private var unfiledReceipts: [Receipt] {
        receipts.filter { $0.group == nil && $0.isEffectivelyArchived == false }
    }

    private var archivedReceipts: [Receipt] {
        receipts.filter(\.isEffectivelyArchived)
    }

    private func badgeAccessibilityValue(key: String.LocalizationValue, count: Int) -> Text {
        guard count > 0 else { return Text("") }
        return Text(
            String.localizedStringWithFormat(
                String(localized: key),
                Int64(count)
            )
        )
    }

    private var selectedGroup: ExpenseGroup? {
        guard case .group(let id) = selection else { return nil }
        return groups.first { $0.persistentModelID == id }
    }

    private var scopedReceipts: [Receipt] {
        switch selection {
        case .group:
            selectedGroup?.activeReceipts.sorted { $0.date > $1.date } ?? []
        case .unfiled:
            unfiledReceipts.sorted { $0.date > $1.date }
        case .archived:
            archivedReceipts.sorted { $0.date > $1.date }
        case nil:
            receipts.filter { $0.isEffectivelyArchived == false }.sorted { $0.date > $1.date }
        }
    }

    private var filteredReceipts: [Receipt] {
        guard searchText.isEmpty == false else { return scopedReceipts }
        return scopedReceipts.filter { MacReceiptSearch.matches($0, query: searchText) }
    }

    private var selectedBatchReceipts: [Receipt] {
        filteredReceipts.filter { selectedReceiptIDs.contains($0.persistentModelID) }
    }

    private var selectedReceipt: Receipt? {
        guard selectedBatchReceipts.count == 1 else { return nil }
        return selectedBatchReceipts.first
    }

    private func seedMacVisualPolishLibraryIfNeeded() {
        guard services.launchConfiguration.seedMacVisualPolishLibrary,
              PersistenceStack.shouldUseInMemoryStoreForCurrentProcess(),
              receipts.isEmpty
        else { return }

        let pages = (try? services.makeUITestFixturePages(sourceType: .photoImport)) ?? []
        let attachments = pages.flatMap { page in
            [
                ReceiptAttachment(
                    imageData: page.imageData,
                    thumbnailData: page.thumbnailData,
                    pageIndex: 0,
                    capturedAt: Date(),
                    sourceType: .photoImport
                ),
                ReceiptAttachment(
                    imageData: page.imageData,
                    thumbnailData: page.thumbnailData,
                    pageIndex: 1,
                    capturedAt: Date(),
                    sourceType: .photoImport
                )
            ]
        }
        let receipt = Receipt(
            vendor: "REWE CITY",
            date: Date(timeIntervalSince1970: 1_781_395_200),
            totalAmount: NSDecimalNumber(string: "84.50").decimalValue,
            currencyCode: "EUR",
            expenseType: .food,
            paymentMethod: .cash,
            notes: "Mac visual polish UI-test fixture.",
            attachments: attachments
        )
        let euroReceipt = Receipt(
            vendor: "Hotel Mitte",
            date: Date(timeIntervalSince1970: 1_781_308_800),
            totalAmount: NSDecimalNumber(string: "20.00").decimalValue,
            currencyCode: "EUR",
            expenseType: .hotel,
            paymentMethod: .card,
            notes: "Conference hotel"
        )
        let dollarReceipt = Receipt(
            vendor: "New York Cab",
            date: Date(timeIntervalSince1970: 1_781_222_400),
            totalAmount: NSDecimalNumber(string: "10.00").decimalValue,
            currencyCode: "USD",
            expenseType: .taxi,
            paymentMethod: .card,
            notes: "Airport transfer"
        )
        let destinationGroup = ExpenseGroup(name: "Berlin Filing")
        attachments.forEach { $0.receipt = receipt }
        modelContext.insert(receipt)
        modelContext.insert(euroReceipt)
        modelContext.insert(dollarReceipt)
        modelContext.insert(destinationGroup)
        try? modelContext.save()
        selection = .unfiled
        selectedReceiptIDs = [receipt.persistentModelID]
    }

    private func seedMacFolderEditorLibraryIfNeeded() {
        guard services.launchConfiguration.seedMacFolderEditorLibrary,
              PersistenceStack.shouldUseInMemoryStoreForCurrentProcess(),
              groups.isEmpty,
              receipts.isEmpty
        else { return }

        let group = ExpenseGroup(name: "Modal Test Folder")
        let receipt = Receipt(
            vendor: "Modal Test Cafe",
            date: Date(timeIntervalSince1970: 1_783_209_600),
            totalAmount: NSDecimalNumber(string: "18.40").decimalValue,
            currencyCode: "EUR",
            expenseType: .food,
            paymentMethod: .card,
            group: group
        )
        group.receipts = [receipt]
        modelContext.insert(group)
        modelContext.insert(receipt)
        try? modelContext.save()
        selection = .group(group.persistentModelID)
    }

    private var pendingAgentEntries: [AgentPendingEntry] {
        AgentPendingEntry.entries(from: drafts)
    }

    private var contentTitle: LocalizedStringKey {
        switch selection {
        case .group:
            LocalizedStringKey(selectedGroup?.name ?? String(localized: "tab.receipts"))
        case .unfiled:
            "groups.unfiled.title"
        case .archived:
            "trips.archived.title"
        case nil:
            "tab.receipts"
        }
    }

    private var emptyTitle: LocalizedStringKey {
        selectedGroupsExist ? "receipts.empty.title" : "groups.empty.title"
    }

    private var emptyMessage: LocalizedStringKey {
        selectedGroupsExist ? "receipts.empty.message" : "groups.empty.message"
    }

    private var selectedGroupsExist: Bool {
        activeGroups.isEmpty == false || unfiledReceipts.isEmpty == false || archivedGroups.isEmpty == false
    }

    private var exportableReceipts: [Receipt] {
        scopedReceipts.filter { $0.isEffectivelyArchived == false }
    }

    @ViewBuilder
    private func receiptContextMenu(for receipt: Receipt) -> some View {
        let targets = contextReceipts(for: receipt)
        let allArchived = targets.allSatisfy(\.isEffectivelyArchived)

        if allArchived {
            Button {
                try? MacReceiptOperations.restore(targets, in: modelContext)
            } label: {
                Label("receipt.restore", systemImage: "arrow.uturn.backward")
            }
            .accessibilityIdentifier("mac.row.contextMenu.archive")

            Button(role: .destructive) {
                pendingReceiptDeletion = targets
            } label: {
                Label("common.delete", systemImage: "trash")
            }
            .accessibilityIdentifier("mac.row.contextMenu.delete")
        } else {
            Button {
                try? MacReceiptOperations.archive(targets, in: modelContext)
            } label: {
                Label(archiveTitle(for: targets), systemImage: "archivebox")
            }
            .accessibilityIdentifier("mac.row.contextMenu.archive")
        }

        Menu("receipt.action.moveToTrip") {
            Button("groups.unfiled.title") {
                try? MacReceiptOperations.move(targets, to: nil, in: modelContext)
            }
            ForEach(activeGroups) { group in
                Button(group.name) {
                    try? MacReceiptOperations.move(targets, to: group, in: modelContext)
                }
            }
        }
        .accessibilityIdentifier("mac.contextMenu.moveToTrip")

        Button {
            showQuickLook(for: targets)
        } label: {
            Label("receipt.action.quickLook", systemImage: "eye")
        }
        .disabled(targets.contains { ($0.attachments ?? []).isEmpty == false } == false)
        .accessibilityIdentifier("mac.contextMenu.quickLook")
    }

    private func contextReceipts(for receipt: Receipt) -> [Receipt] {
        selectedReceiptIDs.contains(receipt.persistentModelID) ? selectedBatchReceipts : [receipt]
    }

    private func delete(_ receipts: [Receipt]) {
        try? MacReceiptOperations.delete(receipts, in: modelContext)
        selectedReceiptIDs.subtract(receipts.map(\.persistentModelID))
        pendingReceiptDeletion = []
    }

    private func archiveTitle(for receipts: [Receipt]) -> String {
        guard receipts.count > 1 else { return String(localized: "receipt.archive") }
        return String.localizedStringWithFormat(String(localized: "receipts.batch.archive"), receipts.count)
    }

    private var selectionActionTitle: String {
        selectedBatchReceipts.allSatisfy(\.isEffectivelyArchived)
            ? String(localized: "common.delete")
            : archiveTitle(for: selectedBatchReceipts)
    }

    private var moveDestinations: [MacMoveDestination] {
        let unfiled = MacMoveDestination(
            id: "unfiled",
            title: String(localized: "groups.unfiled.title"),
            move: { try? MacReceiptOperations.move(selectedBatchReceipts, to: nil, in: modelContext) }
        )
        return [unfiled] + activeGroups.map { group in
            MacMoveDestination(
                id: "\(group.createdAt.timeIntervalSinceReferenceDate):\(group.name)",
                title: group.name,
                move: { try? MacReceiptOperations.move(selectedBatchReceipts, to: group, in: modelContext) }
            )
        }
    }

    private var deleteConfirmationTitle: String {
        guard pendingReceiptDeletion.count > 1 else { return String(localized: "receipt.delete.title") }
        return String.localizedStringWithFormat(
            String(localized: "receipts.batch.delete.title"),
            pendingReceiptDeletion.count
        )
    }

    private var contentZoom: MacContentZoom {
        MacContentZoom(step: contentZoomStep)
    }

    private func selectAllVisibleReceipts() {
        guard isSearchFocused == false else { return }
        selectedReceiptIDs = Set(filteredReceipts.map(\.persistentModelID))
        isReceiptListFocused = true
    }

    private func pruneSelectionToVisibleReceipts() {
        selectedReceiptIDs.formIntersection(filteredReceipts.map(\.persistentModelID))
    }

    private func archiveOrDeleteSelection() {
        let targets = selectedBatchReceipts
        guard targets.isEmpty == false else { return }
        if targets.allSatisfy(\.isEffectivelyArchived) {
            pendingReceiptDeletion = targets
        } else {
            let activeTargets = targets.filter { $0.isEffectivelyArchived == false }
            try? MacReceiptOperations.archive(activeTargets, in: modelContext)
            undoGeneration += 1
        }
    }

    private func zoomInContent() {
        var zoom = contentZoom
        zoom.zoomIn()
        contentZoomStep = zoom.step
    }

    private func zoomOutContent() {
        var zoom = contentZoom
        zoom.zoomOut()
        contentZoomStep = zoom.step
    }

    private func resetContentZoom() {
        contentZoomStep = 0
    }

    private func showQuickLook() {
        showQuickLook(for: selectedBatchReceipts)
    }

    private func showQuickLook(for receipts: [Receipt]) {
        guard let urls = try? MacReceiptFileMaterializer.materialize(receipts, purpose: "quick-look"),
              let first = urls.first
        else {
            NSSound.beep()
            return
        }
        quickLookURLs = urls
        quickLookSelection = first
    }

    private func cleanupQuickLookFiles() {
        if let directory = quickLookURLs.first?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        quickLookURLs = []
    }

    private func handleReceiptDrop(_ items: [MacReceiptTransferItem], destination: ExpenseGroup?) -> Bool {
        let droppedReceipts = receiptsForTransferItems(items)
        guard droppedReceipts.isEmpty == false else { return false }
        try? MacReceiptOperations.move(droppedReceipts, to: destination, in: modelContext)
        selectedReceiptIDs = Set(droppedReceipts.map(\.persistentModelID))
        return true
    }

    private func handleArchiveDrop(_ items: [MacReceiptTransferItem]) -> Bool {
        let droppedReceipts = receiptsForTransferItems(items).filter { $0.isEffectivelyArchived == false }
        guard droppedReceipts.isEmpty == false else { return false }
        try? MacReceiptOperations.archive(droppedReceipts, in: modelContext)
        return true
    }

    private func receiptsForTransferItems(_ items: [MacReceiptTransferItem]) -> [Receipt] {
        let keys = Set(items.map(\.receiptKey))
        return receipts.filter { keys.contains(MacReceiptFileMaterializer.key(for: $0)) }
    }

    private func beginSelectedGroupRename() {
        guard let selectedGroup else { return }
        beginRename(selectedGroup)
    }

    private func beginRename(_ group: ExpenseGroup) {
        selection = .group(group.persistentModelID)
        renamingGroupName = group.name
        renamingGroupID = group.persistentModelID
    }

    private func commitRename(_ group: ExpenseGroup) {
        let trimmedName = renamingGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            cancelRename()
            return
        }
        group.name = trimmedName
        try? modelContext.save()
        renamingGroupID = nil
    }

    private func cancelRename() {
        renamingGroupName = ""
        renamingGroupID = nil
    }

    private func restorationKey(for selection: MacLibrarySelection?) -> String {
        switch selection {
        case .group(let identifier):
            guard let group = groups.first(where: { $0.persistentModelID == identifier }) else { return "all" }
            return "group:\(group.createdAt.timeIntervalSinceReferenceDate):\(group.name)"
        case .unfiled: return "unfiled"
        case .archived: return "archived"
        case nil: return "all"
        }
    }

    private var foldersExpansionBinding: Binding<Bool> {
        Binding(
            get: {
                MacSidebarFoldersExpansion.isExpanded(restoredValue: restoredFoldersExpansion)
            },
            set: { isExpanded in
                restoredFoldersExpansion = MacSidebarFoldersExpansion.restoredValue(isExpanded: isExpanded)
            }
        )
    }

    private func restoreSidebarSelection() {
        switch restoredSidebarSelection {
        case "unfiled": selection = .unfiled
        case "archived": selection = archivedGroups.isEmpty && archivedReceipts.isEmpty ? nil : .archived
        default:
            guard restoredSidebarSelection.hasPrefix("group:"),
                  let separator = restoredSidebarSelection.dropFirst(6).firstIndex(of: ":"),
                  let timestamp = TimeInterval(restoredSidebarSelection.dropFirst(6)[..<separator]),
                  let group = groups.first(where: { abs($0.createdAt.timeIntervalSinceReferenceDate - timestamp) < 0.001 })
            else {
                selection = nil
                return
            }
            selection = .group(group.persistentModelID)
        }
    }

    private func importFromNearbyDevice(_ providers: [NSItemProvider]) -> Bool {
        let supportedProviders = providers.compactMap { provider -> (NSItemProvider, String)? in
            let identifier = [UTType.image, .pdf]
                .map(\.identifier)
                .first(where: provider.hasItemConformingToTypeIdentifier)
            return identifier.map { (provider, $0) }
        }
        guard supportedProviders.isEmpty == false else { return false }

        Task { @MainActor in
            do {
                var urls: [URL] = []
                for (provider, typeIdentifier) in supportedProviders {
                    guard let data = await dataRepresentation(from: provider, typeIdentifier: typeIdentifier) else {
                        continue
                    }
                    let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat"
                    let url = FileManager.default.temporaryDirectory
                        .appending(path: "continuity-camera-\(UUID().uuidString).\(fileExtension)")
                    try data.write(to: url, options: .atomic)
                    urls.append(url)
                }
                guard urls.isEmpty == false else { throw CocoaError(.fileReadUnknown) }
                ingest(fileURLs: urls, removeSourceFilesAfterProcessing: true)
            } catch {
                captureErrorMessage = String(localized: "capture.error.generic")
            }
        }
        return true
    }

    private func dataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func ingest(fileURLs urls: [URL], removeSourceFilesAfterProcessing: Bool = false) {
        guard urls.isEmpty == false else { return }
        ingestTask?.cancel()
        processingState = ReceiptProcessingOverlayState()
        reviewDefaultGroup = selectedGroup
        ingestTask = Task { @MainActor in
            let manager = modelContext.undoManager
            modelContext.undoManager = nil
            defer {
                processingState = nil
                ingestTask = nil
                if reviewForm == nil { modelContext.undoManager = manager }
                if removeSourceFilesAfterProcessing {
                    urls.forEach { try? FileManager.default.removeItem(at: $0) }
                }
            }
            do {
                let processor = makeFileIngestionProcessor()
                let form = try await processor.process(
                    fileURLs: urls,
                    defaultCurrencyCode: defaultCurrencyCode,
                    defaultPaymentMethod: defaultPaymentMethod,
                    onPagesBuilt: { pages in
                        processingState = ReceiptProcessingOverlayState(
                            previewImageData: pages.first?.thumbnailData ?? pages.first?.imageData
                        )
                    },
                    onStage: { stage in
                        processingState?.stage = stage
                    }
                )
                reviewForm = form
            } catch ReceiptProcessingError.blockedByModelAvailability {
                captureErrorMessage = String(localized: "capture.error.blocked")
            } catch is CancellationError {
                captureErrorMessage = nil
            } catch {
                captureErrorMessage = String(localized: "capture.error.generic")
            }
        }
    }

    private func startAttachmentImport(for receipt: Receipt) {
        attachmentTargetReceipt = receipt
        isShowingFileImporter = true
    }

    private func attach(fileURLs urls: [URL], to receipt: Receipt) {
        guard urls.isEmpty == false else {
            attachmentTargetReceipt = nil
            return
        }
        ingestTask?.cancel()
        processingState = ReceiptProcessingOverlayState()
        ingestTask = Task { @MainActor in
            let manager = modelContext.undoManager
            modelContext.undoManager = nil
            defer {
                processingState = nil
                ingestTask = nil
                attachmentTargetReceipt = nil
                modelContext.undoManager = manager
            }
            do {
                let processor = makeFileIngestionProcessor()
                let pages = try await processor.capturedPages(fromFileURLs: urls)
                try Task.checkCancellation()
                processingState = ReceiptProcessingOverlayState(
                    previewImageData: pages.first?.thumbnailData ?? pages.first?.imageData
                )
                let result = try await services.makePipeline(
                    context: modelContext,
                    defaultCurrencyCode: defaultCurrencyCode,
                    locale: .current
                )
                .process(capturedPages: pages) { stage in
                    processingState?.stage = stage
                }
                let diff = try receipt.applyAttachedCapture(result, in: modelContext)
                attachmentResultMessage = attachmentMessage(for: diff)
            } catch ReceiptProcessingError.blockedByModelAvailability {
                captureErrorMessage = String(localized: "capture.error.blocked")
            } catch is CancellationError {
                captureErrorMessage = nil
            } catch {
                captureErrorMessage = String(localized: "capture.error.generic")
            }
        }
    }

    private func makeFileIngestionProcessor() -> ReceiptFileIngestionProcessor {
        ReceiptFileIngestionProcessor(
            pageBuilder: services.receiptCapturePageBuilder,
            pdfRasterizer: services.pdfRasterizer,
            makePipeline: {
                services.makePipeline(
                    context: modelContext,
                    defaultCurrencyCode: defaultCurrencyCode,
                    locale: .current
                )
            }
        )
    }

    private func runAgentInboxLoop() async {
        while Task.isCancelled == false {
            await drainAgentInbox()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func drainAgentInbox() async {
        let manager = modelContext.undoManager
        modelContext.undoManager = nil
        defer {
            if reviewForm == nil { modelContext.undoManager = manager }
        }
        do {
            let inbox = try AgentImportInbox()
            try inbox.writeManifest(groups: groups)
            guard reviewForm == nil else { return }
            let processor = AgentImportProcessor(
                inbox: inbox,
                fileProcessor: makeFileIngestionProcessor(),
                context: modelContext
            )
            let result = await processor.processPendingDrops(
                groups: groups,
                requiresReview: agentEntriesRequireReview,
                defaultCurrencyCode: defaultCurrencyCode,
                defaultPaymentMethod: defaultPaymentMethod
            )
            if let rawReview = result.rawReview {
                reviewDefaultGroup = rawReview.defaultGroup
                reviewForm = rawReview.form
            }
            try inbox.writeManifest(groups: groups)
        } catch {
            _ = error
        }
    }

    private func confirmAgentEntry(_ entry: AgentPendingEntry) {
        guard let form = entry.makeReviewForm(
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod
        ) else { return }
        let manager = modelContext.undoManager
        modelContext.undoManager = nil
        defer { modelContext.undoManager = manager }
        _ = try? form.save(in: modelContext, group: entry.resolvedGroup(in: groups))
    }

    private func reviewAgentEntry(_ entry: AgentPendingEntry) {
        guard let form = entry.makeReviewForm(
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod
        ) else { return }
        reviewDefaultGroup = entry.resolvedGroup(in: groups)
        reviewForm = form
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didStartLoading = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didStartLoading = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url {
                    Task { @MainActor in
                        ingest(fileURLs: [url])
                    }
                }
            }
        }
        return didStartLoading
    }

    private func cancelIngestion() {
        ingestTask?.cancel()
        ingestTask = nil
        processingState = nil
        attachmentTargetReceipt = nil
    }

    private func exportSelectedTrip() {
        let receipts = exportableReceipts
        guard receipts.isEmpty == false else { return }
        let archiveBaseName = selectedGroup?.name ?? String(localized: "export.unfiled.filename")
        let fallbackSlug = selectedGroup == nil ? "unfiled-receipts" : "intelli-expense"
        startExport(receipts: receipts, archiveBaseName: archiveBaseName, fallbackSlug: fallbackSlug)
    }

    private func export(group: ExpenseGroup) {
        startExport(receipts: group.activeReceipts, archiveBaseName: group.name, fallbackSlug: "intelli-expense")
    }

    private func startExport(receipts: [Receipt], archiveBaseName: String, fallbackSlug: String) {
        guard receipts.isEmpty == false else { return }
        exportTask?.cancel()
        cleanupExportShareItem()

        let exportReceipts = ReceiptExportMapper.exportReceipts(from: receipts)
        let fileName = ExportFilenameBuilder().archiveFilename(for: archiveBaseName, fallbackSlug: fallbackSlug)
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
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        exportShareItem = nil
    }

    private func attachmentMessage(for diff: ReceiptAutofillDiff) -> String {
        var lines: [String] = []
        if diff.filledFields.isEmpty == false {
            lines.append(
                String.localizedStringWithFormat(
                    String(localized: "receipt.attach.result.filled"),
                    localizedFieldList(diff.filledFields)
                )
            )
        }
        if diff.conflictingFields.isEmpty == false {
            lines.append(
                String.localizedStringWithFormat(
                    String(localized: "receipt.attach.result.conflicts"),
                    localizedFieldList(diff.conflictingFields)
                )
            )
        }
        if lines.isEmpty {
            lines.append(String(localized: "receipt.attach.result.noChanges"))
        }
        return lines.joined(separator: "\n")
    }

    private func localizedFieldList(_ fields: [String]) -> String {
        fields.map(localizedFieldName).joined(separator: ", ")
    }

    private func localizedFieldName(_ field: String) -> String {
        switch field {
        case "vendor": String(localized: "receipt.field.vendor")
        case "date": String(localized: "receipt.field.date")
        case "totalAmount": String(localized: "receipt.field.amount")
        case "currencyCode": String(localized: "receipt.field.currency")
        case "expenseType": String(localized: "receipt.field.type")
        case "paymentMethod": String(localized: "receipt.field.payment")
        default: field
        }
    }
}

private struct MacProcessingOverlay: View {
    var state: ReceiptProcessingOverlayState
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.24).ignoresSafeArea()
            VStack(spacing: 16) {
                ReceiptProcessingPreview(imageData: state.previewImageData)
                    .frame(width: 160, height: 220)
                ProgressView(state.stage?.localizedTitle ?? String(localized: "processing.stage.reading"))
                Button("common.cancel", action: onCancel)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct ReceiptProcessingPreview: View {
    var imageData: Data?

    var body: some View {
        if let imageData, let image = ReceiptPlatformImage.receiptImage(data: imageData) {
            Image(receiptImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .overlay {
                    Image(systemName: "doc.text.viewfinder")
                        .contentScaledFont(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private extension ReceiptProcessingStage {
    var localizedTitle: String {
        switch self {
        case .readingText:
            String(localized: "processing.stage.reading")
        case .understandingReceipt:
            String(localized: "processing.stage.understanding")
        }
    }
}

private struct MacReceiptReviewPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseGroup.name) private var groups: [ExpenseGroup]
    @Bindable var form: ReceiptReviewForm
    var defaultGroup: ExpenseGroup?
    var onSaved: () -> Void
    var onDiscard: () -> Void
    @State private var selectedGroup: ExpenseGroup?
    @State private var showSaveError = false

    init(
        form: ReceiptReviewForm,
        defaultGroup: ExpenseGroup?,
        onSaved: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.form = form
        self.defaultGroup = defaultGroup
        self.onSaved = onSaved
        self.onDiscard = onDiscard
        _selectedGroup = State(initialValue: defaultGroup)
    }

    var body: some View {
        HStack(spacing: 0) {
            MacReceiptImageColumn(imageDatas: form.pageImageDatas) {
                ContentUnavailableView("review.manual.header", systemImage: "square.and.pencil")
            }
                .frame(minWidth: 320, idealWidth: 440, maxWidth: .infinity)
            Divider()
            Form {
                if let notice = form.notice {
                    Section {
                        Label(notice.localizedTitle, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("review.section.fields") {
                    TextField("receipt.field.vendor", text: $form.vendor)
                    DatePicker("receipt.field.date", selection: $form.date, displayedComponents: .date)
                    TextField("receipt.field.amount", text: $form.amountText)
                    CurrencyPickerRow(
                        title: "receipt.field.currency",
                        selectedCode: $form.currencyCode,
                        accessibilityIdentifier: "mac.review.currency.row"
                    )
                    Picker("receipt.field.type", selection: $form.categoryID) {
                        Text("review.required.unselected").tag(String?.none)
                        ForEach(macReviewCategories) { category in
                            Label(category.displayName, systemImage: category.symbolName).tag(String?.some(category.id))
                        }
                    }
                    Picker("receipt.field.payment", selection: $form.paymentMethod) {
                        Text("review.required.unselected").tag(PaymentMethod?.none)
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(ExpenseFormatters.paymentName(method)).tag(PaymentMethod?.some(method))
                        }
                    }
                    Menu {
                        Button("groups.unfiled.title") { selectedGroup = nil }
                        ForEach(assignableGroups) { group in
                            Button(group.name) { selectedGroup = group }
                        }
                    } label: {
                        LabeledContent("receipt.field.group", value: selectedGroup?.name ?? String(localized: "groups.unfiled.title"))
                    }
                    TextField("receipt.field.notes", text: $form.notes, axis: .vertical)
                }
                Section {
                    DisclosureGroup("receipt.detail.provenance") {
                        Text(form.provenanceText.isEmpty ? String(localized: "receipt.detail.noOCR") : form.provenanceText)
                            .contentScaledFont(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 360, idealWidth: 440)
        }
        .navigationTitle("review.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(cancelActionTitle, action: onDiscard)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save", action: save)
                    .disabled(form.canSave == false)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .alert("review.save.error", isPresented: $showSaveError) {
            Button("common.ok", role: .cancel) {}
        }
    }

    private var assignableGroups: [ExpenseGroup] {
        groups.filter { $0.isArchived == false || $0.persistentModelID == selectedGroup?.persistentModelID }
    }

    /// Folder-scoped category options for the Mac review picker, including the current category when
    /// it falls outside the selected folder's visible set (SPEC §D6).
    private var macReviewCategories: [FolderCategory] {
        let base = selectedGroup?.visibleCategories ?? FolderCategorySnapshot.unfiledDefault.categories
        if let id = form.categoryID, base.contains(where: { $0.id == id }) == false {
            return [CategoryResolver.category(forID: id, in: selectedGroup?.categorySnapshot)] + base
        }
        return base
    }

    private var cancelActionTitle: LocalizedStringKey {
        form.preservesPendingDraftOnDiscard ? "common.cancel" : "common.discard"
    }

    private func save() {
        do {
            _ = try form.save(in: modelContext, group: selectedGroup)
            onSaved()
        } catch {
            showSaveError = true
        }
    }
}

private extension ReceiptProcessingNotice {
    var localizedTitle: String {
        switch self {
        case .smartExtractionPreparing:
            String(localized: "notice.modelPreparing")
        case .smartExtractionTimedOut:
            String(localized: "notice.modelTimedOut")
        case .unsupportedReceiptLanguage:
            String(localized: "notice.unsupportedLanguage")
        case .smartExtractionUnavailable:
            String(localized: "notice.modelUnavailable")
        case .noReceiptTextFound:
            String(localized: "notice.noText")
        }
    }
}
#endif
