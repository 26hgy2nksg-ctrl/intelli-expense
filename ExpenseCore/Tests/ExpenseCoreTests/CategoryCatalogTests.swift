import XCTest
@testable import ExpenseCore

final class CategoryCatalogTests: XCTestCase {
    // MARK: - Built-in category catalog

    func testBuiltInCategoryIDsAreUnique() {
        let ids = CategoryCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Built-in category IDs must be unique")
    }

    func testEveryBuiltInCategoryHasSymbolAndSafeFallback() {
        for category in CategoryCatalog.all {
            XCTAssertFalse(category.symbolName.isEmpty, "\(category.id) is missing a symbol")
            XCTAssertFalse(category.fallbackSymbolName.isEmpty, "\(category.id) is missing a fallback symbol")
        }
    }

    func testEveryBuiltInCategoryIDIsStorageSafe() {
        for category in CategoryCatalog.all {
            XCTAssertTrue(
                CategoryCatalog.isValidIdentifier(category.id),
                "\(category.id) is not a storage/CSV-safe identifier"
            )
        }
    }

    func testLegacyExpenseTypeIDsMapToBuiltInCategories() {
        for type in ExpenseType.allCases {
            XCTAssertTrue(
                CategoryCatalog.isBuiltIn(type.categoryID),
                "Legacy type \(type.rawValue) must exist in the built-in catalog"
            )
        }
        XCTAssertEqual(CategoryCatalog.legacyExpenseTypeIDs, ["food", "hotel", "flight", "taxi", "other"])
    }

    func testBuiltInCategoryColorRolesMatchCategoryColorRolesSpec() {
        let expectedRoles: [String: CategoryColorRole] = [
            "food": .orange,
            "advertising": .orange,
            "labor": .orange,
            "pharmacy": .orange,
            "repairs": .orange,
            "catering": .orange,
            "purchase": .orange,
            "fuel": .amber,
            "booth_display": .amber,
            "utilities": .amber,
            "fixtures": .amber,
            "gifts": .amber,
            "repair": .amber,
            "baggage": .brown,
            "materials": .brown,
            "supplies": .brown,
            "building_materials": .brown,
            "medical_equipment": .brown,
            "tires": .brown,
            "packing": .brown,
            "replacement_parts": .brown,
            "laundry": .mint,
            "shipping": .mint,
            "tips": .mint,
            "rental_equipment": .mint,
            "consultation": .mint,
            "medical": .mint,
            "lease_finance": .mint,
            "cleaning": .mint,
            "warranty_plan": .mint,
            "taxi": .teal,
            "transport": .teal,
            "vehicle": .teal,
            "tools": .teal,
            "service": .teal,
            "bank_fees": .teal,
            "truck_rental": .teal,
            "installation": .teal,
            "parking_tolls": .cyan,
            "parking": .cyan,
            "wifi_tech": .cyan,
            "software": .cyan,
            "delivery": .cyan,
            "dental": .cyan,
            "audio_visual": .cyan,
            "flight": .blue,
            "travel": .blue,
            "equipment": .blue,
            "plumbing": .blue,
            "hospital": .blue,
            "washing": .blue,
            "movers": .blue,
            "hotel": .indigo,
            "train_bus": .indigo,
            "insurance": .indigo,
            "vision": .indigo,
            "venue": .indigo,
            "service_visit": .indigo,
            "business_calls": .purple,
            "registration": .purple,
            "professional_fees": .purple,
            "paint": .purple,
            "tests_labs": .purple,
            "tolls": .purple,
            "storage": .purple,
            "staff": .purple,
            "accessories": .purple,
            "professional_development": .plum,
            "electrical": .plum,
            "therapy": .plum,
            "oil": .plum,
            "decor": .plum,
            "printing": .slate,
            "client_materials": .slate,
            "permits": .slate,
            "vehicle_registration": .slate,
            "insurance_premium": .slate,
            "utilities_setup": .slate,
            "other": .gray
        ]

        XCTAssertEqual(Set(CategoryCatalog.all.map(\.id)), Set(expectedRoles.keys))
        for category in CategoryCatalog.all {
            XCTAssertEqual(
                category.colorRole,
                expectedRoles[category.id],
                "\(category.id) has the wrong color role"
            )
        }
    }

