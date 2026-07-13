import PDFKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PDFReceiptPageRasterizerError: Error, Equatable {
    case unreadablePDF
    case emptyPDF
}

struct PDFReceiptPageRasterizer {
    var pageBuilder: ReceiptCapturePageBuilder

    init(pageBuilder: ReceiptCapturePageBuilder = ReceiptCapturePageBuilder()) {
        self.pageBuilder = pageBuilder
    }

    func capturedPages(fromPDFData data: Data) throws -> [CapturedReceiptPage] {
        guard let document = PDFDocument(data: data) else {
            throw PDFReceiptPageRasterizerError.unreadablePDF
        }
        guard document.pageCount > 0 else {
            throw PDFReceiptPageRasterizerError.emptyPDF
        }

        let images = (0..<document.pageCount).compactMap { index in
            document.page(at: index).map(render)
        }
        return try pageBuilder.makePages(from: images, sourceType: .fileImport)
    }

    private func render(page: PDFPage) -> ReceiptPlatformImage {
        let bounds = page.bounds(for: .mediaBox)
        #if os(iOS)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true

        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))

            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        #elseif os(macOS)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: bounds.size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
        }
        image.unlockFocus()
        return image
        #endif
    }
}
