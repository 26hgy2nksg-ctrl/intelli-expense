import ExpenseCore
import FoundationModels
import Vision
import XCTest
@testable import IntelliExpense

final class ReceiptServiceWrapperTests: XCTestCase {
    @MainActor
    func testProductionServicesUseThirtySecondSmartExtractionTimeout() throws {
        let services = AppServices.make(launchConfiguration: AppLaunchConfiguration(arguments: []))
        let modelService = try XCTUnwrap(services.modelService as? FoundationModelReceiptService)

        XCTAssertEqual(FoundationModelReceiptService.defaultTimeoutSeconds, 30)
        XCTAssertEqual(modelService.timeoutSeconds, 30)
    }

    func testVisionDocumentOCRRequestUsesDocumentRecognitionWithAutomaticLanguageDetection() {
        let request = VisionDocumentOCRService.makeReceiptRecognitionRequest()

        XCTAssertTrue(request.textRecognitionOptions.automaticallyDetectLanguage)
        XCTAssertTrue(request.textRecognitionOptions.useLanguageCorrection)
        XCTAssertEqual(request.textRecognitionOptions.maximumCandidateCount, 1)
    }

    func testFoundationModelPromptUsesExactLocaleSteeringPhraseForNonUSEnglish() {
        let promptFactory = FoundationModelReceiptPromptFactory(maxOCRCharacters: 120)

        XCTAssertNil(promptFactory.localeInstructions(for: Locale(identifier: "en_US")))
        XCTAssertEqual(promptFactory.localeInstructions(for: Locale(identifier: "de_DE")), "The person's locale is de_DE.")
    }

