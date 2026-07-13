import XCTest

final class ShareExtensionHandoffTests: XCTestCase {
    func testAppRegistersShareImportURLScheme() throws {
        let info = try propertyList(at: repoRoot.appending(path: "IntelliExpense/Info.plist"))
        let urlTypes = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }

        XCTAssertTrue(schemes.contains("intelliexpense"))
    }

    func testShareExtensionCopySeparatesReadyAndSavedStates() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpenseShare/Resources/Localizable.xcstrings"))

        let readyBody = try localizedValue(for: "share.body", in: catalog)
        let savedBody = try localizedValue(for: "share.saved.body", in: catalog)

        XCTAssertFalse(readyBody.localizedCaseInsensitiveContains("saved"))
        XCTAssertTrue(savedBody.localizedCaseInsensitiveContains("saved"))
        XCTAssertTrue(savedBody.localizedCaseInsensitiveContains("open"))
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func stringCatalog(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func localizedValue(for key: String, in catalog: [String: Any]) throws -> String {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let english = try XCTUnwrap(localizations["en"] as? [String: Any])
        let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
