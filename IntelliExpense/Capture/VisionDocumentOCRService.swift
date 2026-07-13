import ExpenseCore
import Foundation
import Vision

struct VisionDocumentOCRService: OCRServicing {
    typealias PageRecognizer = @Sendable (OCRInputPage) async throws -> OCRTextPage

    private let pageRecognizer: PageRecognizer

    init(pageRecognizer: PageRecognizer? = nil) {
        self.pageRecognizer = pageRecognizer ?? Self.recognizePage
    }

    static func makeReceiptRecognitionRequest() -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.maximumCandidateCount = 1
        return request
    }

    func recognizeText(from pages: [OCRInputPage]) async throws -> OCRResult {
        var textPages: [OCRTextPage] = []
        var skippedPageIndices: [Int] = []
        for page in pages {
            do {
                textPages.append(try await pageRecognizer(page))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedPageIndices.append(page.pageIndex)
            }
        }

        return OCRResult(pages: textPages, skippedPageIndices: skippedPageIndices)
    }

    private static func recognizePage(_ page: OCRInputPage) async throws -> OCRTextPage {
        let request = makeReceiptRecognitionRequest()
        let observations = try await request.perform(on: page.imageData)
        let text = observations
            .map(\.document.text.transcript)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .joined(separator: "\n")
        return OCRTextPage(
            id: page.id,
            pageIndex: page.pageIndex,
            text: text,
            confidence: meanConfidence(from: observations)
        )
    }

    private static func meanConfidence(from observations: [DocumentObservation]) -> Double? {
        guard observations.isEmpty == false else { return nil }
        let total = observations.reduce(Float.zero) { partialResult, observation in
            partialResult + observation.confidence
        }
        return Double(total / Float(observations.count))
    }
}
