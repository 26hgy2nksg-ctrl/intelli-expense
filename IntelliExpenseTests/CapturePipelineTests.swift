import ExpenseCore
import SwiftData
import XCTest
@testable import IntelliExpense

@MainActor
final class CapturePipelineTests: XCTestCase {
    func testPipelinePersistsOrderedDraftPagesRawOCRAndMergesAvailableModel() async throws {
        let context = try makeContext()
        let ocr = SpyOCRService(
            result: OCRResult(
                pages: [
                    OCRTextPage(id: "page-1", pageIndex: 1, text: "SUMME 84,50 EUR", confidence: 0.94),
                    OCRTextPage(id: "page-0", pageIndex: 0, text: "REWE CITY\n14.06.2026", confidence: 0.98)
                ]
            )
        )
        let model = InspectingModelService { request in
            let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
            XCTAssertEqual(drafts.count, 1)
            XCTAssertEqual(drafts[0].rawOCRText, "REWE CITY\n14.06.2026\nSUMME 84,50 EUR")
            XCTAssertEqual(request.localeIdentifier, "de_DE")
            XCTAssertEqual(request.deterministicReceipt?.vendor?.value, "REWE CITY")
            XCTAssertEqual(request.promptEvidence?.vendorCandidates.first?.text, "REWE CITY")
            XCTAssertTrue(request.promptEvidence?.promptText.contains("OCR evidence") ?? false)
            XCTAssertTrue(request.promptEvidence?.promptText.contains("SUMME 84,50 EUR") ?? false)
            XCTAssertTrue(request.images.isEmpty)
            return ModelExtractedReceipt(
                paymentMethod: .known(primary: .cash),
                expenseType: .known(primary: .food)
            )
        }
        let pipeline = makePipeline(
            context: context,
            ocrService: ocr,
            modelService: model,
            availability: .available,
            locale: Locale(identifier: "de_DE")
        )

        let result = try await pipeline.process(
            capturedPages: [
                CapturedReceiptPage(imageData: Data([0x01]), thumbnailData: Data([0x11]), pageIndex: 1, sourceType: .photoImport),
                CapturedReceiptPage(imageData: Data([0x00]), thumbnailData: Data([0x10]), pageIndex: 0, sourceType: .photoImport)
            ]
        )

        let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(orderedPages(in: drafts[0]).map(\.pageIndex), [0, 1])
        XCTAssertEqual(orderedPages(in: drafts[0]).map(\.imageData), [Data([0x00]), Data([0x01])])
        XCTAssertEqual(ocr.receivedPages.map(\.pageIndex), [0, 1])
        XCTAssertEqual(result.draft.rawOCRText, "REWE CITY\n14.06.2026\nSUMME 84,50 EUR")
        XCTAssertEqual(result.mergedReceipt.vendor.primary?.value, "REWE CITY")
        XCTAssertEqual(result.mergedReceipt.totalAmount.primary?.value, Decimal(string: "84.50")!)
        XCTAssertEqual(result.mergedReceipt.paymentMethod.primary?.value, .cash)
        XCTAssertEqual(result.mergedReceipt.expenseType.primary?.value, .food)
        XCTAssertNil(result.notice)
    }

