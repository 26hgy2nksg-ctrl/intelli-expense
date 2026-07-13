import Foundation
import CoreGraphics

enum ReceiptCapturePageBuilderError: Error, Equatable {
    case unreadableImageData(pageIndex: Int)
    case imageEncodingFailed(pageIndex: Int)
}

struct ReceiptCapturePageBuilder {
    var maxImageDimension: CGFloat
    var thumbnailDimension: CGFloat
    var promptImageDimension: CGFloat
    var compressionQuality: CGFloat

    init(
        maxImageDimension: CGFloat = 2600,
        thumbnailDimension: CGFloat = 320,
        promptImageDimension: CGFloat = 1280,
        compressionQuality: CGFloat = 0.82
    ) {
        self.maxImageDimension = maxImageDimension
        self.thumbnailDimension = thumbnailDimension
        self.promptImageDimension = promptImageDimension
        self.compressionQuality = compressionQuality
    }

    func makePages(from images: [ReceiptPlatformImage], sourceType: ReceiptAttachmentSourceType) throws -> [CapturedReceiptPage] {
        try images.enumerated().map { index, image in
            try makePage(from: image, pageIndex: index, sourceType: sourceType)
        }
    }

    func makePages(fromImageData imageData: [Data], sourceType: ReceiptAttachmentSourceType) throws -> [CapturedReceiptPage] {
        let images = try imageData.enumerated().map { index, data in
            guard let image = ReceiptPlatformImage.receiptImage(data: data) else {
                throw ReceiptCapturePageBuilderError.unreadableImageData(pageIndex: index)
            }
            return image
        }
        return try makePages(from: images, sourceType: sourceType)
    }

    private func makePage(
        from image: ReceiptPlatformImage,
        pageIndex: Int,
        sourceType: ReceiptAttachmentSourceType
    ) throws -> CapturedReceiptPage {
        let fullSizeImage = image.resizedToFit(maxDimension: maxImageDimension)
        let thumbnail = image.resizedToFit(maxDimension: thumbnailDimension)
        let promptImage = image.resizedToFit(maxDimension: min(maxImageDimension, promptImageDimension))

        guard let fullData = fullSizeImage.receiptJPEGData(compressionQuality: compressionQuality),
              let thumbnailData = thumbnail.receiptJPEGData(compressionQuality: compressionQuality),
              let promptImageData = promptImage.receiptJPEGData(compressionQuality: compressionQuality) else {
            throw ReceiptCapturePageBuilderError.imageEncodingFailed(pageIndex: pageIndex)
        }

        return CapturedReceiptPage(
            imageData: fullData,
            thumbnailData: thumbnailData,
            promptImageData: promptImageData,
            promptImageLongEdgePixels: Int(max(promptImage.size.width, promptImage.size.height)),
            pageIndex: pageIndex,
            sourceType: sourceType
        )
    }
}
