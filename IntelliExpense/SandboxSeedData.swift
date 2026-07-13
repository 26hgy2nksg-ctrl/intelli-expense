#if INTELLI_EXPENSE_SANDBOX
import ExpenseCore
import Foundation
import SwiftData
import UIKit

enum SandboxSeedData {
    static func seedIfNeeded(in context: ModelContext) throws {
        let existingGroups = try context.fetchCount(FetchDescriptor<ExpenseGroup>())
        let existingReceipts = try context.fetchCount(FetchDescriptor<Receipt>())
        guard existingGroups == 0 && existingReceipts == 0 else { return }

        for seed in profileSeeds {
            let group = ExpenseGroup(
                name: seed.name,
                startDate: seed.startDate,
                endDate: seed.endDate,
                notes: seed.notes,
                createdAt: seed.createdAt,
                profileID: seed.profile.id,
                categorySnapshotJSON: seed.profile.defaultSnapshot.jsonString()
            )
            context.insert(group)

            for receiptSeed in seed.receipts {
                let receipt = makeReceipt(from: receiptSeed, group: group)
                context.insert(receipt)
            }
        }

        for seed in unfiledReceipts {
            context.insert(makeReceipt(from: seed, group: nil))
        }

        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        try context.save()
    }

    private static func makeReceipt(from seed: ReceiptSeed, group: ExpenseGroup?) -> Receipt {
        let imageData = makeReceiptImage(seed)
        let thumbnailData = makeReceiptThumbnail(from: imageData)
        let receipt = Receipt(
            vendor: seed.vendor,
            date: seed.date,
            totalAmount: amount(seed.amount),
            currencyCode: seed.currencyCode,
            paymentMethod: seed.paymentMethod,
            notes: seed.notes,
            createdAt: seed.createdAt,
            group: group
        )
        receipt.categoryID = seed.categoryID
        let attachment = ReceiptAttachment(
            imageData: imageData,
            thumbnailData: thumbnailData,
            pageIndex: 0,
            capturedAt: seed.createdAt,
            sourceType: .photoImport,
            receipt: receipt
        )
        let extraction = ExtractionRecord(
            rawOCRText: seed.ocrText,
            modelOutputJSON: seed.modelOutputJSON,
            ocrConfidence: 0.98,
            pipelineVersion: "sandbox-seed-v2",
            extractedAt: seed.createdAt,
            userCorrectedFields: [],
            receipt: receipt
        )
        receipt.attachments = [attachment]
        receipt.extraction = extraction
        return receipt
    }

    private static func makeReceiptImage(_ seed: ReceiptSeed) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { context in
            UIColor(red: 0.98, green: 0.97, blue: 0.92, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))

            UIColor(red: 0.93, green: 0.92, blue: 0.86, alpha: 1).setStroke()
            context.cgContext.setLineWidth(2)
            context.stroke(CGRect(x: 62, y: 64, width: 776, height: 1072))

            let titleStyle = paragraph(.center)
            draw(
                seed.vendor.uppercased(),
                in: CGRect(x: 90, y: 126, width: 720, height: 72),
                font: .monospacedSystemFont(ofSize: 48, weight: .bold),
                color: .black,
                paragraphStyle: titleStyle
            )
            draw(
                seed.location,
                in: CGRect(x: 90, y: 198, width: 720, height: 42),
                font: .systemFont(ofSize: 26, weight: .regular),
                color: UIColor(white: 0.28, alpha: 1),
                paragraphStyle: titleStyle
            )

            drawSeparator(y: 284)
            drawLine("DATE", formattedDate(seed.date), y: 330)
            drawLine("CATEGORY", CategoryResolver.humanize(seed.categoryID).uppercased(), y: 382)
            drawLine("PAYMENT", seed.paymentMethod.rawValue.uppercased(), y: 434)
            drawSeparator(y: 506)

            var y = 560.0
            for item in seed.items {
                drawLine(item.label, item.amount, y: y)
                y += 52
            }

