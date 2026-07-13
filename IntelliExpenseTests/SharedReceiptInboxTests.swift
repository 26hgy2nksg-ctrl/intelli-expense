import ExpenseCore
import SwiftData
import UIKit
import XCTest
@testable import IntelliExpense

final class SharedReceiptInboxTests: XCTestCase {
    private var temporaryContainerURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryContainerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedReceiptInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryContainerURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryContainerURL {
            try? FileManager.default.removeItem(at: temporaryContainerURL)
        }
        try super.tearDownWithError()
    }

    func testWriteCreatesManifestAndPendingItemPreservesPageOrder() throws {
        let inbox = try SharedReceiptInbox(containerURL: temporaryContainerURL)

        _ = try inbox.write(images: [Data([0x01]), Data([0x02]), Data([0x03])])

        let item = try XCTUnwrap(try inbox.pendingItems().first)
        XCTAssertEqual(item.pageFilenames, ["page-0.jpg", "page-1.jpg", "page-2.jpg"])
        XCTAssertEqual(try item.readPageData(), [Data([0x01]), Data([0x02]), Data([0x03])])
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.appendingPathComponent("manifest.json").path))
    }

    func testPendingIgnoresIncompleteFoldersAndSweepDeletesOldIncompleteFolders() throws {
        let inbox = try SharedReceiptInbox(containerURL: temporaryContainerURL)
        let incompleteURL = temporaryContainerURL
            .appendingPathComponent("SharedInbox", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: incompleteURL, withIntermediateDirectories: true)
        try Data([0x01]).write(to: incompleteURL.appendingPathComponent("page-0.jpg"))
        let oldDate = Date(timeIntervalSinceNow: -48 * 60 * 60)
        try FileManager.default.setAttributes([.creationDate: oldDate, .modificationDate: oldDate], ofItemAtPath: incompleteURL.path)

        XCTAssertTrue(try inbox.pendingItems().isEmpty)

        try inbox.sweep(olderThan: Date(timeIntervalSinceNow: -24 * 60 * 60))

        XCTAssertFalse(FileManager.default.fileExists(atPath: incompleteURL.path))
    }

    func testRemoveDeletesItemAndPendingItemsAreSortedOldestFirst() throws {
        let inbox = try SharedReceiptInbox(containerURL: temporaryContainerURL)
        let firstURL = try inbox.write(images: [Data([0x01])])
        Thread.sleep(forTimeInterval: 0.01)
        let secondURL = try inbox.write(images: [Data([0x02])])

        let items = try inbox.pendingItems()
        XCTAssertEqual(items.map(\.url), [firstURL, secondURL])

        try inbox.remove(items[0])

        XCTAssertEqual(try inbox.pendingItems().map(\.url), [secondURL])
    }

    @MainActor
    func testDrainProcessesFirstInboxItemAndLeavesSecondUntilReviewCompletes() async throws {
        let inbox = try SharedReceiptInbox(containerURL: temporaryContainerURL)
        _ = try inbox.write(images: [try makeFixtureImageData(label: "First")])
        _ = try inbox.write(images: [try makeFixtureImageData(label: "Second")])
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        let services = AppServices.make(launchConfiguration: AppLaunchConfiguration(arguments: ["-UITestFakeServices"]))
        let processor = SharedReceiptInboxDrainProcessor(
            inbox: inbox,
            pageBuilder: services.receiptCapturePageBuilder,
            makePipeline: {
                services.makePipeline(
                    context: context,
                    defaultCurrencyCode: "USD",
                    locale: Locale(identifier: "de_DE")
                )
            }
        )

        let firstItem = try XCTUnwrap(try inbox.pendingItems().first)
        let form = try await processor.process(firstItem, defaultCurrencyCode: "USD", defaultPaymentMethod: .card)

        XCTAssertEqual(form.vendor, "REWE CITY")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptDraft>()).count, 1)
        XCTAssertEqual(try inbox.pendingItems().count, 1)
    }

    private func makeFixtureImageData(label: String) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 420))
        let image = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 420))
            label.draw(
                in: CGRect(x: 24, y: 160, width: 272, height: 100),
                withAttributes: [
                    .font: UIFont.preferredFont(forTextStyle: .title1),
                    .foregroundColor: UIColor.label
                ]
            )
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}
