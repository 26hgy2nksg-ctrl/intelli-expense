import UIKit
import XCTest
@testable import IntelliExpense

@MainActor
final class CaptureInputTests: XCTestCase {
    func testImagePreprocessorBuildsCompressedOrderedPagesWithThumbnails() throws {
        let builder = ReceiptCapturePageBuilder(maxImageDimension: 600, thumbnailDimension: 160, compressionQuality: 0.72)

        let pages = try builder.makePages(
            from: [
                makeImage(width: 900, height: 1200, color: .systemBlue),
                makeImage(width: 1000, height: 700, color: .systemGreen)
            ],
            sourceType: .cameraScan
        )

        XCTAssertEqual(pages.map(\.pageIndex), [0, 1])
        XCTAssertEqual(pages.map(\.sourceType), [.cameraScan, .cameraScan])
        for page in pages {
            let fullImage = try XCTUnwrap(UIImage(data: page.imageData))
            let thumbnail = try XCTUnwrap(page.thumbnailData.flatMap(UIImage.init(data:)))
            let promptImage = try XCTUnwrap(page.promptImageData.flatMap(UIImage.init(data:)))
            XCTAssertLessThanOrEqual(max(fullImage.size.width, fullImage.size.height), 601)
            XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 161)
            XCTAssertLessThanOrEqual(max(promptImage.size.width, promptImage.size.height), 601)
            XCTAssertEqual(page.promptImageLongEdgePixels, Int(max(promptImage.size.width, promptImage.size.height)))
        }
    }

    func testDefaultImagePreprocessorStores2600PixelLongSideWithoutUpscaling() throws {
        let builder = ReceiptCapturePageBuilder()

        let largePages = try builder.makePages(
            from: [makeImage(width: 4000, height: 3000, color: .systemBlue)],
            sourceType: .photoImport
        )
        let largeFullImage = try XCTUnwrap(UIImage(data: largePages[0].imageData))
        let largeThumbnail = try XCTUnwrap(largePages[0].thumbnailData.flatMap(UIImage.init(data:)))
        XCTAssertEqual(longSide(of: largeFullImage), 2600, accuracy: 1)
        XCTAssertEqual(longSide(of: largeThumbnail), 320, accuracy: 1)
        let promptImage = try XCTUnwrap(largePages[0].promptImageData.flatMap(UIImage.init(data:)))
        XCTAssertEqual(longSide(of: promptImage), 1280, accuracy: 1)

        let smallPages = try builder.makePages(
            from: [makeImage(width: 1200, height: 800, color: .systemGreen)],
            sourceType: .photoImport
        )
        let smallFullImage = try XCTUnwrap(UIImage(data: smallPages[0].imageData))
        XCTAssertEqual(longSide(of: smallFullImage), 1200, accuracy: 1)
    }

    func testImageDataImporterRejectsUnreadableData() {
        let builder = ReceiptCapturePageBuilder()

        XCTAssertThrowsError(
            try builder.makePages(fromImageData: [Data([0x00, 0x01])], sourceType: .photoImport)
        ) { error in
            XCTAssertEqual(error as? ReceiptCapturePageBuilderError, .unreadableImageData(pageIndex: 0))
        }
    }

    func testPDFRasterizerReturnsOneCapturedPagePerPDFPageInOrder() throws {
        let rasterizer = PDFReceiptPageRasterizer(
            pageBuilder: ReceiptCapturePageBuilder(maxImageDimension: 500, thumbnailDimension: 120)
        )

        let pages = try rasterizer.capturedPages(fromPDFData: makePDFData(pageCount: 2))

        XCTAssertEqual(pages.map(\.pageIndex), [0, 1])
        XCTAssertEqual(pages.map(\.sourceType), [.fileImport, .fileImport])
        XCTAssertTrue(pages.allSatisfy { $0.imageData.isEmpty == false && ($0.thumbnailData?.isEmpty == false) })
    }

    func testFileIngestionProcessorBuildsOrderedPagesFromMixedFileURLs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("receipt.jpg")
        let pdfURL = directory.appendingPathComponent("receipt.pdf")
        let imageData = try XCTUnwrap(makeImage(width: 900, height: 1200, color: .systemBlue).jpegData(compressionQuality: 0.9))
        try imageData.write(to: imageURL)
        try makePDFData(pageCount: 2).write(to: pdfURL)

        let builder = ReceiptCapturePageBuilder(maxImageDimension: 500, thumbnailDimension: 120)
        let processor = ReceiptFileIngestionProcessor(
            pageBuilder: builder,
            pdfRasterizer: PDFReceiptPageRasterizer(pageBuilder: builder),
            makePipeline: { fatalError("This test covers file-to-page ingestion only.") }
        )

        let pages = try await processor.capturedPages(fromFileURLs: [imageURL, pdfURL])

        XCTAssertEqual(pages.map(\.pageIndex), [0, 1, 2])
        XCTAssertEqual(pages.map(\.sourceType), [.fileImport, .fileImport, .fileImport])
        XCTAssertTrue(pages.allSatisfy { $0.imageData.isEmpty == false && ($0.thumbnailData?.isEmpty == false) })
    }

    func testDocumentCameraSupportCanBeInjectedForSimulatorGate() {
        let supported = DocumentCameraSupport(isSupported: { true })
        let unsupported = DocumentCameraSupport(isSupported: { false })

        XCTAssertTrue(supported.canScanDocuments)
        XCTAssertFalse(unsupported.canScanDocuments)
    }

    private func makeImage(width: CGFloat, height: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        }
    }

    private func longSide(of image: UIImage) -> CGFloat {
        max(image.size.width, image.size.height)
    }

    private func makePDFData(pageCount: Int) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 180, height: 260))
        return renderer.pdfData { context in
            for index in 0..<pageCount {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 180, height: 260))
                ("Receipt page \(index + 1)" as NSString).draw(at: CGPoint(x: 24, y: 24), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: UIColor.black
                ])
            }
        }
    }
}