            drawSeparator(y: 840)
            drawLine("TOTAL", "\(seed.currencyCode) \(seed.amount)", y: 892, isTotal: true)
            drawSeparator(y: 982)

            draw(
                "Thank you",
                in: CGRect(x: 90, y: 1024, width: 720, height: 34),
                font: .systemFont(ofSize: 24, weight: .medium),
                color: UIColor(white: 0.22, alpha: 1),
                paragraphStyle: titleStyle
            )
            draw(
                "Business receipt",
                in: CGRect(x: 90, y: 1064, width: 720, height: 32),
                font: .systemFont(ofSize: 18, weight: .regular),
                color: UIColor(white: 0.45, alpha: 1),
                paragraphStyle: titleStyle
            )
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    private static func makeReceiptThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320))
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 240, height: 320))
        }
        return thumbnail.jpegData(compressionQuality: 0.82)
    }

    private static func drawLine(_ left: String, _ right: String, y: CGFloat, isTotal: Bool = false) {
        draw(
            left,
            in: CGRect(x: 112, y: y, width: 430, height: 40),
            font: .monospacedSystemFont(ofSize: isTotal ? 34 : 27, weight: isTotal ? .bold : .medium),
            color: .black,
            paragraphStyle: paragraph(.left)
        )
        draw(
            right,
            in: CGRect(x: 536, y: y, width: 252, height: 40),
            font: .monospacedSystemFont(ofSize: isTotal ? 34 : 27, weight: isTotal ? .bold : .regular),
            color: .black,
            paragraphStyle: paragraph(.right)
        )
    }

    private static func drawSeparator(y: CGFloat) {
        UIColor(white: 0.75, alpha: 1).setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 112, y: y))
        path.addLine(to: CGPoint(x: 788, y: y))
        path.lineWidth = 2
        path.stroke()
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        paragraphStyle: NSMutableParagraphStyle
    ) {
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private static func paragraph(_ alignment: NSTextAlignment) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        return style
    }

    fileprivate static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func amount(_ text: String) -> Decimal {
        NSDecimalNumber(string: text).decimalValue
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date ?? Date()
    }

    private static var profileSeeds: [ProfileSeed] {
        FolderProfileCatalog.all.enumerated().map { profileIndex, profile in
            let metadata = profileMetadata[profile.id] ?? ProfileMetadata(
                name: CategoryResolver.humanize(profile.id),
                location: "Sample location",
                currencyCode: "USD"
            )
            let createdAt = addingDays(-profileIndex * 7, to: date(2026, 7, 6, 9))
            let startDate = profile.isDateBound ? addingDays(1, to: createdAt) : nil
            let endDate = profile.isDateBound
                ? addingDays(profile.defaultCategoryIDs.count, to: createdAt)
                : nil
            let receiptStart = startDate ?? createdAt
            let receipts = profile.defaultCategoryIDs.enumerated().map { categoryIndex, categoryID in
                makeReceiptSeed(
                    metadata: metadata,
                    profileIndex: profileIndex,
                    categoryID: categoryID,
                    categoryIndex: categoryIndex,
                    date: addingDays(categoryIndex, to: receiptStart)
                )
            }
            return ProfileSeed(
                profile: profile,
                name: metadata.name,
                startDate: startDate,
                endDate: endDate,
                notes: "Sandbox example for the \(CategoryResolver.humanize(profile.id)) profile.",
                createdAt: createdAt,
                receipts: receipts
            )
        }
    }

    private static func makeReceiptSeed(
        metadata: ProfileMetadata,
        profileIndex: Int,
        categoryID: String,
        categoryIndex: Int,
        date: Date
    ) -> ReceiptSeed {
        let categoryName = CategoryResolver.humanize(categoryID)
        let wholeAmount = metadata.currencyCode == "JPY"
            ? 2_400 + (profileIndex * 350) + (categoryIndex * 475)
            : 28 + (profileIndex * 11) + (categoryIndex * 17)
        let fractionalAmount = metadata.currencyCode == "JPY" ? 0 : (categoryIndex * 13) % 100
        let amount = String(format: "%d.%02d", wholeAmount, fractionalAmount)
        return ReceiptSeed(
            vendor: "\(categoryName) Example",
            location: metadata.location,
            date: date,
            amount: amount,
            currencyCode: metadata.currencyCode,
            categoryID: categoryID,
            paymentMethod: categoryIndex.isMultiple(of: 3) ? .cash : .card,
            notes: "\(categoryName) example for \(metadata.name).",
            items: [(categoryName.uppercased(), amount)]
        )
    }

    private static func addingDays(_ days: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date) ?? date
    }

    private static let profileMetadata: [String: ProfileMetadata] = [
        "workTrip": ProfileMetadata(name: "Tokyo Product Visit", location: "Tokyo", currencyCode: "JPY"),
        "conference": ProfileMetadata(name: "Berlin Design Summit", location: "Berlin", currencyCode: "EUR"),
        "clientVisit": ProfileMetadata(name: "Singapore Client Workshop", location: "Singapore", currencyCode: "SGD"),
        "homeProject": ProfileMetadata(name: "Kitchen Refresh", location: "Bengaluru", currencyCode: "INR"),
        "medicalClaim": ProfileMetadata(name: "Annual Health Claim", location: "Chennai", currencyCode: "INR"),
        "vehicleCosts": ProfileMetadata(name: "Car Running Costs", location: "Pune", currencyCode: "INR"),
        "businessPurchases": ProfileMetadata(name: "Studio Operations 2026", location: "Mumbai", currencyCode: "INR"),
        "moving": ProfileMetadata(name: "Apartment Move", location: "Hyderabad", currencyCode: "INR"),
        "event": ProfileMetadata(name: "Community Launch Event", location: "Delhi", currencyCode: "INR"),
        "warranty": ProfileMetadata(name: "Laptop Purchase & Warranty", location: "Online", currencyCode: "USD"),
        "custom": ProfileMetadata(name: "Everyday Receipts", location: "Various", currencyCode: "INR")
    ]

    private static let unfiledReceipts: [ReceiptSeed] = [
        ReceiptSeed(vendor: "Station Kiosk", location: "Berlin Central", date: date(2026, 6, 13, 10), amount: "12.40", currencyCode: "EUR", categoryID: "food", paymentMethod: .card, notes: "Unfiled snack receipt.", items: [("COFFEE", "4.20"), ("SNACK", "8.20")])
    ]
}

