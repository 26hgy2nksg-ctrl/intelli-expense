import XCTest

final class MacVisualPolishTests: XCTestCase {
    func testAccentColorAliasesLedgerGreenAndIsGlobalAccent() throws {
        let accentURL = repoRoot.appending(path: "IntelliExpense/Resources/Assets.xcassets/AccentColor.colorset/Contents.json")
        let ledgerURL = repoRoot.appending(path: "IntelliExpense/Resources/Assets.xcassets/LedgerGreen.colorset/Contents.json")
        XCTAssertEqual(try Data(contentsOf: accentURL), try Data(contentsOf: ledgerURL))

        let project = try String(contentsOf: repoRoot.appending(path: "project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor"))
    }

    func testMacVisualPolishStringsAreCatalogued() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpense/Resources/Localizable.xcstrings"))

        XCTAssertEqual(try localizedValue(for: "receipt.detail.addPhoto.toolbar", in: catalog), "Add Photo")
        XCTAssertEqual(try localizedValue(for: "receipt.pager.previous", in: catalog), "Previous Page")
        XCTAssertEqual(try localizedValue(for: "receipt.pager.next", in: catalog), "Next Page")
        XCTAssertEqual(try localizedValue(for: "mac.sidebar.trip.help", in: catalog), "%1$@ · %2$@")
    }

    func testMacDetailPaneOwnsActionsAndPager() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/Mac/MacReceiptDetailPane.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("mac.detail.hero.amount"))
        XCTAssertTrue(source.contains("mac.detail.toolbar.addPhoto"))
        XCTAssertTrue(source.contains("mac.detail.toolbar.archive"))
        XCTAssertTrue(source.contains("mac.detail.toolbar.restore"))
        XCTAssertTrue(source.contains("mac.detail.toolbar.delete"))
        XCTAssertTrue(source.contains("mac.detail.pager.previous"))
        XCTAssertTrue(source.contains("mac.detail.pager.next"))
        XCTAssertTrue(source.contains("formStyle(.grouped)"))
        XCTAssertTrue(source.contains("ReceiptStore.archive"))
        XCTAssertTrue(source.contains("ReceiptStore.restore"))
    }

    func testMacDetailAmountEditorRefreshesWhenReceiptSelectionChanges() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/Mac/MacReceiptDetailPane.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("onChange(of: receipt.persistentModelID, initial: true)"))
    }

    func testMacLibraryUsesNativeDetailPaneInsteadOfIPhoneDetailNavigationStack() throws {
        let source = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/Mac/MacContentView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("MacReceiptDetailPane("))
        XCTAssertFalse(source.contains("NavigationStack {\n                ReceiptDetailView(receipt: selectedReceipt)"))
    }

    func testMacFolderEditorModalFamilyUsesNativePresentationRoles() throws {
        let support = try String(
            contentsOf: repoRoot.appending(path: "IntelliExpense/UI/PlatformPresentationSupport.swift"),
            encoding: .utf8
        )
        let editor = try String(
            contentsOf: repoRoot.appending(path: "IntelliExpense/UI/GroupsViews.swift"),
            encoding: .utf8
        )
        let categories = try String(
            contentsOf: repoRoot.appending(path: "IntelliExpense/UI/CategoryComposer.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(support.contains("formStyle(.grouped)"))
        XCTAssertTrue(support.contains("presentationSizing(.form)"))
        XCTAssertTrue(support.contains("presentationSizing(.page)"))
        XCTAssertTrue(editor.contains("mac.folderEditor.sheet"))
        XCTAssertTrue(editor.contains("mac.folderEditor.form"))
        XCTAssertTrue(editor.contains("macFormPresentation"))
        XCTAssertTrue(categories.contains("mac.folderCategories.browse.sheet"))
        XCTAssertTrue(categories.contains("mac.folderCategories.browse.list"))
        XCTAssertTrue(categories.contains("mac.folderCategories.custom.sheet"))
        XCTAssertTrue(categories.contains("mac.folderCategories.custom.form"))
        XCTAssertTrue(categories.contains("mac.folderCategories.reassign.sheet"))
        XCTAssertTrue(categories.contains("mac.folderCategories.reassign.list"))
        XCTAssertTrue(categories.contains("macCatalogPresentation"))
        XCTAssertTrue(categories.contains("macFormPresentation"))
    }

    func testDesignDocsRecordMacVisualPolishRules() throws {
        let design = try String(contentsOf: repoRoot.appending(path: "DESIGN.md"), encoding: .utf8)
        let uiSpec = try String(contentsOf: repoRoot.appending(path: "design/ui-spec.html"), encoding: .utf8)
        let guidance = try String(contentsOf: repoRoot.appending(path: "CLAUDE.md"), encoding: .utf8)

        XCTAssertTrue(design.contains("AccentColor"))
        XCTAssertTrue(design.contains("image beside grouped fields"))
        XCTAssertTrue(design.contains("Mac detail toolbar"))
        XCTAssertTrue(design.contains("New/Edit Folder and Add Custom Category use grouped forms"))
        XCTAssertTrue(design.contains("page presentation role"))
        XCTAssertTrue(uiSpec.contains("Mac detail"))
        XCTAssertTrue(uiSpec.contains("AccentColor"))
        XCTAssertTrue(uiSpec.contains("Folder editor modal family"))
        XCTAssertTrue(uiSpec.contains("presentationSizing(.form)"))
        XCTAssertTrue(uiSpec.contains("presentationSizing(.page)"))
        XCTAssertTrue(guidance.contains("iOS 26 + native macOS 26"))
        XCTAssertTrue(guidance.contains("make test-mac"))
        XCTAssertTrue(guidance.contains("Shared UI changes must run every affected platform lane"))
    }

    func testMacDesktopBehaviorContractIsWiredAndDocumented() throws {
        let catalog = try stringCatalog(at: repoRoot.appending(path: "IntelliExpense/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        for key in [
            "receipt.action.quickLook", "receipt.action.moveToTrip", "trip.rename", "menu.showArchived",
            "receipts.selected.count", "receipts.batch.archive", "receipts.batch.delete.title",
            "menu.zoomIn", "menu.zoomOut", "menu.actualSize"
        ] {
            XCTAssertNotNil(strings[key], "Missing \(key)")
        }
        XCTAssertEqual(try localizedValue(for: "receipt.action.moveToTrip", in: catalog), "Move to Folder")

        let macSource = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/Mac/MacContentView.swift"), encoding: .utf8)
        let support = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/Mac/MacDesktopBehaviorSupport.swift"), encoding: .utf8)
        let commands = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/Mac/MacCommands.swift"), encoding: .utf8)
        let exportSource = try String(contentsOf: repoRoot.appending(path: "IntelliExpense/UI/ShareSheet.swift"), encoding: .utf8)
        let design = try String(contentsOf: repoRoot.appending(path: "DESIGN.md"), encoding: .utf8)
        let uiSpec = try String(contentsOf: repoRoot.appending(path: "design/ui-spec.html"), encoding: .utf8)

        for identifier in [
            "mac.list.search", "mac.detail.multiSummary", "mac.detail.multiSummary.total",
            "mac.contextMenu.quickLook", "mac.contextMenu.moveToTrip", "mac.sidebar.rename.field"
        ] {
            XCTAssertTrue(macSource.contains(identifier) || support.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(exportSource.contains("mac.export.showInFinder"))
        XCTAssertTrue(macSource.contains("importsItemProviders"))
        XCTAssertTrue(commands.contains("ImportFromDevicesCommands"))
        XCTAssertTrue(commands.contains("CommandGroup(replacing: .textFormatting)"))
        XCTAssertTrue(support.contains("ProxyRepresentation"))
        XCTAssertTrue(design.contains("Never custom-paint list selection"))
        XCTAssertTrue(design.contains("Font.scaled(by:)"))
        XCTAssertTrue(uiSpec.contains("Undo + batch editing"))
        XCTAssertTrue(uiSpec.contains("Search + keyboard"))
        XCTAssertTrue(uiSpec.contains("Drag + nearby import"))
        XCTAssertTrue(uiSpec.contains("Zoom + restoration"))
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
