import XCTest

final class FolderUserFacingRenameTests: XCTestCase {
    func testFolderRenameCatalogValuesStayUserFacingFolderBased() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpense/Resources/Localizable.xcstrings"))

        XCTAssertEqual(try localizedValue(for: "filter.allGroups", in: catalog), "All folders")
        XCTAssertEqual(try localizedValue(for: "filter.group", in: catalog), "Folder")
        XCTAssertEqual(try localizedValue(for: "filter.group.section", in: catalog), "Folder")
        XCTAssertEqual(try localizedValue(for: "group.detail.empty.title", in: catalog), "No receipts in this folder")
        XCTAssertEqual(try localizedValue(for: "group.detail.empty.message", in: catalog), "Receipts saved to this folder will appear here.")
        XCTAssertEqual(try localizedValue(for: "group.editor.delete", in: catalog), "Delete Folder\u{2026}")
        XCTAssertEqual(try localizedValue(for: "folder.pin", in: catalog), "Pin")
        XCTAssertEqual(try localizedValue(for: "folder.pinned", in: catalog), "Pinned")
        XCTAssertEqual(try localizedValue(for: "folder.unpin", in: catalog), "Unpin")
        XCTAssertEqual(try localizedValue(for: "onboarding.bullet.export.subtitle", in: catalog), "Create a finance-ready zip when the folder is ready.")
        XCTAssertEqual(try localizedValue(for: "trips.archived.empty.title", in: catalog), "No archived folders")
        XCTAssertEqual(try localizedValue(for: "trips.archived.empty.message", in: catalog), "When you archive a folder it moves here.")

        let deleteTitle = try pluralValues(for: "group.delete.title", in: catalog)
        XCTAssertEqual(deleteTitle["one"], "Delete %d folder?")
        XCTAssertEqual(deleteTitle["other"], "Delete %d folders?")

        let archivedRow = try pluralValues(for: "trips.archived.row", in: catalog)
        XCTAssertEqual(archivedRow["one"], "%d folder")
        XCTAssertEqual(archivedRow["other"], "%d folders")
    }

    func testGenericTripLanguageDoesNotReturnToMainCatalogChrome() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpense/Resources/Localizable.xcstrings"))
        let allValues = try englishValues(in: catalog)
        let allowedTripKeys: Set<String> = [
            "folder.profile.workTrip"
        ]

        let genericTripValues = allValues
            .filter { allowedTripKeys.contains($0.key) == false }
            .filter { $0.value.range(of: #"\btrips?\b"#, options: [.regularExpression, .caseInsensitive]) != nil }

        XCTAssertTrue(
            genericTripValues.isEmpty,
            genericTripValues
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: "\n")
        )
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func stringCatalog(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func localizedValue(for key: String, in catalog: [String: Any]) throws -> String {
        let english = try englishLocalization(for: key, in: catalog)
        let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }

    private func pluralValues(for key: String, in catalog: [String: Any]) throws -> [String: String] {
        let english = try englishLocalization(for: key, in: catalog)
        let variations = try XCTUnwrap(english["variations"] as? [String: Any])
        let plural = try XCTUnwrap(variations["plural"] as? [String: Any])
        return try plural.mapValues { variant in
            let variantDictionary = try XCTUnwrap(variant as? [String: Any])
            let unit = try XCTUnwrap(variantDictionary["stringUnit"] as? [String: Any])
            return try XCTUnwrap(unit["value"] as? String)
        }
    }

    private func englishLocalization(for key: String, in catalog: [String: Any]) throws -> [String: Any] {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        return try XCTUnwrap(localizations["en"] as? [String: Any])
    }

    private func englishValues(in catalog: [String: Any]) throws -> [(key: String, value: String)] {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        return strings.flatMap { key, entry -> [(key: String, value: String)] in
            guard
                let entryDictionary = entry as? [String: Any],
                let localizations = entryDictionary["localizations"] as? [String: Any],
                let english = localizations["en"] as? [String: Any]
            else { return [] }

            return collectedValues(in: english).map { (key: key, value: $0) }
        }
    }

    private func collectedValues(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let array = value as? [Any] {
            return array.flatMap(collectedValues)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.flatMap(collectedValues)
        }
        return []
    }
}
