import XCTest
@testable import IntelliExpense

final class IntelliExpenseTests: XCTestCase {
    func testAppMetadataUsesStringCatalogKey() {
        XCTAssertEqual(AppMetadata.displayNameKey, "app.title")
    }

    func testReviewPageCountUsesSingularAndPluralCatalogForms() {
        XCTAssertEqual(reviewPageCountText(1), "1 page")
        XCTAssertEqual(reviewPageCountText(2), "2 pages")
    }

    func testFeaturedThumbnailSelectionSkipsPhotoLessReceiptsInRecencyOrder() {
        let now = Date()
        let firstTaxi = Receipt(date: now, expenseType: .taxi, attachments: [])
        let secondTaxi = Receipt(date: now.addingTimeInterval(-60), expenseType: .taxi, attachments: [])
        let food = Receipt(
            date: now.addingTimeInterval(-120),
            expenseType: .food,
            attachments: [ReceiptAttachment(thumbnailData: Data([0x01]), pageIndex: 0)]
        )
        let hotel = Receipt(
            date: now.addingTimeInterval(-180),
            expenseType: .hotel,
            attachments: [ReceiptAttachment(imageData: Data([0x02]), pageIndex: 0)]
        )

        let selected = FeaturedThumbnailSelection.receipts(from: [firstTaxi, secondTaxi, food, hotel])

        XCTAssertEqual(selected.count, 2)
        XCTAssertTrue(selected[0] === food)
        XCTAssertTrue(selected[1] === hotel)
    }

    func testFeaturedThumbnailSelectionLimitsToThreePhotoReceipts() {
        let receipts = (0..<4).map { index in
            Receipt(
                date: Date().addingTimeInterval(TimeInterval(-index)),
                expenseType: .food,
                attachments: [ReceiptAttachment(thumbnailData: Data([UInt8(index + 1)]), pageIndex: 0)]
            )
        }

        XCTAssertEqual(FeaturedThumbnailSelection.receipts(from: receipts).count, 3)
    }

    private func reviewPageCountText(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "review.page.count"), count)
    }
}
