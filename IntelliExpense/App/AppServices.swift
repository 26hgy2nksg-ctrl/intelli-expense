import ExpenseCore
import Foundation
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AppLaunchConfiguration: Equatable {
    var arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
    }

    var usesFakeServices: Bool {
        arguments.contains("-UITestFakeServices")
    }

    var isUITesting: Bool {
        arguments.contains("--ui-testing")
    }

    var skipOnboarding: Bool {
        #if INTELLI_EXPENSE_SANDBOX
        arguments.contains("-SandboxShowOnboarding") == false
        #else
        arguments.contains("-SkipOnboarding")
        #endif
    }

    var resetOnboarding: Bool {
        arguments.contains("-ResetOnboarding")
    }

    var resetCurrencyDefaults: Bool {
        arguments.contains("-ResetCurrencyDefaults")
    }

    var availabilityOverride: ModelAvailabilityStatus? {
        if arguments.contains("-FakeModelNotReady") { return .modelNotReady }
        if arguments.contains("-FakeAINotEnabled") { return .appleIntelligenceNotEnabled }
        if arguments.contains("-FakeDeviceNotEligible") { return .deviceNotEligible }
        if usesFakeServices { return .available }
        #if INTELLI_EXPENSE_SANDBOX
        if arguments.contains("-SandboxUseRealAvailability") == false { return .available }
        #endif
        return nil
    }

    var fakeUnsupportedLanguage: Bool {
        arguments.contains("-FakeUnsupportedLanguage")
    }

    var fakeSlowOCR: Bool {
        arguments.contains("-FakeSlowOCR")
    }

    var seedSharedInbox: Bool {
        arguments.contains("-UITestSeedSharedInbox")
    }

    var seedMacVisualPolishLibrary: Bool {
        arguments.contains("-UITestSeedMacVisualPolishLibrary")
    }

    var seedMacFolderEditorLibrary: Bool {
        arguments.contains("-UITestSeedMacFolderEditorLibrary")
    }

    var seedTripBreakdownRows: Bool {
        arguments.contains("-UITestSeedTripBreakdownRows")
    }

    var forceCameraDeniedForUITests: Bool {
        arguments.contains("-UITestForceCameraDenied")
    }
}

@MainActor
struct AppServices {
    static let productionSmartExtractionTimeoutSeconds: TimeInterval = 30

    var launchConfiguration: AppLaunchConfiguration
    var ocrService: any OCRServicing
    var modelService: any ExtractionModelServicing
    var availabilityProvider: any ModelAvailabilityProviding
    var receiptCapturePageBuilder: ReceiptCapturePageBuilder
    var pdfRasterizer: PDFReceiptPageRasterizer
    var timingRecorder: any ReceiptProcessingTimingRecording
    var sharedInbox: SharedReceiptInbox?

    static func make(
        launchConfiguration: AppLaunchConfiguration = AppLaunchConfiguration()
    ) -> AppServices {
        let availabilityProvider: any ModelAvailabilityProviding
        if let override = launchConfiguration.availabilityOverride {
            availabilityProvider = FakeModelAvailabilityProvider(status: override)
        } else {
            availabilityProvider = NonBlockingModelAvailabilityProvider(
                base: FoundationModelAvailabilityProvider()
            )
        }

        let ocrService: any OCRServicing
        let modelService: any ExtractionModelServicing
        if launchConfiguration.usesFakeServices {
            let fakeOCRResult = OCRResult(
                pages: [
                    OCRTextPage(
                        id: "fixture-0",
                        pageIndex: 0,
                        text: "REWE CITY\n14.06.2026\nSUMME 84,50 EUR\nBar",
                        confidence: 0.98
                    )
                ]
            )
            ocrService = launchConfiguration.fakeSlowOCR
                ? SlowFakeOCRService(result: fakeOCRResult)
                : FakeOCRService(
                    result: .success(fakeOCRResult)
                )
            if launchConfiguration.fakeUnsupportedLanguage {
                modelService = FakeExtractionModelService(
                    result: .failure(.unsupportedLanguageOrLocale("UI-test unsupported language fixture"))
                )
            } else {
                modelService = FakeExtractionModelService(
                    result: .success(
                        ModelExtractedReceipt(
                            paymentMethod: .known(primary: .cash),
                            expenseType: .known(primary: .food)
                        )
                    )
                )
            }
        } else {
            ocrService = VisionDocumentOCRService()
            modelService = FoundationModelReceiptService(timeoutSeconds: productionSmartExtractionTimeoutSeconds)
        }

        let builder = ReceiptCapturePageBuilder()
        let sharedInbox = makeSharedInbox(launchConfiguration: launchConfiguration)
        return AppServices(
            launchConfiguration: launchConfiguration,
            ocrService: ocrService,
            modelService: modelService,
            availabilityProvider: availabilityProvider,
            receiptCapturePageBuilder: builder,
            pdfRasterizer: PDFReceiptPageRasterizer(pageBuilder: builder),
            timingRecorder: LoggingReceiptProcessingTimingRecorder(),
            sharedInbox: sharedInbox
        )
    }