    func testModelNotReadyUsesDeterministicExtractionWithoutCallingModel() async throws {
        let context = try makeContext()
        let model = InspectingModelService { _ in
            XCTFail("Model should not be called while it is still downloading.")
            return ModelExtractedReceipt()
        }
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Berlin Cab Co\nTotal EUR 41.20\nVISA")])),
            modelService: model,
            availability: .modelNotReady
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x03]), pageIndex: 0, sourceType: .cameraScan)])

        XCTAssertEqual(result.notice, .smartExtractionPreparing)
        XCTAssertEqual(result.mergedReceipt.vendor.primary?.value, "Berlin Cab Co")
        XCTAssertEqual(result.mergedReceipt.paymentMethod.primary?.value, .card)
        XCTAssertEqual(result.mergedReceipt.totalAmount.primary?.value, Decimal(string: "41.20")!)
    }

    func testProcessingStagesAreTruthfulForModelAvailabilityAndEmptyOCR() async throws {
        var availableStages: [ReceiptProcessingStage] = []
        let available = makePipeline(
            context: try makeContext(),
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .available
        )
        _ = try await available.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x01]), pageIndex: 0, sourceType: .cameraScan)]) {
            availableStages.append($0)
        }
        XCTAssertEqual(availableStages, [.readingText, .understandingReceipt])

        var unavailableStages: [ReceiptProcessingStage] = []
        let unavailable = makePipeline(
            context: try makeContext(),
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .modelNotReady
        )
        _ = try await unavailable.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x02]), pageIndex: 0, sourceType: .cameraScan)]) {
            unavailableStages.append($0)
        }
        XCTAssertEqual(unavailableStages, [.readingText])

        var emptyStages: [ReceiptProcessingStage] = []
        let emptyOCR = makePipeline(
            context: try makeContext(),
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "   ")])),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .available
        )
        _ = try await emptyOCR.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x03]), pageIndex: 0, sourceType: .cameraScan)]) {
            emptyStages.append($0)
        }
        XCTAssertEqual(emptyStages, [.readingText])
    }

    func testUnsupportedReceiptLanguageFallsBackToDeterministicReview() async throws {
        let context = try makeContext()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: ThrowingModelService(error: ExtractionModelError.unsupportedLanguageOrLocale("receipt")),
            availability: .available
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x04]), pageIndex: 0, sourceType: .fileImport)])

        XCTAssertEqual(result.notice, .unsupportedReceiptLanguage)
        XCTAssertEqual(result.mergedReceipt.vendor.primary?.value, "Cafe")
        XCTAssertEqual(result.mergedReceipt.paymentMethod.primary?.value, .cash)
        XCTAssertFalse(result.mergedReceipt.requiresManualEntryFallback)
    }

    func testUnsupportedUILocalePreflightSkipsModelAndFallsBackToDeterministicReview() async throws {
        let context = try makeContext()
        let model = InspectingModelService { _ in
            XCTFail("Unsupported UI locale should be caught before generation.")
            return ModelExtractedReceipt()
        }
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: model,
            availability: .available,
            locale: Locale(identifier: "zz_ZZ"),
            supportsLocale: false
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x15]), pageIndex: 0, sourceType: .photoImport)])

        XCTAssertEqual(result.notice, .unsupportedReceiptLanguage)
        XCTAssertEqual(result.mergedReceipt.vendor.primary?.value, "Cafe")
        XCTAssertEqual(result.mergedReceipt.paymentMethod.primary?.value, .cash)
    }

    func testParserUsesSettingsDefaultCurrencyWhenOCRHasNoCurrencyMarker() async throws {
        let context = try makeContext()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal 12.40\nCash")])),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .modelNotReady,
            defaultCurrencyCode: "CAD"
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x16]), pageIndex: 0, sourceType: .photoImport)])

        XCTAssertEqual(result.mergedReceipt.currencyCode.primary?.value, "CAD")
    }

    func testGarbageOCRStillPreservesImageAndOpensManualFallbackReview() async throws {
        let context = try makeContext()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "   ")])),
            modelService: ThrowingModelService(error: ExtractionModelError.generationFailed("should not run")),
            availability: .available
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x05]), pageIndex: 0, sourceType: .photoImport)])

        XCTAssertEqual(result.notice, .noReceiptTextFound)
        XCTAssertTrue(result.mergedReceipt.requiresManualEntryFallback)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptDraft>()).first?.pages?.first?.imageData, Data([0x05]))
    }

    func testBlockingAvailabilityPreventsCaptureDraftCreation() async throws {
        let context = try makeContext()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [])),
            modelService: ThrowingModelService(error: ExtractionModelError.generationFailed("should not run")),
            availability: .appleIntelligenceNotEnabled
        )

        do {
            _ = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x06]), pageIndex: 0, sourceType: .cameraScan)])
            XCTFail("Capture should be blocked when Apple Intelligence is disabled.")
        } catch ReceiptProcessingError.blockedByModelAvailability(let status) {
            XCTAssertEqual(status, .appleIntelligenceNotEnabled)
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
    }

    func testPipelineRecordsStageTimingWhenModelTimesOut() async throws {
        let context = try makeContext()
        let timingRecorder = RecordingTimingRecorder()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: ThrowingModelService(error: ExtractionModelError.timedOut),
            availability: .available,
            timingRecorder: timingRecorder
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x07]), pageIndex: 0, sourceType: .photoImport)])

        XCTAssertEqual(result.notice, .smartExtractionTimedOut)
        let timing = try XCTUnwrap(timingRecorder.recordedTimings.first)
        XCTAssertEqual(timing.pageCount, 1)
        XCTAssertNotNil(timing.ocrSeconds)
        XCTAssertNotNil(timing.deterministicParseSeconds)
        XCTAssertNotNil(timing.modelExtractionSeconds)
        XCTAssertEqual(timing.modelAttemptCount, 2)
        XCTAssertEqual(timing.modelAttemptSeconds.count, 2)
        XCTAssertGreaterThanOrEqual(timing.totalSeconds, 0)
        XCTAssertEqual(timing.notice, .smartExtractionTimedOut)
    }

    func testPipelineWritesModelAuditJSONOnSuccessfulModelPath() async throws {
        let context = try makeContext()
        let modelReceipt = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "12.40")!),
            currencyCode: .known(primary: "USD"),
            paymentMethod: .known(primary: .cash),
            expenseType: .known(primary: .food)
        )
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: FakeExtractionModelService(result: .success(modelReceipt)),
            availability: .available
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x08]), pageIndex: 0, sourceType: .photoImport)])

        let json = try XCTUnwrap(result.draft.modelOutputJSON)
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["version"] as? Int, 2)
        XCTAssertEqual(decoded?["imageInputUsed"] as? Bool, false)
        XCTAssertEqual(decoded?["attemptCount"] as? Int, 1)
    }

    func testPipelinePersistsRawModelAuditButMergesEvidenceValidatedModelValues() async throws {
        let context = try makeContext()
        let modelReceipt = ModelExtractedReceipt(
            totalAmount: .known(primary: Decimal(string: "999999")!),
            currencyCode: .known(primary: "USD"),
            paymentMethod: .known(primary: .cash),
            expenseType: .known(primary: .food)
        )
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nInvoice 999999\nTotal USD 12.40\nCash")])),
            modelService: FakeExtractionModelService(result: .success(modelReceipt)),
            availability: .available
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x18]), pageIndex: 0, sourceType: .photoImport)])

        let json = try XCTUnwrap(result.draft.modelOutputJSON)
        XCTAssertTrue(json.contains(#""value":"999999""#))
        XCTAssertEqual(result.mergedReceipt.totalAmount.options.map(\.value), [Decimal(string: "12.40")!])
        XCTAssertEqual(result.mergedReceipt.totalAmount.options.map(\.source), [.deterministic])
    }

    func testPipelineLeavesModelAuditJSONNilOnTimeoutFallback() async throws {
        let context = try makeContext()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: ThrowingModelService(error: .timedOut),
            availability: .available
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x09]), pageIndex: 0, sourceType: .photoImport)])

        XCTAssertNil(result.draft.modelOutputJSON)
    }

    func testImageCapablePipelineAttachesFirstAndLastPromptImagesOnly() async throws {
        let context = try makeContext()
        let model = InspectingModelService { request in
            XCTAssertEqual(request.images.map(\.pageIndex), [0, 2])
            XCTAssertEqual(request.images.map(\.longEdgePixels), [1_280, 1_280])
            return ModelExtractedReceipt(vendor: .known(primary: "FADED CAFE"))
        }
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "OCR STORE\nTotal USD 12.40")])),
            modelService: model,
            availability: .available,
            supportsImageInput: true
        )

        let result = try await pipeline.process(capturedPages: [
            promptPage(index: 0, byte: 0x20),
            promptPage(index: 1, byte: 0x21),
            promptPage(index: 2, byte: 0x22)
        ])

        XCTAssertEqual(result.mergedReceipt.vendor.options.last?.value, "FADED CAFE")
        XCTAssertEqual(result.mergedReceipt.vendor.options.last?.confidence, .low)
        let decoded = try XCTUnwrap(result.draft.modelOutputJSON).data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertEqual(decoded?["imageInputUsed"] as? Bool, true)
        XCTAssertEqual(decoded?["attachmentCount"] as? Int, 2)
    }

    func testTransientFailureRetriesOnceWithoutImagesAndRecordsBothAttempts() async throws {
        let context = try makeContext()
        let timingRecorder = RecordingTimingRecorder()
        let model = AttemptingModelService(results: [
            .failure(.generationFailed("vision failed")),
            .success(ModelExtractedReceipt(expenseType: .known(primary: .food)))
        ])
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40")])),
            modelService: model,
            availability: .available,
            supportsImageInput: true,
            timingRecorder: timingRecorder
        )

        let result = try await pipeline.process(capturedPages: [promptPage(index: 0, byte: 0x30)])

        XCTAssertEqual(model.requests.count, 2)
        XCTAssertEqual(model.requests[0].images.count, 1)
        XCTAssertTrue(model.requests[1].images.isEmpty)
        XCTAssertEqual(model.requests.map(\.timeoutSeconds), [22, 10])
        XCTAssertEqual(result.mergedReceipt.expenseType.primary?.value, .food)
        XCTAssertNil(result.notice)
        XCTAssertEqual(timingRecorder.recordedTimings.first?.modelAttemptCount, 2)
        XCTAssertEqual(timingRecorder.recordedTimings.first?.modelAttemptSeconds.count, 2)
    }

    func testUnsupportedLanguageDoesNotRetry() async throws {
        let model = AttemptingModelService(results: [
            .failure(.unsupportedLanguageOrLocale("receipt"))
        ])
        let pipeline = makePipeline(
            context: try makeContext(),
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "p0", pageIndex: 0, text: "Cafe\nTotal USD 12.40")])),
            modelService: model,
            availability: .available,
            supportsImageInput: true
        )

        let result = try await pipeline.process(capturedPages: [promptPage(index: 0, byte: 0x40)])

        XCTAssertEqual(model.requests.count, 1)
        XCTAssertEqual(result.notice, .unsupportedReceiptLanguage)
    }

    func testPipelineStoresAggregateOCRConfidenceAndRecordsItInTiming() async throws {
        let context = try makeContext()
        let timingRecorder = RecordingTimingRecorder()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(
                result: OCRResult(
                    pages: [
                        OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe", confidence: 0.9),
                        OCRTextPage(id: "page-1", pageIndex: 1, text: "Total USD 12.40", confidence: 0.4)
                    ]
                )
            ),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .available,
            timingRecorder: timingRecorder
        )

        let result = try await pipeline.process(
            capturedPages: [
                CapturedReceiptPage(imageData: Data([0x0A]), pageIndex: 0, sourceType: .photoImport),
                CapturedReceiptPage(imageData: Data([0x0B]), pageIndex: 1, sourceType: .photoImport)
            ]
        )

        XCTAssertEqual(result.draft.ocrConfidence, 0.4)
        XCTAssertEqual(timingRecorder.recordedTimings.first?.ocrConfidence, 0.4)
    }

    func testPipelineLeavesOCRConfidenceNilWhenAllPagesAreUnknown() async throws {
        let context = try makeContext()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe", confidence: nil)])),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .available
        )

        let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x0C]), pageIndex: 0, sourceType: .photoImport)])

        XCTAssertNil(result.draft.ocrConfidence)
    }

    func testCancellationDuringOCRKeepsDraftAndReturnsManualFallbackReview() async throws {
        let context = try makeContext()
        let ocr = SuspendingOCRService()
        let pipeline = makePipeline(
            context: context,
            ocrService: ocr,
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availability: .available
        )

        let resultBox = ReceiptProcessingResultBox()
        let task = Task { @MainActor in
            do {
                let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x0D]), pageIndex: 0, sourceType: .photoImport)])
                resultBox.result = .success(result)
            } catch {
                resultBox.result = .failure(error)
            }
        }
        await ocr.waitUntilStarted()
        task.cancel()
        await task.value

        let result = try resultBox.unwrap()
        let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(orderedPages(in: drafts[0]).map(\.imageData), [Data([0x0D])])
        XCTAssertTrue(result.mergedReceipt.requiresManualEntryFallback)
        XCTAssertEqual(result.draft.persistentModelID, drafts[0].persistentModelID)
    }

    func testCancellationDuringModelKeepsDraftAndReturnsDeterministicValues() async throws {
        let context = try makeContext()
        let model = SuspendingModelService()
        let pipeline = makePipeline(
            context: context,
            ocrService: SpyOCRService(result: OCRResult(pages: [OCRTextPage(id: "page-0", pageIndex: 0, text: "Cafe\nTotal USD 12.40\nCash")])),
            modelService: model,
            availability: .available
        )

        let resultBox = ReceiptProcessingResultBox()
        let task = Task { @MainActor in
            do {
                let result = try await pipeline.process(capturedPages: [CapturedReceiptPage(imageData: Data([0x0E]), pageIndex: 0, sourceType: .photoImport)])
                resultBox.result = .success(result)
            } catch {
                resultBox.result = .failure(error)
            }
        }
        await model.waitUntilStarted()
        task.cancel()
        await task.value

        let result = try resultBox.unwrap()
        let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].rawOCRText, "Cafe\nTotal USD 12.40\nCash")
        XCTAssertEqual(result.mergedReceipt.vendor.primary?.value, "Cafe")
        XCTAssertEqual(result.mergedReceipt.totalAmount.primary?.value, Decimal(string: "12.40")!)
        XCTAssertEqual(result.mergedReceipt.paymentMethod.primary?.value, .cash)
    }

    private func makePipeline(
        context: ModelContext,
        ocrService: any OCRServicing,
        modelService: any ExtractionModelServicing,
        availability: ModelAvailabilityStatus,
        locale: Locale = Locale(identifier: "en_US"),
        supportsLocale: Bool = true,
        supportsImageInput: Bool = false,
        defaultCurrencyCode: String = "USD",
        timingRecorder: any ReceiptProcessingTimingRecording = NoopReceiptProcessingTimingRecorder()
    ) -> ReceiptProcessingPipeline {
        ReceiptProcessingPipeline(
            context: context,
            ocrService: ocrService,
            modelService: modelService,
            availabilityProvider: FakeModelAvailabilityProvider(
                status: availability,
                supportsLocale: supportsLocale,
                supportsImageInput: supportsImageInput
            ),
            parser: ReceiptParser(referenceDate: date(2026, 12, 31), defaultCurrencyCode: defaultCurrencyCode, locale: locale),
            mergePolicy: ReceiptMergePolicy(),
            locale: locale,
            timingRecorder: timingRecorder
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
    }

    private func orderedPages(in draft: ReceiptDraft) -> [ReceiptDraftPage] {
        (draft.pages ?? []).sorted { $0.pageIndex < $1.pageIndex }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }

    private func promptPage(index: Int, byte: UInt8) -> CapturedReceiptPage {
        CapturedReceiptPage(
            imageData: Data([byte]),
            thumbnailData: nil,
            promptImageData: Data([byte, byte]),
            promptImageLongEdgePixels: 1_280,
            pageIndex: index,
            sourceType: .photoImport
        )
    }
}

