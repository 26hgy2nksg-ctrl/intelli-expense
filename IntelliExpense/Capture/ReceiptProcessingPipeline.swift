import ExpenseCore
import Foundation
import OSLog
import SwiftData

struct CapturedReceiptPage: Equatable, Sendable {
    var id: String
    var imageData: Data
    var thumbnailData: Data?
    var promptImageData: Data?
    var promptImageLongEdgePixels: Int?
    var pageIndex: Int
    var sourceType: ReceiptAttachmentSourceType

    init(
        id: String = UUID().uuidString,
        imageData: Data,
        thumbnailData: Data? = nil,
        promptImageData: Data? = nil,
        promptImageLongEdgePixels: Int? = nil,
        pageIndex: Int,
        sourceType: ReceiptAttachmentSourceType
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.promptImageData = promptImageData
        self.promptImageLongEdgePixels = promptImageLongEdgePixels
        self.pageIndex = pageIndex
        self.sourceType = sourceType
    }
}

enum ReceiptProcessingNotice: Equatable {
    case smartExtractionPreparing
    case smartExtractionTimedOut
    case unsupportedReceiptLanguage
    case smartExtractionUnavailable
    case noReceiptTextFound
}

enum ReceiptProcessingStage: Equatable {
    case readingText
    case understandingReceipt
}

enum ReceiptProcessingError: Error, Equatable {
    case noPages
    case blockedByModelAvailability(ModelAvailabilityStatus)
}

struct ReceiptProcessingResult {
    var draft: ReceiptDraft
    var mergedReceipt: MergedReceipt
    var notice: ReceiptProcessingNotice?
}

struct ReceiptProcessingTiming: Equatable, Sendable {
    var pageCount: Int
    var ocrSeconds: TimeInterval?
    var deterministicParseSeconds: TimeInterval?
    var modelExtractionSeconds: TimeInterval?
    var modelAttemptCount: Int
    var modelAttemptSeconds: [TimeInterval]
    var totalSeconds: TimeInterval
    var notice: ReceiptProcessingNotice?
    var ocrConfidence: Double?
    var skippedOCRPageIndices: [Int]

    init(
        pageCount: Int,
        ocrSeconds: TimeInterval? = nil,
        deterministicParseSeconds: TimeInterval? = nil,
        modelExtractionSeconds: TimeInterval? = nil,
        modelAttemptCount: Int = 0,
        modelAttemptSeconds: [TimeInterval] = [],
        totalSeconds: TimeInterval = 0,
        notice: ReceiptProcessingNotice? = nil,
        ocrConfidence: Double? = nil,
        skippedOCRPageIndices: [Int] = []
    ) {
        self.pageCount = pageCount
        self.ocrSeconds = ocrSeconds
        self.deterministicParseSeconds = deterministicParseSeconds
        self.modelExtractionSeconds = modelExtractionSeconds
        self.modelAttemptCount = modelAttemptCount
        self.modelAttemptSeconds = modelAttemptSeconds
        self.totalSeconds = totalSeconds
        self.notice = notice
        self.ocrConfidence = ocrConfidence
        self.skippedOCRPageIndices = skippedOCRPageIndices
    }
}

protocol ReceiptProcessingTimingRecording: Sendable {
    func record(_ timing: ReceiptProcessingTiming)
}

struct NoopReceiptProcessingTimingRecorder: ReceiptProcessingTimingRecording {
    func record(_ timing: ReceiptProcessingTiming) {
        _ = timing
    }
}

struct LoggingReceiptProcessingTimingRecorder: ReceiptProcessingTimingRecording {
    private let logger = Logger(subsystem: "com.nags.intelliexpense", category: "ReceiptProcessing")

    func record(_ timing: ReceiptProcessingTiming) {
        logger.info(
            """
            Receipt processing timing pages=\(timing.pageCount, privacy: .public) \
            ocr=\(format(timing.ocrSeconds), privacy: .public) \
            parse=\(format(timing.deterministicParseSeconds), privacy: .public) \
            model=\(format(timing.modelExtractionSeconds), privacy: .public) \
            modelAttempts=\(timing.modelAttemptCount, privacy: .public) \
            modelAttemptDurations=\(format(timing.modelAttemptSeconds), privacy: .public) \
            total=\(format(timing.totalSeconds), privacy: .public) \
            ocrConfidence=\(formatConfidence(timing.ocrConfidence), privacy: .public) \
            skippedOCRPages=\(timing.skippedOCRPageIndices.description, privacy: .public) \
            notice=\((timing.notice?.logValue ?? "none"), privacy: .public)
            """
        )
    }

    private func format(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "n/a"
        }
        return String(format: "%.3fs", seconds)
    }

    private func formatConfidence(_ confidence: Double?) -> String {
        guard let confidence else { return "n/a" }
        return String(format: "%.3f", confidence)
    }

    private func format(_ durations: [TimeInterval]) -> String {
        durations.map { String(format: "%.3fs", $0) }.joined(separator: ",")
    }
}