private struct ProfileSeed {
    var profile: FolderProfile
    var name: String
    var startDate: Date?
    var endDate: Date?
    var notes: String
    var createdAt: Date
    var receipts: [ReceiptSeed]
}

private struct ProfileMetadata {
    var name: String
    var location: String
    var currencyCode: String
}

private struct ReceiptSeed {
    var vendor: String
    var location: String
    var date: Date
    var amount: String
    var currencyCode: String
    var categoryID: String
    var paymentMethod: PaymentMethod
    var notes: String
    var items: [(label: String, amount: String)]
    var createdAt: Date

    init(
        vendor: String,
        location: String,
        date: Date,
        amount: String,
        currencyCode: String,
        categoryID: String,
        paymentMethod: PaymentMethod,
        notes: String,
        items: [(label: String, amount: String)],
        createdAt: Date? = nil
    ) {
        self.vendor = vendor
        self.location = location
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.items = items
        self.createdAt = createdAt ?? date.addingTimeInterval(45 * 60)
    }

    var ocrText: String {
        let itemLines = items.map { "\($0.label) \($0.amount)" }.joined(separator: "\n")
        return "\(vendor)\n\(location)\nDATE \(SandboxSeedData.formattedDate(date))\n\(itemLines)\nTOTAL \(currencyCode) \(amount)\n\(paymentMethod.rawValue.uppercased())"
    }

    var modelOutputJSON: String {
        """
        {"vendor":"\(vendor)","date":"\(SandboxSeedData.formattedDate(date))","totalAmount":"\(amount)","currencyCode":"\(currencyCode)","expenseType":"\(categoryID)","paymentMethod":"\(paymentMethod.rawValue)"}
        """
    }
}
#endif