    func makePipeline(
        context: ModelContext,
        defaultCurrencyCode: String = Locale.current.currency?.identifier ?? "USD",
        locale: Locale = .current
    ) -> ReceiptProcessingPipeline {
        ReceiptProcessingPipeline(
            context: context,
            ocrService: ocrService,
            modelService: modelService,
            availabilityProvider: availabilityProvider,
            parser: ReceiptParser(
                referenceDate: Date(),
                defaultCurrencyCode: defaultCurrencyCode,
                locale: locale
            ),
            mergePolicy: ReceiptMergePolicy(),
            locale: locale,
            timingRecorder: timingRecorder
        )
    }

    func makeUITestFixturePages(sourceType: ReceiptAttachmentSourceType) throws -> [CapturedReceiptPage] {
        try receiptCapturePageBuilder.makePages(
            from: [Self.makeReceiptFixtureImage()],
            sourceType: sourceType
        )
    }

    private static func makeReceiptFixtureImage() -> ReceiptPlatformImage {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            let lines = [
                "REWE CITY",
                "14.06.2026",
                "SUMME 84,50 EUR",
                "Bar"
            ]
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 54, weight: .semibold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
            lines.joined(separator: "\n").draw(
                in: CGRect(x: 80, y: 220, width: 740, height: 520),
                withAttributes: attributes
            )
        }
        #elseif os(macOS)
        let image = NSImage(size: CGSize(width: 900, height: 1200))
        image.lockFocus()
        NSColor.textBackgroundColor.setFill()
        CGRect(x: 0, y: 0, width: 900, height: 1200).fill()
        let lines = [
            "REWE CITY",
            "14.06.2026",
            "SUMME 84,50 EUR",
            "Bar"
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 54, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        lines.joined(separator: "\n").draw(
            in: CGRect(x: 80, y: 220, width: 740, height: 520),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
        #endif
    }

    private static func makeSharedInbox(launchConfiguration: AppLaunchConfiguration) -> SharedReceiptInbox? {
        if launchConfiguration.seedSharedInbox {
            return makeSeededUITestSharedInbox()
        }
        return try? SharedReceiptInbox()
    }

    private static func makeSeededUITestSharedInbox() -> SharedReceiptInbox? {
        do {
            let inbox = try SharedReceiptInbox(containerURL: uiTestSharedInboxContainerURL)
            try inbox.removeAll()
            guard let imageData = makeReceiptFixtureImage().receiptJPEGData(compressionQuality: 0.9) else {
                return inbox
            }
            _ = try inbox.write(images: [imageData])
            return inbox
        } catch {
            return nil
        }
    }

    private static var uiTestSharedInboxContainerURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("IntelliExpenseUITestSharedInbox", isDirectory: true)
    }
}

struct NonBlockingModelAvailabilityProvider: ModelAvailabilityProviding {
    var base: any ModelAvailabilityProviding

    func currentAvailability() async -> ModelAvailabilityStatus {
        let status = await base.currentAvailability()
        switch status {
        case .appleIntelligenceNotEnabled, .deviceNotEligible:
            return .unknownUnavailable
        case .available, .modelNotReady, .unknownUnavailable:
            return status
        }
    }

    func supportsLocale(_ locale: Locale) -> Bool {
        base.supportsLocale(locale)
    }

    func supportsImageInput() -> Bool {
        base.supportsImageInput()
    }
}

private struct SlowFakeOCRService: OCRServicing {
    var result: OCRResult

    func recognizeText(from pages: [OCRInputPage]) async throws -> OCRResult {
        _ = pages
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return result
    }
}