@MainActor
final class ReceiptProcessingPipeline {
    private let context: ModelContext
    private let ocrService: any OCRServicing
    private let modelService: any ExtractionModelServicing
    private let availabilityProvider: any ModelAvailabilityProviding
    private let parser: ReceiptParser
    private let mergePolicy: ReceiptMergePolicy
    private let locale: Locale
    private let timingRecorder: any ReceiptProcessingTimingRecording

    init(
        context: ModelContext,
        ocrService: any OCRServicing,
        modelService: any ExtractionModelServicing,
        availabilityProvider: any ModelAvailabilityProviding,
        parser: ReceiptParser,
        mergePolicy: ReceiptMergePolicy = ReceiptMergePolicy(),
        locale: Locale = .current,
        timingRecorder: any ReceiptProcessingTimingRecording = NoopReceiptProcessingTimingRecorder()
    ) {
        self.context = context
        self.ocrService = ocrService
        self.modelService = modelService
        self.availabilityProvider = availabilityProvider
        self.parser = parser
        self.mergePolicy = mergePolicy
        self.locale = locale
        self.timingRecorder = timingRecorder
    }

    func process(
        capturedPages: [CapturedReceiptPage],
        onStage: ((ReceiptProcessingStage) -> Void)? = nil
    ) async throws -> ReceiptProcessingResult {
        guard capturedPages.isEmpty == false else {
            throw ReceiptProcessingError.noPages
        }

        let pipelineStartedAt = Date()
        var timing = ReceiptProcessingTiming(pageCount: capturedPages.count)
        var persistedDraft: ReceiptDraft?
        var latestDeterministicReceipt: ParsedReceipt?
        defer {
            timing.totalSeconds = Date().timeIntervalSince(pipelineStartedAt)
            timingRecorder.record(timing)
        }

        do {
            let availability = await availabilityProvider.currentAvailability()
            guard availability.blocksCapture == false else {
                throw ReceiptProcessingError.blockedByModelAvailability(availability)
            }

            let orderedPages = capturedPages.sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.id < rhs.id
                }
                return lhs.pageIndex < rhs.pageIndex
            }

            let draft = try persistDraftPages(orderedPages)
            persistedDraft = draft
            try Task.checkCancellation()

            onStage?(.readingText)
            let ocrStartedAt = Date()
            let ocrResult = try await ocrService.recognizeText(
                from: orderedPages.map { page in
                    OCRInputPage(id: page.id, pageIndex: page.pageIndex, imageData: page.imageData)
                }
            )
            try Task.checkCancellation()
            timing.ocrSeconds = Date().timeIntervalSince(ocrStartedAt)
            timing.ocrConfidence = ocrResult.aggregateConfidence
            timing.skippedOCRPageIndices = ocrResult.skippedPageIndices

            draft.rawOCRText = ocrResult.rawText
            draft.ocrConfidence = ocrResult.aggregateConfidence
            draft.lastUpdatedAt = Date()
            try context.save()