@MainActor
private final class ReceiptProcessingResultBox {
    var result: Result<ReceiptProcessingResult, Error>?

    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> ReceiptProcessingResult {
        guard let result else {
            XCTFail("Expected receipt processing result", file: file, line: line)
            throw ReceiptProcessingResultBoxError.missingResult
        }
        return try result.get()
    }
}

private enum ReceiptProcessingResultBoxError: Error {
    case missingResult
}

private final class SpyOCRService: OCRServicing, @unchecked Sendable {
    private let result: OCRResult
    private(set) var receivedPages: [OCRInputPage] = []

    init(result: OCRResult) {
        self.result = result
    }

    func recognizeText(from pages: [OCRInputPage]) async throws -> OCRResult {
        receivedPages = pages
        return result
    }
}

private final class InspectingModelService: ExtractionModelServicing, @unchecked Sendable {
    private let handler: @MainActor (ExtractionModelRequest) throws -> ModelExtractedReceipt

    init(handler: @escaping @MainActor (ExtractionModelRequest) throws -> ModelExtractedReceipt) {
        self.handler = handler
    }

    func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt {
        try await MainActor.run {
            try handler(request)
        }
    }
}

private struct ThrowingModelService: ExtractionModelServicing {
    var error: ExtractionModelError

    func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt {
        _ = request
        throw error
    }
}

private final class AttemptingModelService: ExtractionModelServicing, @unchecked Sendable {
    private let results: [Result<ModelExtractedReceipt, ExtractionModelError>]
    private(set) var requests: [ExtractionModelRequest] = []

    init(results: [Result<ModelExtractedReceipt, ExtractionModelError>]) {
        self.results = results
    }

    func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt {
        requests.append(request)
        let index = min(requests.count - 1, results.count - 1)
        return try results[index].get()
    }
}

private actor SuspendingOCRService: OCRServicing {
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func recognizeText(from pages: [OCRInputPage]) async throws -> OCRResult {
        _ = pages
        started = true
        startContinuation?.resume()
        startContinuation = nil
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return OCRResult(pages: [])
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }
}

private actor SuspendingModelService: ExtractionModelServicing {
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt {
        _ = request
        started = true
        startContinuation?.resume()
        startContinuation = nil
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return ModelExtractedReceipt()
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }
}

private final class RecordingTimingRecorder: ReceiptProcessingTimingRecording, @unchecked Sendable {
    private(set) var recordedTimings: [ReceiptProcessingTiming] = []

    func record(_ timing: ReceiptProcessingTiming) {
        recordedTimings.append(timing)
    }
}
