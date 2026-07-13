import AppIntents
import XCTest
@testable import IntelliExpense

final class ScanReceiptIntentTests: XCTestCase {
    func testIntentUsesForegroundSupportedModesAndCaptureTarget() {
        XCTAssertTrue(ScanReceiptIntent.supportedModes.contains(.foreground(.immediate)))
        XCTAssertEqual(ScanReceiptIntent().target, .capture)
    }

    func testIntentImplementationAvoidsRejectedAPIs() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/AppIntents/ScanReceiptIntent.swift"), encoding: .utf8)
        let contentViewSource = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/ContentView.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("openAppWhenRun"))
        XCTAssertFalse(source.contains("LockedCameraCapture"))
        XCTAssertTrue(source.contains("OpenIntent"))
        XCTAssertFalse(source.contains("URLRepresentableIntent"))
        XCTAssertFalse(source.contains("URLRepresentableEnum"))
        XCTAssertTrue(source.contains("TargetContentProvidingIntent"))
        XCTAssertTrue(contentViewSource.contains("onAppIntentExecution(ScanReceiptIntent.self)"))
        XCTAssertTrue(contentViewSource.contains("handleIncomingURL(AppDeepLinkRouter.captureURL)"))
        XCTAssertFalse(source.contains("OpenURLIntent"))
        XCTAssertFalse(source.contains("func perform"))
    }

    func testAppShortcutsCatalogOwnsIntentAndShortcutStrings() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpense/Resources/AppShortcuts.xcstrings"))

        XCTAssertEqual(try localizedValue(for: "intent.scanReceipt.title", in: catalog), "Scan Receipt")
        XCTAssertEqual(try localizedValue(for: "control.scanReceipt.label", in: catalog), "Scan Receipt")
        XCTAssertEqual(try localizedValue(for: "shortcut.scanReceipt.shortTitle", in: catalog), "Scan Receipt")
        XCTAssertEqual(
            try localizedValue(for: "shortcut.scanReceipt.phrase.scanReceipt", in: catalog),
            "Scan a receipt in ${applicationName}"
        )
        XCTAssertEqual(
            try localizedValue(for: "shortcut.scanReceipt.phrase.appScan", in: catalog),
            "${applicationName} scan"
        )
        XCTAssertEqual(
            try localizedValue(for: "shortcut.scanReceipt.phrase.newReceipt", in: catalog),
            "New receipt in ${applicationName}"
        )
    }

    func testMacTargetExcludesIOSOnlyScanIntentSource() throws {
        let project = try String(contentsOf: repoRoot.appending(path: "project.yml"), encoding: .utf8)
        let macTargetStart = try XCTUnwrap(project.range(of: "  IntelliExpenseMac:\n"))
        let nextTargetStart = try XCTUnwrap(project[macTargetStart.upperBound...].range(of: "\n  IntelliExpenseShare:\n"))
        let macTargetBlock = project[macTargetStart.lowerBound..<nextTargetStart.lowerBound]

        XCTAssertTrue(macTargetBlock.contains(#"- "AppIntents/ScanReceiptIntent.swift""#))
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
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let english = try XCTUnwrap(localizations["en"] as? [String: Any])
        let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