            guard ocrResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                timing.notice = .noReceiptTextFound
                return ReceiptProcessingResult(
                    draft: draft,
                    mergedReceipt: MergedReceipt(rawText: ocrResult.rawText, requiresManualEntryFallback: true),
                    notice: .noReceiptTextFound
                )
            }

            let parseStartedAt = Date()
            let deterministicReceipt = parser.parse(ocrResult.rawText)
            latestDeterministicReceipt = deterministicReceipt
            timing.deterministicParseSeconds = Date().timeIntervalSince(parseStartedAt)
            let promptEvidence = ReceiptPromptEvidenceBuilder(
                defaultCurrencyCode: deterministicReceipt.currencyCode?.value
                    ?? locale.currency?.identifier
                    ?? "USD"
            )
            .build(rawText: ocrResult.rawText, deterministicReceipt: deterministicReceipt)

            guard availability == .available else {
                let notice = notice(for: availability)
                timing.notice = notice
                return ReceiptProcessingResult(
                    draft: draft,
                    mergedReceipt: mergePolicy.merge(deterministic: deterministicReceipt),
                    notice: notice
                )
            }

            guard availabilityProvider.supportsLocale(locale) else {
                timing.notice = .unsupportedReceiptLanguage
                return ReceiptProcessingResult(
                    draft: draft,
                    mergedReceipt: mergePolicy.merge(deterministic: deterministicReceipt),
                    notice: .unsupportedReceiptLanguage
                )
            }

            try Task.checkCancellation()
            onStage?(.understandingReceipt)
            let modelStartedAt = Date()
            let initialImages = availabilityProvider.supportsImageInput()
                ? modelImages(from: orderedPages)
                : []
            let imageInputAttempted = initialImages.isEmpty == false
            var lastModelError: ExtractionModelError?

            for attemptIndex in 0..<2 {
                let images = attemptIndex == 0 ? initialImages : []
                let attemptStartedAt = Date()
                timing.modelAttemptCount += 1
                do {
                    let modelReceipt = try await modelService.extractReceipt(
                        from: ExtractionModelRequest(
                            rawText: ocrResult.rawText,
                            localeIdentifier: locale.identifier,
                            deterministicReceipt: deterministicReceipt,
                            promptEvidence: promptEvidence,
                            images: images,
                            timeoutSeconds: attemptIndex == 0 ? 22 : 10
                        )
                    )
                    timing.modelAttemptSeconds.append(Date().timeIntervalSince(attemptStartedAt))
                    try Task.checkCancellation()
                    timing.modelExtractionSeconds = Date().timeIntervalSince(modelStartedAt)
                    let validation = ModelOutputEvidenceValidator().validateWithAudit(
                        modelReceipt,
                        against: promptEvidence,
                        imageInputUsed: images.isEmpty == false
                    )
                    draft.modelOutputJSON = try ModelOutputAuditEncoder.json(
                        for: modelReceipt,
                        context: ModelOutputAuditContext(
                            imageInputUsed: imageInputAttempted,
                            attachmentCount: initialImages.count,
                            attachmentLongEdges: initialImages.map(\.longEdgePixels),
                            attemptCount: timing.modelAttemptCount,
                            acceptance: validation.acceptance
                        )
                    )
                    draft.lastUpdatedAt = Date()
                    try context.save()
                    return ReceiptProcessingResult(
                        draft: draft,
                        mergedReceipt: mergePolicy.merge(
                            deterministic: deterministicReceipt,
                            model: validation.validatedReceipt
                        ),
                        notice: nil
                    )
                } catch let error as ExtractionModelError {
                    timing.modelAttemptSeconds.append(Date().timeIntervalSince(attemptStartedAt))
                    lastModelError = error
                    if attemptIndex == 0, isTransientModelFailure(error) {
                        continue
                    }
                    break
                }
            }

            timing.modelExtractionSeconds = Date().timeIntervalSince(modelStartedAt)
            let notice = notice(for: lastModelError ?? .generationFailed("No model response."))
            timing.notice = notice
            return ReceiptProcessingResult(
                draft: draft,
                mergedReceipt: mergePolicy.merge(deterministic: deterministicReceipt),
                notice: notice
            )
        } catch is CancellationError {
            if let persistedDraft {
                let mergedReceipt: MergedReceipt
                if let latestDeterministicReceipt {
                    mergedReceipt = mergePolicy.merge(deterministic: latestDeterministicReceipt)
                } else {
                    mergedReceipt = MergedReceipt(rawText: persistedDraft.rawOCRText, requiresManualEntryFallback: true)
                }
                return ReceiptProcessingResult(
                    draft: persistedDraft,
                    mergedReceipt: mergedReceipt,
                    notice: nil
                )
            }
            throw CancellationError()
        }
    }

    private func persistDraftPages(_ pages: [CapturedReceiptPage]) throws -> ReceiptDraft {
        let draftPages = pages.map { page in
            ReceiptDraftPage(
                imageData: page.imageData,
                thumbnailData: page.thumbnailData,
                pageIndex: page.pageIndex,
                sourceType: page.sourceType
            )
        }
        let draft = ReceiptDraft(pages: draftPages)
        draftPages.forEach { page in
            page.draft = draft
            context.insert(page)
        }
        context.insert(draft)
        try context.save()
        return draft
    }

    private func modelImages(from pages: [CapturedReceiptPage]) -> [ExtractionModelImage] {
        guard let first = pages.first else { return [] }
        let selectedPages = pages.count == 1 ? [first] : [first, pages[pages.count - 1]]
        return selectedPages.compactMap { page in
            guard let imageData = page.promptImageData,
                  let longEdgePixels = page.promptImageLongEdgePixels else {
                return nil
            }
            return ExtractionModelImage(
                pageIndex: page.pageIndex,
                imageData: imageData,
                longEdgePixels: longEdgePixels
            )
        }
    }

    private func isTransientModelFailure(_ error: ExtractionModelError) -> Bool {
        switch error {
        case .timedOut, .generationFailed:
            true
        case .unsupportedLanguageOrLocale, .modelUnavailable, .contextSizeExceeded:
            false
        }
    }

    private func notice(for availability: ModelAvailabilityStatus) -> ReceiptProcessingNotice {
        switch availability {
        case .modelNotReady:
            return .smartExtractionPreparing
        case .available:
            return .smartExtractionUnavailable
        case .appleIntelligenceNotEnabled, .deviceNotEligible, .unknownUnavailable:
            return .smartExtractionUnavailable
        }
    }

    private func notice(for error: ExtractionModelError) -> ReceiptProcessingNotice {
        switch error {
        case .unsupportedLanguageOrLocale:
            return .unsupportedReceiptLanguage
        case .timedOut:
            return .smartExtractionTimedOut
        case .modelUnavailable(let status):
            return notice(for: status)
        case .generationFailed:
            return .smartExtractionUnavailable
        case .contextSizeExceeded:
            return .smartExtractionUnavailable
        }
    }
}

private extension ReceiptProcessingNotice {
    var logValue: String {
        switch self {
        case .smartExtractionPreparing:
            "smartExtractionPreparing"
        case .smartExtractionTimedOut:
            "smartExtractionTimedOut"
        case .unsupportedReceiptLanguage:
            "unsupportedReceiptLanguage"
        case .smartExtractionUnavailable:
            "smartExtractionUnavailable"
        case .noReceiptTextFound:
            "noReceiptTextFound"
        }
    }
}
