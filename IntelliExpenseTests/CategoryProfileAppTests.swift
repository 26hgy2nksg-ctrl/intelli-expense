import ExpenseCore
import XCTest
@testable import IntelliExpense

#if canImport(UIKit)
import UIKit
#endif

final class CategoryProfileAppTests: XCTestCase {

    // MARK: - SF Symbol validation (SPEC §D9)

    #if canImport(UIKit)
    func testEveryBuiltInCategorySymbolResolvesOnMinimumOS() {
        var unresolved: [String] = []
        for category in CategoryCatalog.all {
            let primaryResolves = UIImage(systemName: category.symbolName) != nil
            let fallbackResolves = UIImage(systemName: category.fallbackSymbolName) != nil
            if primaryResolves == false && fallbackResolves == false {
                unresolved.append("\(category.id): \(category.symbolName)/\(category.fallbackSymbolName)")
            }
        }
        XCTAssertTrue(unresolved.isEmpty, "Categories with no resolvable symbol: \(unresolved.joined(separator: ", "))")
    }

    func testEveryProfileIdentitySymbolResolvesOnMinimumOS() {
        var unresolved: [String] = []
        for profile in FolderProfileCatalog.all {
            if UIImage(systemName: profile.identity.symbolName) == nil {
                unresolved.append("\(profile.id): \(profile.identity.symbolName)")
            }
        }
        XCTAssertTrue(unresolved.isEmpty, "Profiles with no resolvable identity symbol: \(unresolved.joined(separator: ", "))")
    }

    func testEveryCategoryFallbackSymbolResolves() {
        for category in CategoryCatalog.all {
            XCTAssertNotNil(
                UIImage(systemName: category.fallbackSymbolName),
                "Fallback \(category.fallbackSymbolName) for \(category.id) must resolve"
            )
        }
    }

    func testEveryCategoryColorRoleLoadsNamedAssetColor() {
        let expectedAssetNames: [CategoryColorRole: String] = [
            .orange: "CategoryOrange",
            .amber: "CategoryAmber",
            .brown: "CategoryBrown",
            .mint: "CategoryMint",
            .teal: "CategoryTeal",
            .cyan: "CategoryCyan",
            .blue: "CategoryBlue",
            .indigo: "CategoryIndigo",
            .purple: "CategoryPurple",
            .plum: "CategoryPlum",
            .slate: "CategorySlate",
            .gray: "CategoryGray"
        ]

        XCTAssertEqual(CategoryColorRole.allCases.count, expectedAssetNames.count)
        for role in CategoryColorRole.allCases {
            XCTAssertEqual(role.assetColorName, expectedAssetNames[role])
            XCTAssertNotNil(
                UIColor(named: role.assetColorName, in: Bundle.main, compatibleWith: nil),
                "Missing asset color \(role.assetColorName) for \(role.rawValue)"
            )
        }
    }
    #endif

    // MARK: - Migration (SPEC §11.1)

    @MainActor
    func testExistingGroupDefaultsToWorkTripSnapshot() {
        let group = ExpenseGroup(name: "Legacy Trip")
        XCTAssertEqual(group.profileID, "workTrip")
        XCTAssertEqual(group.visibleCategoryIDs, ["flight", "hotel", "food", "taxi", "other"])
    }

    @MainActor
    func testConferenceFolderStartsWithConferenceDefaults() {
        let snapshot = FolderProfileCatalog.defaultSnapshot(forProfileID: "conference")
        let group = ExpenseGroup(name: "AWS Summit", profileID: "conference", categorySnapshotJSON: snapshot.jsonString())
        XCTAssertEqual(
            group.visibleCategoryIDs,
            ["registration", "flight", "hotel", "food", "taxi", "materials", "other"]
        )
    }

    @MainActor
    func testEditedSnapshotRoundTripsThroughPersistedJSON() {
        var snapshot = FolderProfileCatalog.defaultSnapshot(forProfileID: "conference")
        // Remove Materials, add a custom category.
        snapshot = FolderCategorySnapshot(categories: snapshot.categories.filter { $0.id != "materials" })
        let custom = CustomCategory.make(name: "Booth Setup")!
        snapshot = FolderCategorySnapshot(categories: snapshot.categories.dropLast() + [custom, CategoryCatalog.otherFolderCategory])

        let group = ExpenseGroup(name: "AWS", profileID: "conference", categorySnapshotJSON: snapshot.jsonString())
        XCTAssertFalse(group.visibleCategoryIDs.contains("materials"))
        XCTAssertTrue(group.visibleCategoryIDs.contains("custom_booth_setup"))
        XCTAssertEqual(group.visibleCategoryIDs.last, "other")
    }

    // MARK: - Agent import category validation (SPEC §D12)

    func testAgentImportAcceptsVisibleCategoryWithoutReview() throws {
        let record = makeRecord(expenseType: "registration")
        let validated = try AgentImportRecordValidator.validate(
            record,
            visibleCategoryIDs: ["registration", "flight", "other"]
        )
        XCTAssertEqual(validated.categoryID, "registration")
        XCTAssertFalse(validated.categoryNeedsReview)
    }

    func testAgentImportDraftsHiddenButKnownCategoryForReview() throws {
        // "flight" is a known built-in but not visible in a medical folder.
        let record = makeRecord(expenseType: "flight")
        let validated = try AgentImportRecordValidator.validate(
            record,
            visibleCategoryIDs: ["consultation", "pharmacy", "other"]
        )
        XCTAssertEqual(validated.categoryID, "flight")
        XCTAssertTrue(validated.categoryNeedsReview)
    }

    func testAgentImportRejectsUnknownCategory() {
        let record = makeRecord(expenseType: "totally_made_up")
        XCTAssertThrowsError(try AgentImportRecordValidator.validate(record, visibleCategoryIDs: ["food", "other"]))
    }

    func testAgentImportAcceptsLegacyCategoryWithoutFolderContext() throws {
        let validated = try AgentImportRecordValidator.validate(makeRecord(expenseType: "taxi"))
        XCTAssertEqual(validated.categoryID, "taxi")
        XCTAssertFalse(validated.categoryNeedsReview)
    }

    private func makeRecord(expenseType: String) -> AgentStructuredReceiptRecord {
        AgentStructuredReceiptRecord(
            merchant: "Vendor",
            date: "2026-06-14",
            total: "12.30",
            currency: "USD",
            expenseType: expenseType,
            paymentMethod: "card",
            notes: nil,
            userConfirmed: true
        )
    }
}
