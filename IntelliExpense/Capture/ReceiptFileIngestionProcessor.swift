import ExpenseCore
import Foundation

@MainActor
struct ReceiptFileIngestionProcessor {
    var pageBuilder: ReceiptCapturePageBuilder
    var pdfRasterizer: PDFReceiptPageRasterizer
    var makePipeline: () -> ReceiptProcessingPipeline

    init(
        pageBuilder: ReceiptCapturePageBuilder,
        pdfRasterizer: PDFReceiptPageRasterizer,
        makePipeline: @escaping () -> ReceiptProcessingPipeline
    ) {
        self.pageBuilder = pageBuilder
        self.pdfRasterizer = pdfRasterizer
        self.makePipeline = makePipeline
    }

    func process(
        fileURLs: [URL],
        defaultCurrencyCode: String,
        defaultPaymentMethod: PaymentMethod,
        onPagesBuilt: (([CapturedReceiptPage]) -> Void)? = nil,
        onStage: ((ReceiptProcessingStage) -> Void)? = nil
    ) async throws -> ReceiptReviewForm {
        let pages = try await capturedPages(fromFileURLs: fileURLs)
        onPagesBuilt?(pages)
        let result = try await makePipeline().process(capturedPages: pages, onStage: onStage)
        return ReceiptReviewForm(
            draft: result.draft,
            mergedReceipt: result.mergedReceipt,
            notice: result.notice,
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod
        )
    }

    func capturedPages(fromFileURLs urls: [URL]) async throws -> [CapturedReceiptPage] {
        var pages: [CapturedReceiptPage] = []
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "pdf" {
                pages.append(contentsOf: try pdfRasterizer.capturedPages(fromPDFData: data))
            } else {
                pages.append(
                    contentsOf: try pageBuilder.makePages(
                        fromImageData: [data],
                        sourceType: .fileImport
                    )
                )
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
}

struct ReceiptProcessingOverlayState: Equatable {
    var stage: ReceiptProcessingStage?
    var previewImageData: Data?
}