    func testFoundationModelPromptNamesTheAppUILanguageForVisibleReasons() {
        let promptFactory = FoundationModelReceiptPromptFactory(maxOCRCharacters: 120)

        let englishPrompt = promptFactory.makePrompt(
            rawText: "Cafe\nTOTAL $10.00",
            deterministicReceipt: nil,
            locale: Locale(identifier: "en_US")
        )
        let germanPrompt = promptFactory.makePrompt(
            rawText: "Cafe\nTOTAL 10,00 EUR",
            deterministicReceipt: nil,
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertFalse(englishPrompt.contains("You MUST write user-visible alternate reasons in English."))
        XCTAssertFalse(germanPrompt.contains("You MUST write user-visible alternate reasons in German."))
        XCTAssertTrue(promptFactory.instructions(locale: Locale(identifier: "en_US")).contains("You MUST write user-visible alternate reasons in English."))
        XCTAssertTrue(promptFactory.instructions(locale: Locale(identifier: "de_DE")).contains("You MUST write user-visible alternate reasons in German."))
    }

    func testFoundationModelPromptUsesCompactOCREvidenceInsteadOfRawTranscript() {
        let promptFactory = FoundationModelReceiptPromptFactory(maxOCRCharacters: 320)
        let longText = [
            "REWE CITY",
            String(repeating: "middle ", count: 40),
            "SUMME 84,50 EUR"
        ].joined(separator: "\n")

        let prompt = promptFactory.makePrompt(
            rawText: longText,
            deterministicReceipt: ParsedReceipt(rawText: longText),
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertTrue(prompt.contains("The person's locale is de_DE."))
        XCTAssertTrue(prompt.contains("OCR evidence"))
        XCTAssertFalse(prompt.contains("OCR text:"))
        XCTAssertTrue(prompt.contains("REWE CITY"))
        XCTAssertTrue(prompt.contains("SUMME 84,50 EUR"))
        XCTAssertFalse(prompt.contains("middle middle middle middle"))
    }

    func testFoundationModelPromptUsesAmountAndVendorEvidenceChecklist() {
        let promptFactory = FoundationModelReceiptPromptFactory(maxOCRCharacters: 800)
        let rawText = """
        BLR SKY BITES - T1
        TRAVEL FOOD SERVICES
        LIMITED
        GST NO: 29ABCDE1234F1Z5
        Inv No: 420001000900123456
        142.86
        150.0îŠ†
        7.14
        Total:
        """
        let deterministic = ParsedReceipt(
            vendor: ParsedField(
                value: "BLR SKY BITES - T1",
                confidence: .medium,
                evidence: "BLR SKY BITES - T1"
            ),
            totalAmount: ParsedField(
                value: Decimal(string: "150.0")!,
                confidence: .low,
                evidence: "150.0îŠ†"
            ),
            currencyCode: ParsedField(value: "INR", confidence: .low, evidence: "150.0îŠ†"),
            rawText: rawText
        )

        let prompt = promptFactory.makePrompt(
            rawText: rawText,
            deterministicReceipt: deterministic,
            locale: Locale(identifier: "en_IN")
        )

        XCTAssertTrue(prompt.contains("vendor: user-facing merchant/store name from vendor evidence"))
        XCTAssertTrue(prompt.contains("totalAmount: final payable total as a plain decimal string"))
        XCTAssertTrue(prompt.contains("choose unknown for totalAmount when final payable total evidence is absent"))
        XCTAssertTrue(prompt.contains("Do not use tax IDs, legal entities, payment lines, addresses, or registration metadata as vendor."))
        XCTAssertTrue(prompt.contains("BLR SKY BITES - T1"))
        XCTAssertTrue(prompt.contains("150.0"))
        XCTAssertFalse(prompt.contains("totalAmount=420001000900123456"))
    }

    func testFoundationModelAvailabilityMapsSystemReasonsToCoreStatuses() {
        XCTAssertEqual(
            FoundationModelAvailabilityProvider.map(.available),
            .available
        )
        XCTAssertEqual(
            FoundationModelAvailabilityProvider.map(.unavailable(.modelNotReady)),
            .modelNotReady
        )
        XCTAssertEqual(
            FoundationModelAvailabilityProvider.map(.unavailable(.appleIntelligenceNotEnabled)),
            .appleIntelligenceNotEnabled
        )
        XCTAssertEqual(
            FoundationModelAvailabilityProvider.map(.unavailable(.deviceNotEligible)),
            .deviceNotEligible
        )
    }

    func testPromptBudgetDerivesInputAndOutputReservationsFromActualContext() {
        let budget = FoundationModelPromptBudget(
            contextSize: 8_192,
            instructionsTokens: 320,
            schemaTokens: 540,
            attachmentTokens: 1_100
        )

        XCTAssertEqual(budget.maximumResponseTokens, 1_200)
        XCTAssertEqual(budget.maximumPromptTokens, 5_032)
        XCTAssertTrue(budget.fits(promptTokens: 5_000))
        XCTAssertFalse(budget.fits(promptTokens: 5_100))
    }

    func testImageCapabilityFailsClosedUnlessBetaGateAndVisionCapabilityBothExist() {
        XCTAssertFalse(FoundationModelImageCapability.isSupported(betaCodeCompiled: false, runtimeHasVision: true))
        XCTAssertFalse(FoundationModelImageCapability.isSupported(betaCodeCompiled: true, runtimeHasVision: false))
        XCTAssertTrue(FoundationModelImageCapability.isSupported(betaCodeCompiled: true, runtimeHasVision: true))
    }

    func testVisionOCRSkipsOnlyFailingPagesAndRecordsTheirIndices() async throws {
        let service = VisionDocumentOCRService { page in
            if page.pageIndex == 1 {
                throw OCRServiceError.configuredFailure("blurred")
            }
            return OCRTextPage(id: page.id, pageIndex: page.pageIndex, text: "page-\(page.pageIndex)", confidence: 0.8)
        }

        let result = try await service.recognizeText(from: [
            OCRInputPage(id: "p0", pageIndex: 0, imageData: Data()),
            OCRInputPage(id: "p1", pageIndex: 1, imageData: Data()),
            OCRInputPage(id: "p2", pageIndex: 2, imageData: Data())
        ])

        XCTAssertEqual(result.pages.map(\.pageIndex), [0, 2])
        XCTAssertEqual(result.rawText, "page-0\npage-2")
        XCTAssertEqual(result.skippedPageIndices, [1])
        XCTAssertEqual(result.aggregateConfidence, 0.8)
    }

    func testVisionOCRReturnsExistingEmptyResultWhenEveryPageFails() async throws {
        let service = VisionDocumentOCRService { page in
            throw OCRServiceError.configuredFailure("page \(page.pageIndex)")
        }

        let result = try await service.recognizeText(from: [
            OCRInputPage(id: "p0", pageIndex: 0, imageData: Data()),
            OCRInputPage(id: "p1", pageIndex: 1, imageData: Data())
        ])

        XCTAssertTrue(result.pages.isEmpty)
        XCTAssertTrue(result.rawText.isEmpty)
        XCTAssertEqual(result.skippedPageIndices, [0, 1])
    }

    func testFoundationModelLocaleSupportAcceptsRegionalLocaleWhenLanguageIsSupported() {
        let supportedLanguages: Set<Locale.Language> = [Locale(identifier: "en_US").language]
        var checkedLocales: [String] = []

        let isSupported = FoundationModelLocaleSupport.isSupported(
            Locale(identifier: "en_IN"),
            supportedLanguages: supportedLanguages
        ) { locale in
            checkedLocales.append(locale.identifier)
            return false
        }

        XCTAssertTrue(isSupported)
        XCTAssertEqual(checkedLocales, ["en_IN"])
    }

    func testFoundationModelLocaleSupportRejectsUnsupportedLanguage() {
        let supportedLanguages: Set<Locale.Language> = [Locale(identifier: "en_US").language]

        let isSupported = FoundationModelLocaleSupport.isSupported(
            Locale(identifier: "zz_ZZ"),
            supportedLanguages: supportedLanguages
        ) { _ in
            false
        }

        XCTAssertFalse(isSupported)
    }
}