    func testOnlyOtherUsesGray() {
        let grayIDs = CategoryCatalog.all
            .filter { $0.colorRole == .gray }
            .map(\.id)
            .sorted()

        XCTAssertEqual(grayIDs, ["other"])
    }

    func testIdentifierValidatorRejectsUnsafeValues() {
        XCTAssertFalse(CategoryCatalog.isValidIdentifier(""))
        XCTAssertFalse(CategoryCatalog.isValidIdentifier("Booth Setup"))
        XCTAssertFalse(CategoryCatalog.isValidIdentifier("café"))
        XCTAssertFalse(CategoryCatalog.isValidIdentifier("A_B"))
        XCTAssertTrue(CategoryCatalog.isValidIdentifier("custom_booth_setup"))
        XCTAssertTrue(CategoryCatalog.isValidIdentifier("parking_tolls"))
    }

    // MARK: - Profiles

    func testProfileIDsAreUnique() {
        let ids = FolderProfileCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryProfileDefaultAndSuggestionReferencesKnownCategory() {
        for profile in FolderProfileCatalog.all {
            for id in profile.defaultCategoryIDs {
                XCTAssertTrue(CategoryCatalog.isBuiltIn(id), "\(profile.id) default \(id) is unknown")
            }
            for id in profile.suggestedCategoryIDs {
                XCTAssertTrue(CategoryCatalog.isBuiltIn(id), "\(profile.id) suggestion \(id) is unknown")
            }
        }
    }

    func testEveryProfileDefaultIncludesOtherLast() {
        for profile in FolderProfileCatalog.all {
            XCTAssertEqual(
                profile.defaultCategoryIDs.last,
                CategoryCatalog.otherID,
                "\(profile.id) must end with Other"
            )
            XCTAssertEqual(
                profile.defaultCategoryIDs.filter { $0 == CategoryCatalog.otherID }.count,
                1,
                "\(profile.id) must contain exactly one Other"
            )
        }
    }

    func testProfileDefaultsAreWithinTheVisibleCap() {
        for profile in FolderProfileCatalog.all {
            XCTAssertLessThanOrEqual(
                profile.defaultCategoryIDs.count,
                FolderCategorySnapshot.maximumVisibleCategories,
                "\(profile.id) exceeds the visible-category cap"
            )
        }
    }

    func testWorkTripProfileMatchesLegacyFiveCategories() {
        XCTAssertEqual(
            FolderProfileCatalog.workTrip.defaultCategoryIDs,
            ["flight", "hotel", "food", "taxi", "other"]
        )
    }

    func testProfileDefaultsAndSuggestionsUseDistinctHues() {
        let expectedHues: [String: [CategoryColorRole]] = [
            "workTrip": [.blue, .indigo, .orange, .teal, .cyan, .mint, .brown, .purple],
            "conference": [.purple, .blue, .indigo, .orange, .teal, .brown, .amber, .mint, .cyan, .slate, .plum],
            "clientVisit": [.orange, .teal, .cyan, .amber, .brown, .indigo, .slate, .mint],
            "homeProject": [.brown, .teal, .orange, .cyan, .slate, .amber, .purple, .plum, .blue, .mint],
            "medicalClaim": [.mint, .orange, .purple, .cyan, .indigo, .blue, .teal, .slate, .plum, .brown],
            "vehicleCosts": [.amber, .teal, .orange, .cyan, .purple, .slate, .indigo, .brown, .blue, .plum, .mint],
            "businessPurchases": [.brown, .cyan, .slate, .mint, .purple, .blue, .orange, .amber, .teal, .indigo],
            "moving": [.blue, .brown, .purple, .amber, .indigo, .orange, .cyan, .teal, .slate, .mint],
            "event": [.indigo, .orange, .plum, .slate, .brown, .blue, .cyan, .purple, .amber],
            "warranty": [.orange, .purple, .cyan, .teal, .amber, .mint, .brown, .indigo],
            "custom": [.orange, .brown, .teal]
        ]

        for profile in FolderProfileCatalog.all {
            let categories = CategoryCatalog.folderCategories(
                ids: (profile.defaultCategoryIDs + profile.suggestedCategoryIDs)
                    .filter { $0 != CategoryCatalog.otherID }
            )
            let hues = categories.map(\.colorRole)
            XCTAssertEqual(hues, expectedHues[profile.id], "\(profile.id) hue order drifted")
            XCTAssertEqual(hues.count, Set(hues).count, "\(profile.id) has duplicate hues: \(hues)")
        }
    }

    func testUnfiledDefaultUsesDistinctHues() {
        let hues = FolderCategorySnapshot.unfiledDefault.categories
            .filter { $0.isOther == false }
            .map(\.colorRole)

        XCTAssertEqual(hues, [.orange, .blue, .brown, .mint, .teal])
        XCTAssertEqual(hues.count, Set(hues).count)
    }

    func testProfileIdentityInvariants() {
        let presets = FolderProfileCatalog.all.filter { $0.id != FolderProfileCatalog.customID }
        let presetHues = presets.compactMap(\.identity.colorRole)

        XCTAssertEqual(presetHues.count, presets.count)
        XCTAssertEqual(Set(presetHues).count, presets.count)
        for profile in FolderProfileCatalog.all {
            XCTAssertFalse(profile.identity.symbolName.isEmpty, "\(profile.id) is missing an identity symbol")
        }

        let custom = FolderProfileCatalog.identity(forProfileID: FolderProfileCatalog.customID)
        XCTAssertEqual(custom.symbolName, "folder.fill")
        XCTAssertNil(custom.colorRole)
        XCTAssertEqual(FolderProfileCatalog.identity(forProfileID: "futureProfile"), custom)
    }

    func testConferenceProfileMatchesSpec() {
        let conference = FolderProfileCatalog.profile(id: "conference")
        XCTAssertEqual(
            conference?.defaultCategoryIDs,
            ["registration", "flight", "hotel", "food", "taxi", "materials", "other"]
        )
        XCTAssertEqual(
            conference?.suggestedCategoryIDs,
            ["booth_display", "shipping", "wifi_tech", "printing", "professional_development"]
        )
    }

    func testMedicalClaimNeverShowsFlightOrHotelByDefault() {
        let medical = FolderProfileCatalog.profile(id: "medicalClaim")
        XCTAssertNotNil(medical)
        XCTAssertFalse(medical!.defaultCategoryIDs.contains("flight"))
        XCTAssertFalse(medical!.defaultCategoryIDs.contains("hotel"))
    }

    func testDefaultSnapshotForUnknownProfileFallsBackToWorkTrip() {
        let snapshot = FolderProfileCatalog.defaultSnapshot(forProfileID: "does-not-exist")
        XCTAssertEqual(snapshot.categoryIDs, ["flight", "hotel", "food", "taxi", "other"])
    }

    func testSuggestionsExcludeAlreadySelected() {
        let suggestions = FolderProfileCatalog.suggestedCategories(
            forProfileID: "conference",
            excluding: ["booth_display"]
        )
        XCTAssertFalse(suggestions.contains { $0.id == "booth_display" })
        XCTAssertTrue(suggestions.contains { $0.id == "shipping" })
    }

    // MARK: - Snapshot invariants

    func testSnapshotAlwaysPinsExactlyOneOtherLast() {
        let snapshot = FolderCategorySnapshot(categories: [
            CategoryCatalog.folderCategory(id: "other")!,
            CategoryCatalog.folderCategory(id: "food")!,
            CategoryCatalog.folderCategory(id: "flight")!
        ])
        XCTAssertEqual(snapshot.categoryIDs, ["food", "flight", "other"])
        XCTAssertEqual(snapshot.categories.filter(\.isOther).count, 1)
    }

    func testSnapshotAddsOtherWhenMissing() {
        let snapshot = FolderCategorySnapshot(categories: [
            CategoryCatalog.folderCategory(id: "food")!
        ])
        XCTAssertEqual(snapshot.categoryIDs, ["food", "other"])
    }

    func testSnapshotDeduplicatesByID() {
        let snapshot = FolderCategorySnapshot(categories: [
            CategoryCatalog.folderCategory(id: "food")!,
            CategoryCatalog.folderCategory(id: "food")!,
            CategoryCatalog.folderCategory(id: "other")!
        ])
        XCTAssertEqual(snapshot.categoryIDs, ["food", "other"])
    }

    func testSnapshotJSONRoundTrips() {
        let original = FolderProfileCatalog.profile(id: "conference")!.defaultSnapshot
        let json = original.jsonString()
        XCTAssertFalse(json.isEmpty)
        let restored = FolderCategorySnapshot(jsonString: json)
        XCTAssertEqual(restored, original)
    }

    func testSnapshotJSONInitRejectsEmptyString() {
        XCTAssertNil(FolderCategorySnapshot(jsonString: ""))
        XCTAssertNil(FolderCategorySnapshot(jsonString: "   "))
        XCTAssertNil(FolderCategorySnapshot(jsonString: "not json"))
    }

    func testLegacyRoleRawValuesDecodeAsHues() {
        let legacyMappings: [String: CategoryColorRole] = [
            "food": .orange,
            "lodging": .indigo,
            "travel": .blue,
            "transport": .teal,
            "services": .purple,
            "goods": .brown,
            "tech": .cyan,
            "health": .mint,
            "generic": .gray
        ]

        for (rawValue, hue) in legacyMappings {
            let json = """
            {"categories":[{"colorRoleRawValue":"\(rawValue)","customName":"Legacy","id":"custom_legacy","symbolName":"tag.fill"}],"version":1}
            """

            let snapshot = FolderCategorySnapshot(jsonString: json)

            XCTAssertEqual(snapshot?.categories.first?.colorRole, hue, "\(rawValue) should decode as \(hue)")
        }
    }

    func testUnknownRoleRawValueDecodesAsGray() {
        let json = """
        {"categories":[{"colorRoleRawValue":"future_role","customName":"Future Role","id":"custom_future_role","symbolName":"tag.fill"}],"version":1}
        """

        let snapshot = FolderCategorySnapshot(jsonString: json)

        XCTAssertEqual(snapshot?.categories.first?.colorRole, .gray)
    }

    func testSnapshotEncodingEmitsHueVocabulary() {
        let snapshot = FolderCategorySnapshot(categories: [
            FolderCategory(id: "custom_plum", symbolName: "tag.fill", colorRole: .plum, customName: "Plum")
        ])
        let json = snapshot.jsonString()

        XCTAssertTrue(json.contains(#""colorRoleRawValue":"plum""#))
        XCTAssertFalse(json.contains(#""colorRoleRawValue":"services""#))
    }

    func testUnfiledDefaultSnapshotMatchesSpec() {
        XCTAssertEqual(
            FolderCategorySnapshot.unfiledDefault.categoryIDs,
            ["food", "travel", "supplies", "medical", "vehicle", "other"]
        )
    }

    // MARK: - Custom categories

    func testCustomCategoryGeneratesSafeIdentifier() {
        let category = CustomCategory.make(name: "Booth Setup")
        XCTAssertEqual(category?.id, "custom_booth_setup")
        XCTAssertEqual(category?.customName, "Booth Setup")
        XCTAssertTrue(category?.isCustom == true)
        XCTAssertEqual(category?.symbolName, "tag.fill")
        XCTAssertEqual(category?.colorRole, .orange)
        XCTAssertTrue(CategoryCatalog.isValidIdentifier(category!.id))
    }

    func testCustomCategoryUsesFirstAvailableNonGrayHue() {
        let existing = [
            CategoryCatalog.folderCategory(id: "food")!,
            CategoryCatalog.folderCategory(id: "taxi")!,
            CategoryCatalog.otherFolderCategory
        ]

        let category = CustomCategory.make(name: "Booth Setup", existingCategories: existing)

        XCTAssertEqual(category?.colorRole, .purple)
    }

    func testCustomCategoryLeastUsedFallbackNeverUsesGray() {
        let categories = CustomCategory.autoAssignedColorPriority.enumerated().map { index, hue in
            FolderCategory(id: "custom_\(index)", symbolName: "tag.fill", colorRole: hue, customName: "\(index)")
        } + [
            FolderCategory(id: "custom_extra", symbolName: "tag.fill", colorRole: .orange, customName: "Extra"),
            CategoryCatalog.otherFolderCategory
        ]

        XCTAssertEqual(CustomCategory.autoAssignedColorRole(avoiding: categories), .teal)
    }

    func testGrayCustomCategoriesHealOnEditOnly() {
        let grayCustom = FolderCategory(
            id: "custom_booth_setup",
            symbolName: "star.fill",
            colorRole: .gray,
            customName: "Booth Setup"
        )
        let coloredCustom = FolderCategory(
            id: "custom_colored",
            symbolName: "tag.fill",
            colorRole: .plum,
            customName: "Colored"
        )
        let healed = CustomCategory.healingGrayCustomCategories(in: [
            CategoryCatalog.folderCategory(id: "food")!,
            grayCustom,
            coloredCustom,
            CategoryCatalog.otherFolderCategory
        ])

        XCTAssertEqual(healed.first { $0.id == grayCustom.id }?.colorRole, .teal)
        XCTAssertEqual(healed.first { $0.id == coloredCustom.id }?.colorRole, .plum)
        XCTAssertEqual(healed.last?.id, CategoryCatalog.otherID)
    }

    func testCustomCategoryDisambiguatesCollisions() {
        let first = CustomCategory.make(name: "Booth")!
        let second = CustomCategory.make(name: "Booth", existingIDs: [first.id])
        XCTAssertEqual(first.id, "custom_booth")
        XCTAssertEqual(second?.id, "custom_booth_2")
    }

    func testCustomCategoryHandlesNonASCIIAndEmpty() {
        XCTAssertNil(CustomCategory.make(name: "   "))
        XCTAssertNil(CustomCategory.make(name: "™"))
        let accented = CustomCategory.make(name: "Café Meeting")
        XCTAssertEqual(accented?.id, "custom_caf_meeting")
        XCTAssertTrue(CategoryCatalog.isValidIdentifier(accented!.id))
    }

    // MARK: - Category resolver

    func testResolverUsesCatalogMetadataForBuiltInSnapshotIDs() {
        let staleSoftware = FolderCategory(id: "software", symbolName: "tag.fill", colorRole: .gray)
        let snapshot = FolderCategorySnapshot(categories: [staleSoftware, CategoryCatalog.otherFolderCategory])

        let resolved = CategoryResolver.category(forID: "software", in: snapshot)

        XCTAssertEqual(resolved.symbolName, "laptopcomputer")
        XCTAssertEqual(resolved.colorRole, .cyan)
        XCTAssertNil(resolved.customName)
    }

    func testResolverPreservesCustomSnapshotMetadata() {
        let custom = FolderCategory(
            id: "custom_booth_setup",
            symbolName: "star.fill",
            colorRole: .gray,
            customName: "Booth Setup"
        )
        let snapshot = FolderCategorySnapshot(categories: [custom, CategoryCatalog.otherFolderCategory])

        let resolved = CategoryResolver.category(forID: custom.id, in: snapshot)

        XCTAssertEqual(resolved, custom)
    }

    func testResolverKeepsUnknownFallbackHumanizedAndGray() {
        let resolved = CategoryResolver.category(forID: "future_peer_category", in: nil)

        XCTAssertEqual(resolved.id, "future_peer_category")
        XCTAssertEqual(resolved.symbolName, CustomCategory.defaultSymbolName)
        XCTAssertEqual(resolved.colorRole, .gray)
        XCTAssertEqual(resolved.customName, "Future Peer Category")
    }
}
