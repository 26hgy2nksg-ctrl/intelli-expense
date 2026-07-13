import ExpenseCore
import Foundation

@MainActor
struct SharedReceiptInboxDrainProcessor {
    var inbox: SharedReceiptInbox
    var pageBuilder: ReceiptCapturePageBuilder
    var makePipeline: () -> ReceiptProcessingPipeline

    func process(
        _ item: SharedInboxItem,
        defaultCurrencyCode: String,
        defaultPaymentMethod: PaymentMethod,
        onPagesBuilt: (([CapturedReceiptPage]) -> Void)? = nil,
        onStage: ((ReceiptProcessingStage) -> Void)? = nil
    ) async throws -> ReceiptReviewForm {
        let pages = try pageBuilder.makePages(fromImageData: item.readPageData(), sourceType: .photoImport)
        onPagesBuilt?(pages)
        let result = try await makePipeline().process(capturedPages: pages, onStage: onStage)
        try inbox.remove(item)
        return ReceiptReviewForm(
            draft: result.draft,
            mergedReceipt: result.mergedReceipt,
            notice: result.notice,
            defaultCurrencyCode: defaultCurrencyCode,
            defaultPaymentMethod: defaultPaymentMethod
        )
    }
}
