#if os(iOS)
import AVFoundation
import AppIntents
import ExpenseCore
import PhotosUI
import SwiftData
import SwiftUI
import TipKit
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    var services: AppServices = .make()

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    #if INTELLI_EXPENSE_SANDBOX
    @AppStorage("sandboxShouldShowOnboarding") private var sandboxShouldShowOnboarding = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: ModelAvailabilityStatus?
    @State private var didAcknowledgeModelNotReadyNotice = false
    @State private var deepLinkRequests = DeepLinkRequestState()

    init(services: AppServices = .make()) {
        self.services = services
        if services.launchConfiguration.resetCurrencyDefaults {
            DefaultCurrencySettings.resetSeededDefault()
        }
        DefaultCurrencySettings.seedIfNeeded()
    }

    var body: some View {
        Group {
            if shouldShowWelcome {
                OnboardingWelcomeView {
                    hasSeenWelcome = true
                    #if INTELLI_EXPENSE_SANDBOX
                    sandboxShouldShowOnboarding = false
                    #endif
                    Task { await refreshAvailability() }
                }
            } else if let availability, availability.blocksCapture {
                AppleIntelligenceGateView(status: availability) {
                    openSettings()
                }
            } else if availability == .modelNotReady && didAcknowledgeModelNotReadyNotice == false {
                AppleIntelligencePreparingNoticeView {
                    didAcknowledgeModelNotReadyNotice = true
                }
            } else {
                MainTabView(
                    services: services,
                    sharedInboxOpenRequestID: deepLinkRequests.sharedInboxOpenRequestID,
                    captureOpenRequestID: deepLinkRequests.captureOpenRequestID,
                    captureRequestedKind: deepLinkRequests.captureRequestedKind
                )
            }
        }
        .task {
            if services.launchConfiguration.resetOnboarding {
                hasSeenWelcome = false
                #if INTELLI_EXPENSE_SANDBOX
                sandboxShouldShowOnboarding = true
                #endif
            }
            await refreshAvailability()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshAvailability() }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onAppIntentExecution(ScanReceiptIntent.self) { intent in
            handleIncomingAppIntent(intent)
        }
    }

    private var shouldShowWelcome: Bool {
        #if INTELLI_EXPENSE_SANDBOX
        if sandboxShouldShowOnboarding {
            return hasSeenWelcome == false
        }
        #endif
        return services.launchConfiguration.skipOnboarding == false && hasSeenWelcome == false
    }

    private func refreshAvailability() async {
        availability = await services.availabilityProvider.currentAvailability()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func handleIncomingURL(_ url: URL) {
        guard let route = AppDeepLinkRouter.route(for: url, supportedSchemes: supportedDeepLinkSchemes) else { return }
        handle(route)
    }

    private func handleIncomingAppIntent(_ intent: ScanReceiptIntent) {
        guard intent.target == .capture else { return }
        handleIncomingURL(AppDeepLinkRouter.captureURL)
    }

    private func handle(_ route: AppDeepLinkRoute) {
        if case .capture = route {
            guard shouldShowWelcome == false else { return }
            if availability == .modelNotReady {
                didAcknowledgeModelNotReadyNotice = true
            }
        }
        deepLinkRequests.apply(route)
    }

    private var supportedDeepLinkSchemes: Set<String> {
        #if INTELLI_EXPENSE_SANDBOX
        return ["intelliexpense-sandbox"]
        #else
        return ["intelliexpense"]
        #endif
    }
}

private struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DefaultCurrencySettings.defaultCodeKey) private var defaultCurrencyCode = DefaultCurrencySettings.fallbackCode
    @AppStorage("defaultPaymentMethod") private var defaultPaymentMethodRawValue = PaymentMethod.card.rawValue
    @Query(sort: \ExpenseGroup.createdAt, order: .reverse) private var groups: [ExpenseGroup]
    var services: AppServices
    var sharedInboxOpenRequestID: UUID?
    var captureOpenRequestID: UUID?
    var captureRequestedKind: CaptureKind = .scan

    @State private var selectedTab = 0
    @State private var isShowingAddReceiptSheet = false
    @State private var isShowingAttachDialog = false
    @State private var isShowingCamera = false
    @State private var isShowingCameraDenied = false
    @State private var isShowingPhotosPicker = false
    @State private var isShowingFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var reviewForm: ReceiptReviewForm?
    @State private var reviewFormSourceType: ReceiptAttachmentSourceType?
    @State private var processingState: ReceiptProcessingOverlayState?
    @State private var captureTask: Task<Void, Never>?
    @State private var captureErrorMessage: String?
    @State private var defaultCaptureGroup: ExpenseGroup?
    @State private var captureDestinationGroup: ExpenseGroup?
    @State private var pendingAddReceiptAction: AddReceiptAction?
    @State private var attachmentTargetReceipt: Receipt?
    @State private var attachmentResultMessage: String?
    @State private var didSweepExpiredDrafts = false
    @State private var activeSharedInboxItem: SharedInboxItem?
    @State private var captureOpenRequestGate = DeepLinkRequestGate()

    var body: some View {
        ZStack {
            tabsWithCaptureAccessory

            if let processingState {
                ProcessingOverlay(state: processingState) {
                    cancelCapture()
                }
            }
        }
        .task {
            seedTripBreakdownRowsIfNeeded()
            if didSweepExpiredDrafts == false {
                didSweepExpiredDrafts = true
                try? ReceiptStore.sweepExpiredDrafts(in: modelContext)
            }
            await drainSharedInboxIfPossible()
            handleExternalCaptureRequest(captureOpenRequestID)
        }
        .onDisappear {
            captureTask?.cancel()
        }
        .onChange(of: processingState?.stage) { _, newStage in
            if let newStage {
                announceProcessingStage(newStage)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != 0 {
                captureDestinationGroup = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await drainSharedInboxIfPossible() }
        }
        .onChange(of: sharedInboxOpenRequestID) { _, _ in
            Task { await drainSharedInboxIfPossible() }
        }
        .onChange(of: captureOpenRequestID) { _, newRequestID in
            handleExternalCaptureRequest(newRequestID)
        }
        .sheet(isPresented: $isShowingAddReceiptSheet, onDismiss: performPendingAddReceiptAction) {
            AddReceiptSheet(destinationName: addReceiptSheetDestinationName) { action in
                pendingAddReceiptAction = action
                isShowingAddReceiptSheet = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("receipt.attach.title", isPresented: $isShowingAttachDialog, titleVisibility: .visible) {
            Button("capture.scan") {
                if services.launchConfiguration.usesFakeServices {
                    startUITestFixtureAttachment(sourceType: .cameraScan)
                } else {
                    presentDocumentCameraIfAvailable()
                }
            }
            Button("capture.photo") {
                if services.launchConfiguration.usesFakeServices {
                    startUITestFixtureAttachment(sourceType: .photoImport)
                } else {
                    isShowingPhotosPicker = true
                }
            }
            Button("capture.file") {
                isShowingFileImporter = true
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            DocumentCameraView(
                onScanImages: { images in
                    if let receipt = attachmentTargetReceipt {
                        startAttachmentCapture(for: receipt) {
                            try services.receiptCapturePageBuilder.makePages(from: images, sourceType: .cameraScan)
                        }
                    } else {
                        startCapture {
                            try services.receiptCapturePageBuilder.makePages(from: images, sourceType: .cameraScan)
                        }
                    }
                },
                onCancel: {},
                onError: handleDocumentCameraError
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingCameraDenied) {
            CameraPermissionDeniedView {
                openAppSettings()
            }
        }
        .photosPicker(isPresented: $isShowingPhotosPicker, selection: $selectedPhotoItems, matching: .images)
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard newItems.isEmpty == false else { return }
            if let receipt = attachmentTargetReceipt {
                processAttachmentPhotoItems(newItems, receipt: receipt)
            } else {
                processPhotoItems(newItems)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            if let receipt = attachmentTargetReceipt {
                processAttachmentFileImporterResult(result, receipt: receipt)
            } else {
                processFileImporterResult(result)
            }
        }
        .sheet(item: $reviewForm, onDismiss: {
            reviewFormSourceType = nil
            Task { await drainSharedInboxIfPossible() }
        }) { form in
            NavigationStack {
                ReceiptReviewView(
                    form: form,
                    defaultGroup: defaultCaptureGroup,
                    onSaved: handleReviewSaved
                )
            }
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

    @ViewBuilder
    private var tabsWithCaptureAccessory: some View {
        if selectedTab == 2 {
            mainTabs
        } else {
            mainTabs
                .tabViewBottomAccessory {
                    CaptureAccessoryView(
                        destinationName: captureAccessoryDestinationName,
                        primaryAction: { startAccessoryCapture(sourceType: .cameraScan) },
                        moreAction: { showAccessoryAddReceiptSheet() },
                        photoAction: { startAccessoryCapture(sourceType: .photoImport) },
                        fileAction: { startAccessoryFileImport() },
                        manualAction: { startAccessoryManualEntry() }
                    )
                    .allowsHitTesting(processingState == nil)
                }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("tab.groups", systemImage: "folder", value: 0) {
                GroupsTabView(
                    onAdd: { showAddReceiptSheet(defaultGroup: nil) },
                    onCaptureForGroup: { group in showAddReceiptSheet(defaultGroup: group) },
                    onAttachPhoto: showAttachDialog,
                    onViewingGroupChange: { group in
                        captureDestinationGroup = group
                    }
                )
            }

            Tab("tab.receipts", systemImage: "receipt", value: 1) {
                ReceiptsTabView(
                    onAdd: { showAddReceiptSheet(defaultGroup: nil) },
                    onAttachPhoto: showAttachDialog
                )
            }

            Tab("tab.settings", systemImage: "gearshape", value: 2) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private func showAddReceiptSheet(defaultGroup: ExpenseGroup?) {
        attachmentTargetReceipt = nil
        defaultCaptureGroup = activeGroup(defaultGroup) ?? mostRecentlyUsedGroup
        pendingAddReceiptAction = nil
        CaptureOptionsTip().invalidate(reason: .actionPerformed)
        isShowingAddReceiptSheet = true
    }

    private func showAccessoryAddReceiptSheet() {
        prepareAccessoryCapture()
        pendingAddReceiptAction = nil
        CaptureOptionsTip().invalidate(reason: .actionPerformed)
        isShowingAddReceiptSheet = true
    }

    private func performPendingAddReceiptAction() {
        guard let action = pendingAddReceiptAction else { return }
        pendingAddReceiptAction = nil
        Task { @MainActor in
            await Task.yield()
            dispatchAddReceiptAction(action)
        }
    }

    private func dispatchAddReceiptAction(_ action: AddReceiptAction) {
        attachmentTargetReceipt = nil
        switch action {
        case .scan:
            if services.launchConfiguration.usesFakeServices {
                startUITestFixtureCapture(sourceType: .cameraScan)
            } else {
                presentDocumentCameraIfAvailable()
            }
        case .photo:
            if services.launchConfiguration.usesFakeServices {
                startUITestFixtureCapture(sourceType: .photoImport)
            } else {
                isShowingPhotosPicker = true
            }
        case .file:
            isShowingFileImporter = true
        case .manual:
            startManualEntry()
        }
    }

    private func prepareAccessoryCapture() {
        attachmentTargetReceipt = nil
        defaultCaptureGroup = activeGroup(captureDestinationGroup)
    }

    private func startAccessoryCapture(sourceType: ReceiptAttachmentSourceType) {
        prepareAccessoryCapture()
        switch sourceType {
        case .cameraScan:
            if services.launchConfiguration.forceCameraDeniedForUITests {
                presentDocumentCameraIfAvailable()
            } else if services.launchConfiguration.usesFakeServices {
                startUITestFixtureCapture(sourceType: .cameraScan)
            } else {
                presentDocumentCameraIfAvailable()
            }
        case .photoImport:
            if services.launchConfiguration.usesFakeServices {
                startUITestFixtureCapture(sourceType: .photoImport)
            } else {
                isShowingPhotosPicker = true
            }
        case .fileImport:
            isShowingFileImporter = true
        }
    }

    private func handleExternalCaptureRequest(_ requestID: UUID?) {
        guard captureOpenRequestGate.shouldHandle(requestID) else { return }
        guard canStartExternalCapture else { return }
        selectedTab = 0
        dispatchExternalCapture(captureRequestedKind)
    }

    private func dispatchExternalCapture(_ kind: CaptureKind) {
        switch kind.externalCaptureAction {
        case .accessoryCapture(let sourceType):
            startAccessoryCapture(sourceType: sourceType)
        case .fileImport:
            startAccessoryFileImport()
        case .manualEntry:
            startAccessoryManualEntry()
        }
    }

    private var canStartExternalCapture: Bool {
        processingState == nil &&
            reviewForm == nil &&
            attachmentTargetReceipt == nil &&
            captureTask == nil &&
            isShowingAddReceiptSheet == false &&
            isShowingAttachDialog == false &&
            isShowingCamera == false &&
            isShowingCameraDenied == false &&
            isShowingPhotosPicker == false &&
            isShowingFileImporter == false
    }

    private func startAccessoryFileImport() {
        prepareAccessoryCapture()
        isShowingFileImporter = true
    }

    private func startAccessoryManualEntry() {
        prepareAccessoryCapture()
        startManualEntry()
    }

    private func startManualEntry() {
        reviewFormSourceType = nil
        reviewForm = ReceiptReviewForm.manual(
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod
        )
    }

    private func showAttachDialog(receipt: Receipt) {
        attachmentTargetReceipt = receipt
        isShowingAttachDialog = true
    }

    private func startUITestFixtureCapture(sourceType: ReceiptAttachmentSourceType) {
        startCapture {
            try services.makeUITestFixturePages(sourceType: sourceType)
        }
    }

    private func startUITestFixtureAttachment(sourceType: ReceiptAttachmentSourceType) {
        guard let receipt = attachmentTargetReceipt else { return }
        startAttachmentCapture(for: receipt) {
            try services.makeUITestFixturePages(sourceType: sourceType)
        }
    }

    private func startCapture(_ buildPages: @escaping @MainActor () async throws -> [CapturedReceiptPage]) {
        captureTask?.cancel()
        reviewFormSourceType = nil
        captureTask = Task { @MainActor in
            await process(buildPages)
        }
    }

    private func startAttachmentCapture(
        for receipt: Receipt,
        _ buildPages: @escaping @MainActor () async throws -> [CapturedReceiptPage]
    ) {
        captureTask?.cancel()
        captureTask = Task { @MainActor in
            await processAttachment(for: receipt, buildPages)
        }
    }

    private func cancelCapture() {
        if let activeSharedInboxItem, let inbox = services.sharedInbox {
            try? inbox.remove(activeSharedInboxItem)
            self.activeSharedInboxItem = nil
        }
        captureTask?.cancel()
    }

    private func process(_ buildPages: @escaping @MainActor () async throws -> [CapturedReceiptPage]) async {
        processingState = ReceiptProcessingOverlayState()
        defer {
            processingState = nil
            captureTask = nil
        }
        do {
            let pages = try await buildPages()
            try Task.checkCancellation()
            let sourceType = pages.first?.sourceType
            processingState = ReceiptProcessingOverlayState(previewImageData: pages.first?.thumbnailData ?? pages.first?.imageData)
            let result = try await services.makePipeline(
                context: modelContext,
                defaultCurrencyCode: defaultCurrencyCode,
                locale: .current
            ).process(capturedPages: pages) { stage in
                processingState?.stage = stage
            }
            reviewFormSourceType = sourceType
            reviewForm = ReceiptReviewForm(
                draft: result.draft,
                mergedReceipt: result.mergedReceipt,
                notice: result.notice,
                defaultCurrencyCode: defaultCurrencyCode,
                defaultPaymentMethod: defaultPaymentMethod
            )
        } catch ReceiptProcessingError.blockedByModelAvailability {
            captureErrorMessage = String(localized: "capture.error.blocked")
        } catch is CancellationError {
            captureErrorMessage = nil
        } catch {
            captureErrorMessage = String(localized: "capture.error.generic")
        }
    }

    private func drainSharedInboxIfPossible() async {
        guard canDrainSharedInbox, let inbox = services.sharedInbox else { return }
        try? inbox.sweep(olderThan: Date(timeIntervalSinceNow: -24 * 60 * 60))
        guard let item = try? inbox.pendingItems().first else { return }
        activeSharedInboxItem = item
        defaultCaptureGroup = nil
        reviewFormSourceType = nil
        startSharedInboxCapture(item)
    }

    private var canDrainSharedInbox: Bool {
        processingState == nil &&
            reviewForm == nil &&
            attachmentTargetReceipt == nil &&
            captureTask == nil
    }

    private func startSharedInboxCapture(_ item: SharedInboxItem) {
        captureTask?.cancel()
        captureTask = Task { @MainActor in
            await processSharedInboxItem(item)
        }
    }

    private func processSharedInboxItem(_ item: SharedInboxItem) async {
        guard let inbox = services.sharedInbox else { return }
        processingState = ReceiptProcessingOverlayState()
        defer {
            processingState = nil
            captureTask = nil
            activeSharedInboxItem = nil
        }
        do {
            if services.launchConfiguration.seedSharedInbox {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
            try Task.checkCancellation()
            let processor = SharedReceiptInboxDrainProcessor(
                inbox: inbox,
                pageBuilder: services.receiptCapturePageBuilder,
                makePipeline: {
                    services.makePipeline(
                        context: modelContext,
                        defaultCurrencyCode: defaultCurrencyCode,
                        locale: .current
                    )
                }
            )
            reviewForm = try await processor.process(
                item,
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
        } catch ReceiptProcessingError.blockedByModelAvailability {
            captureErrorMessage = String(localized: "capture.error.blocked")
        } catch is CancellationError {
            captureErrorMessage = nil
        } catch {
            captureErrorMessage = String(localized: "capture.error.generic")
        }
    }

    private func processAttachment(
        for receipt: Receipt,
        _ buildPages: @escaping @MainActor () async throws -> [CapturedReceiptPage]
    ) async {
        processingState = ReceiptProcessingOverlayState()
        defer {
            processingState = nil
            captureTask = nil
            attachmentTargetReceipt = nil
        }
        do {
            let pages = try await buildPages()
            try Task.checkCancellation()
            processingState = ReceiptProcessingOverlayState(previewImageData: pages.first?.thumbnailData ?? pages.first?.imageData)
            let result = try await services.makePipeline(
                context: modelContext,
                defaultCurrencyCode: defaultCurrencyCode,
                locale: .current
            ).process(capturedPages: pages) { stage in
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

    private func processPhotoItems(_ items: [PhotosPickerItem]) {
        startCapture {
            let data = try await loadImageData(from: items)
            return try services.receiptCapturePageBuilder.makePages(fromImageData: data, sourceType: .photoImport)
        }
        selectedPhotoItems = []
    }

    private func processAttachmentPhotoItems(_ items: [PhotosPickerItem], receipt: Receipt) {
        startAttachmentCapture(for: receipt) {
            let data = try await loadImageData(from: items)
            return try services.receiptCapturePageBuilder.makePages(fromImageData: data, sourceType: .photoImport)
        }
        selectedPhotoItems = []
    }

    private func processFileImporterResult(_ result: Result<[URL], Error>) {
        startCapture {
            try await pages(from: result)
        }
    }

    private func processAttachmentFileImporterResult(_ result: Result<[URL], Error>, receipt: Receipt) {
        startAttachmentCapture(for: receipt) {
            try await pages(from: result)
        }
    }

    private var defaultPaymentMethod: PaymentMethod {
        PaymentMethod(rawValue: defaultPaymentMethodRawValue) ?? .card
    }

    private var mostRecentlyUsedGroup: ExpenseGroup? {
        ExpenseGroup.sortedByMostRecentActivity(groups).first
    }

    private func seedTripBreakdownRowsIfNeeded() {
        guard services.launchConfiguration.seedTripBreakdownRows,
              PersistenceStack.shouldUseInMemoryStoreForCurrentProcess(),
              groups.isEmpty
        else { return }

        let group = ExpenseGroup(
            name: "Breakdown Rows",
            startDate: date(2026, 6, 12),
            endDate: date(2026, 6, 16)
        )
        let receipts = [
            Receipt(
                vendor: "Food Vendor",
                date: date(2026, 6, 16),
                totalAmount: Decimal(string: "10.25")!,
                currencyCode: "EUR",
                expenseType: .food,
                paymentMethod: .cash,
                group: group
            ),
            Receipt(
                vendor: "Hotel Vendor",
                date: date(2026, 6, 15),
                totalAmount: Decimal(string: "120.00")!,
                currencyCode: "EUR",
                expenseType: .hotel,
                paymentMethod: .card,
                group: group
            ),
            Receipt(
                vendor: "Flight Vendor",
                date: date(2026, 6, 14),
                totalAmount: Decimal(string: "240.00")!,
                currencyCode: "EUR",
                expenseType: .flight,
                paymentMethod: .card,
                group: group
            ),
            Receipt(
                vendor: "Taxi Vendor",
                date: date(2026, 6, 13),
                totalAmount: Decimal(string: "31.50")!,
                currencyCode: "EUR",
                expenseType: .taxi,
                paymentMethod: .cash,
                group: group
            ),
            Receipt(
                vendor: "Other Vendor",
                date: date(2026, 6, 12),
                totalAmount: Decimal(string: "5.00")!,
                currencyCode: "EUR",
                expenseType: .other,
                paymentMethod: .card,
                group: group
            )
        ]
        group.receipts = receipts
        modelContext.insert(group)
        receipts.forEach { modelContext.insert($0) }
        try? modelContext.save()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day).date ?? Date()
    }

    private var captureAccessoryDestinationName: String {
        activeGroup(captureDestinationGroup)?.name ?? String(localized: "capture.accessory.unfiled")
    }

    private var addReceiptSheetDestinationName: String {
        activeGroup(defaultCaptureGroup)?.name ?? String(localized: "capture.accessory.unfiled")
    }

    private func handleReviewSaved() {
        if reviewFormSourceType == .cameraScan {
            CaptureOptionsTip.scanReceiptSaved.sendDonation()
        }
        reviewFormSourceType = nil
        reviewForm = nil
    }

    private func activeGroup(_ group: ExpenseGroup?) -> ExpenseGroup? {
        guard let group, group.isArchived == false else { return nil }
        return group
    }

    private func presentDocumentCameraIfAvailable() {
        if services.launchConfiguration.forceCameraDeniedForUITests {
            isShowingCameraDenied = true
            return
        }

        guard DocumentCameraSupport.live.canScanDocuments else {
            captureErrorMessage = String(localized: "capture.camera.unsupported")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            isShowingCameraDenied = true
        default:
            isShowingCamera = true
        }
    }

    private func handleDocumentCameraError(_ error: Error) {
        if isCameraPermissionDenied {
            isShowingCameraDenied = true
        } else {
            captureErrorMessage = error.localizedDescription
        }
    }

    private var isCameraPermissionDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func announceProcessingStage(_ stage: ReceiptProcessingStage) {
        UIAccessibility.post(notification: .announcement, argument: stage.accessibilityAnnouncement)
    }

    private func loadImageData(from items: [PhotosPickerItem]) async throws -> [Data] {
        var data: [Data] = []
        for item in items {
            if let loaded = try await item.loadTransferable(type: Data.self) {
                data.append(loaded)
            }
        }
        return data
    }

    private func pages(from result: Result<[URL], Error>) async throws -> [CapturedReceiptPage] {
        let urls = try result.get()
        var pages: [CapturedReceiptPage] = []
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "pdf" {
                pages.append(contentsOf: try services.pdfRasterizer.capturedPages(fromPDFData: data))
            } else {
                pages.append(contentsOf: try services.receiptCapturePageBuilder.makePages(fromImageData: [data], sourceType: .fileImport))
            }
        }
        return pages.enumerated().map { index, page in
            CapturedReceiptPage(
                id: page.id,
                imageData: page.imageData,
                thumbnailData: page.thumbnailData,
                pageIndex: index,
                sourceType: page.sourceType
            )
        }
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

private struct CaptureAccessoryView: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var destinationName: String
    var primaryAction: () -> Void
    var moreAction: () -> Void
    var photoAction: () -> Void
    var fileAction: () -> Void
    var manualAction: () -> Void
    @ScaledMetric(relativeTo: .headline) private var iconTileSize = 34
    private let captureOptionsTip = CaptureOptionsTip()

    var body: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                accessoryLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("capture.accessory.accessibility"))
            .accessibilityIdentifier("capture.accessory")

            if placement != .inline {
                Divider()
                    .frame(height: 32)
            }

            Button(action: moreAction) {
                moreLabel
            }
            .buttonStyle(.plain)
            .frame(minWidth: placement == .inline ? 44 : 52, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(Text("capture.accessory.more"))
            .accessibilityIdentifier("capture.accessory.menu")
            .popoverTip(captureOptionsTip, arrowEdge: .bottom)
        }
        .padding(.horizontal, placement == .inline ? 0 : 14)
        .padding(.vertical, placement == .inline ? 0 : 9)
        .contextMenu {
            menuContent()
        }
    }

    @ViewBuilder
    private var accessoryLabel: some View {
        if placement == .inline {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(Color("LedgerGreen"))
                Text("capture.accessory.title")
                    .contentScaledFont(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .contentScaledFont(.headline)
                    .imageScale(.medium)
                    .foregroundStyle(.white)
                    .frame(width: iconTileSize, height: iconTileSize)
                    .background(Color("LedgerGreen"), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("capture.accessory.title")
                        .contentScaledFont(.subheadline.weight(.semibold))
                    Text(destinationName)
                        .contentScaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var moreLabel: some View {
        if placement == .inline {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                Text("capture.accessory.moreLabel")
                    .contentScaledFont(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 52)
        }
    }

    @ViewBuilder
    private func menuContent() -> some View {
        Button("capture.photo", action: photoAction)
        Button("capture.file", action: fileAction)
        Button("capture.manual", action: manualAction)
    }
}

private struct ProcessingOverlay: View {
    var state: ReceiptProcessingOverlayState
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                VStack(spacing: 18) {
                    ReceiptProcessingPreview(imageData: state.previewImageData)
                        .frame(width: 180, height: 250)
                    Text("processing.title")
                        .contentScaledFont(.headline)
                        .foregroundStyle(.white)
                    Text(stageText)
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("processing.accessibility"))

                Button("common.cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("processing.cancel")
            }
        }
    }

    private var stageText: LocalizedStringKey {
        state.stage?.localizedKey ?? "processing.stage.reading"
    }
}

private struct ReceiptProcessingPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var imageData: Data?
    @State private var scanLineAtBottom = false

    var body: some View {
        ZStack(alignment: .top) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                VStack(spacing: 10) {
                    Capsule().fill(.secondary.opacity(0.4)).frame(height: 5)
                    Capsule().fill(.secondary.opacity(0.25)).frame(height: 5)
                    Capsule().fill(.secondary.opacity(0.25)).frame(height: 5)
                    Spacer()
                    Capsule().fill(.secondary.opacity(0.55)).frame(height: 7)
                }
                .padding(22)
            }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color("LedgerGreen").opacity(0.35), .white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 58)
                .offset(y: reduceMotion ? 88 : (scanLineAtBottom ? 260 : -64))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            guard reduceMotion == false else { return }
            scanLineAtBottom = false
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                scanLineAtBottom = true
            }
        }
    }
}

private extension ReceiptProcessingStage {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .readingText:
            "processing.stage.reading"
        case .understandingReceipt:
            "processing.stage.understanding"
        }
    }

    var accessibilityAnnouncement: String {
        switch self {
        case .readingText:
            String(localized: "processing.stage.reading")
        case .understandingReceipt:
            String(localized: "processing.stage.understanding")
        }
    }
}

#Preview {
    ContentView(services: .make(launchConfiguration: AppLaunchConfiguration(arguments: ["-UITestFakeServices", "-SkipOnboarding"])))
}
#endif
