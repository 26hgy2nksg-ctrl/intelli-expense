import XCTest

@MainActor
final class IntelliExpenseMacUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testEmptyDetailStateRendersWhenNothingIsSelected() {
        launchApp()

        XCTAssertTrue(app.staticTexts["Select a receipt"].waitForExistence(timeout: 5))
    }

    func testSeededReceiptUsesMacDetailToolbarAndPager() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        XCTAssertTrue(app.staticTexts["mac.detail.hero.amount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mac.detail.toolbar.archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mac.detail.pager.previous"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mac.detail.pager.next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["receipt.action.archive"].exists)

        app.buttons["mac.detail.toolbar.archive"].tap()
        XCTAssertTrue(app.staticTexts["Select a receipt"].waitForExistence(timeout: 5))
    }

    func testSelectingReceiptRefreshesEditableAmount() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        let firstReceipt = staticText(startingWith: "REWE CITY")
        XCTAssertTrue(firstReceipt.waitForExistence(timeout: 5))
        firstReceipt.click()

        let amount = element("mac.detail.amount")
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "84.50")

        staticText(startingWith: "Hotel Mitte").click()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "20.00"), object: amount)],
                timeout: 5
            ),
            .completed
        )

        staticText(startingWith: "New York Cab").click()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "10.00"), object: amount)],
                timeout: 5
            ),
            .completed
        )
    }

    func testFindFiltersWithinTheCurrentReceiptColumn() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        app.typeKey("f", modifierFlags: .command)
        let search = searchField(placeholder: "Search vendor or notes")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("no receipt matches this")

        XCTAssertTrue(app.staticTexts["No matching receipts"].waitForExistence(timeout: 5))
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(staticText(startingWith: "REWE CITY").waitForExistence(timeout: 5))
    }

    func testMultiSelectionShowsCurrencySeparatedSummary() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        staticText(startingWith: "REWE CITY").click()
        app.typeKey(.downArrow, modifierFlags: .shift)

        XCTAssertTrue(element("mac.detail.multiSummary").waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "mac.detail.multiSummary.total").count, 1)
    }

    func testDeleteArchivesAndUndoRestoresTheSelectedReceipt() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        let hotel = staticText(startingWith: "Hotel Mitte")
        XCTAssertTrue(hotel.waitForExistence(timeout: 5))
        hotel.click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(hotel.waitForNonExistence(timeout: 5))

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(hotel.waitForExistence(timeout: 5))
    }

    func testReturnRenamesTheSelectedFolderInline() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        staticText(startingWith: "Berlin Filing").click()
        app.typeKey(.return, modifierFlags: [])
        let renameField = element("mac.sidebar.rename.field")
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.typeKey("a", modifierFlags: .command)
        renameField.typeText("Berlin Renamed")
        renameField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["Berlin Renamed"].waitForExistence(timeout: 5))
    }

    func testEmptyInlineRenameIsRejectedWithoutChangingTheFolder() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        staticText(startingWith: "Berlin Filing").click()
        app.typeKey(.return, modifierFlags: [])
        let renameField = element("mac.sidebar.rename.field")
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.typeKey("a", modifierFlags: .command)
        renameField.typeText("   ")
        renameField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(renameField.waitForNonExistence(timeout: 5))
        XCTAssertTrue(staticText(startingWith: "Berlin Filing").exists)
    }

    func testSpaceOpensQuickLookForTheSelectedReceipt() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        staticText(startingWith: "REWE CITY").click()
        let initialWindowCount = app.windows.count
        app.typeKey(.space, modifierFlags: [])

        XCTAssertGreaterThan(app.windows.count, initialWindowCount)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testDraggingAReceiptOntoAFolderRefilesIt() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        let receipt = staticText(startingWith: "REWE CITY")
        let folder = staticText(startingWith: "Berlin Filing")
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        receipt.click(forDuration: 0.5, thenDragTo: folder)
        folder.click()

        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
    }

    func testSidebarFolderSelectionIsImmediateAndDoubleClickStillRenames() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        let folder = staticText(startingWith: "Berlin Filing")
        let unfiled = staticText(startingWith: "Unfiled")
        XCTAssertTrue(folder.waitForExistence(timeout: 5))

        unfiled.click()
        XCTAssertTrue(app.windows["Unfiled"].waitForExistence(timeout: 5))

        folder.click()
        XCTAssertTrue(app.windows["Berlin Filing"].exists)

        folder.doubleClick()
        XCTAssertTrue(element("mac.sidebar.rename.field").waitForExistence(timeout: 1))
    }

    func testSidebarBottomBarCreationDisclosureAndBadge() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        let newFolderButton = element("mac.sidebar.newFolder")
        XCTAssertTrue(newFolderButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(newFolderButton.frame.width, 180)

        openNewFolder()

        let nameField = element("group.editor.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Transformation")
        app.buttons["Save"].click()

        let sidebar = app.outlines["Sidebar"]
        let createdFolder = sidebar.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Transformation")
        ).firstMatch
        XCTAssertTrue(createdFolder.waitForExistence(timeout: 5))
        createdFolder.click()
        XCTAssertTrue(app.windows["Transformation"].waitForExistence(timeout: 5))

        let unfiled = element("mac.sidebar.unfiled.row")
        XCTAssertTrue(unfiled.waitForExistence(timeout: 5))
        XCTAssertEqual(unfiled.value as? String, "3 receipts")

        let foldersDisclosure = sidebar.disclosureTriangles.firstMatch
        XCTAssertTrue(foldersDisclosure.waitForExistence(timeout: 5))
        foldersDisclosure.click()
        XCTAssertTrue(createdFolder.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.windows["Transformation"].exists)

        foldersDisclosure.click()
        XCTAssertTrue(createdFolder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows["Transformation"].exists)
    }

    func testExportSheetOffersShowInFinder() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        app.typeKey("e", modifierFlags: .command)

        XCTAssertTrue(element("mac.export.showInFinder").waitForExistence(timeout: 10))
    }

    func testContentZoomStepsResetAndPersistAcrossRelaunch() {
        launchApp("-UITestSeedMacVisualPolishLibrary")
        staticText(startingWith: "REWE CITY").click()
        app.typeKey("0", modifierFlags: .command)
        let amount = element("mac.detail.hero.amount")
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let actualSizeHeight = amount.frame.height

        app.typeKey("+", modifierFlags: .command)
        XCTAssertGreaterThan(amount.frame.height, actualSizeHeight)
        let zoomedHeight = amount.frame.height

        app.terminate()
        app.launch()
        staticText(startingWith: "REWE CITY").click()
        XCTAssertEqual(element("mac.detail.hero.amount").frame.height, zoomedHeight, accuracy: 1)

        app.typeKey("0", modifierFlags: .command)
        XCTAssertEqual(element("mac.detail.hero.amount").frame.height, actualSizeHeight, accuracy: 1)

        for _ in 0..<10 { app.typeKey("+", modifierFlags: .command) }
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Zoom In"].isEnabled)
        XCTAssertTrue(app.menuItems["Actual Size"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        for _ in 0..<10 { app.typeKey("-", modifierFlags: .command) }
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Zoom Out"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("0", modifierFlags: .command)
    }

    func testZoomCommandsDriveTheReceiptViewerWhenItIsFrontmost() {
        launchApp("-UITestSeedMacVisualPolishLibrary")

        staticText(startingWith: "REWE CITY").click()
        element("receipt.image.open").click()
        let viewerImage = element("receipt.image.viewer.magnification")
        XCTAssertTrue(viewerImage.waitForExistence(timeout: 5))
        let actualSizeFrame = viewerImage.frame

        app.typeKey("+", modifierFlags: .command)
        XCTAssertGreaterThan(viewerImage.frame.width, actualSizeFrame.width)
        app.typeKey("0", modifierFlags: .command)
        XCTAssertEqual(viewerImage.frame.width, actualSizeFrame.width, accuracy: 1)
    }

    func testNewFolderAndBrowseCatalogUseNativeMacPresentations() {
        launchApp()
        openNewFolder()

        let editorSheet = app.sheets.firstMatch
        let editorForm = element("mac.folderEditor.form")
        XCTAssertTrue(editorSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(editorForm.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(editorForm.frame.height, 300)
        XCTAssertTrue(app.staticTexts["Details"].exists)
        XCTAssertTrue(app.staticTexts["Categories"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)

        let nameField = element("group.editor.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Keyboard Folder")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(element("group.editor.profile").isHittable)

        openBrowseCategories()

        let browseList = element("mac.folderCategories.browse.list")
        XCTAssertTrue(browseList.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(browseList.frame.height, 240)
        let search = searchField(placeholder: "Search categories")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Professional Development")
        let professionalDevelopment = element("folder.categories.browse.professional_development")
        XCTAssertTrue(professionalDevelopment.waitForExistence(timeout: 5))

        app.typeKey(.tab, modifierFlags: [])
        professionalDevelopment.click()

        XCTAssertTrue(browseList.waitForNonExistence(timeout: 5))
        XCTAssertTrue(editorSheet.exists)
        XCTAssertTrue(element("folder.categories.remove.professional_development").waitForExistence(timeout: 5))
    }

    func testBrowseEmptyResultsKeepsTheCatalogViewportStable() {
        launchApp()
        openNewFolder()
        openBrowseCategories()

        let browseList = element("mac.folderCategories.browse.list")
        XCTAssertTrue(browseList.waitForExistence(timeout: 5))
        let initialHeight = browseList.frame.height
        XCTAssertGreaterThan(initialHeight, 240)

        let search = searchField(placeholder: "Search categories")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("no-category-can-match-this-query")

        let noResults = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "No Results")
        ).firstMatch
        XCTAssertTrue(noResults.waitForExistence(timeout: 5))
        XCTAssertEqual(browseList.frame.height, initialHeight, accuracy: 1)

        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(element("folder.categories.browse.pharmacy").waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        XCTAssertTrue(browseList.waitForNonExistence(timeout: 5))
    }

    func testNestedCancellationPreservesUnsavedFolderEdits() {
        launchApp()
        openNewFolder()

        let nameField = element("group.editor.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Unsaved Modal Draft")

        openBrowseCategories()
        XCTAssertTrue(element("mac.folderCategories.browse.list").waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        XCTAssertEqual(nameField.value as? String, "Unsaved Modal Draft")

        element("folder.categories.addCustom").click()
        XCTAssertTrue(element("mac.folderCategories.custom.form").waitForExistence(timeout: 5))
        app.sheets.element(boundBy: 1).buttons["Cancel"].click()
        XCTAssertTrue(element("mac.folderCategories.custom.form").waitForNonExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Unsaved Modal Draft")
        XCTAssertTrue(element("mac.folderEditor.form").exists)
    }

    func testAddCustomCategoryReturnsToTheOpenFolderEditor() {
        launchApp()
        openNewFolder()

        let editorSheet = app.sheets.firstMatch
        element("folder.categories.addCustom").click()

        let customForm = element("mac.folderCategories.custom.form")
        let nameField = element("folder.categories.custom.name")
        XCTAssertTrue(customForm.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(customForm.frame.height, 200)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        nameField.click()
        nameField.typeText("Mac Parking")
        app.buttons["Add"].click()

        XCTAssertTrue(customForm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(editorSheet.exists)
        XCTAssertTrue(element("folder.categories.remove.custom_mac_parking").waitForExistence(timeout: 5))
    }

    func testUsedCategoryReassignmentUsesAVisibleCatalogBody() {
        launchApp("-UITestSeedMacFolderEditorLibrary")

        let folder = staticText(startingWith: "Modal Test Folder")
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        let folderCell = app.outlines["Sidebar"].cells.element(boundBy: 1)
        folderCell.rightClick()
        let edit = app.menuItems["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()

        XCTAssertTrue(element("mac.folderEditor.form").waitForExistence(timeout: 5))
        element("folder.categories.remove.food").click()

        let reassignList = element("mac.folderCategories.reassign.list")
        XCTAssertTrue(reassignList.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(reassignList.frame.height, 180)
        XCTAssertTrue(element("folder.categories.reassign.hotel").waitForExistence(timeout: 5))

        element("folder.categories.keep").click()

        XCTAssertTrue(reassignList.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("mac.folderEditor.form").exists)
        XCTAssertTrue(element("folder.categories.remove.food").exists)

        element("folder.categories.remove.food").click()
        XCTAssertTrue(reassignList.waitForExistence(timeout: 5))
        element("folder.categories.reassign.hotel").click()

        XCTAssertTrue(reassignList.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("mac.folderEditor.form").exists)
        XCTAssertTrue(element("folder.categories.remove.food").waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("folder.categories.remove.hotel").exists)
    }

    private func launchApp(_ arguments: String...) {
        app = XCUIApplication()
        app.launchArguments = [
            "-UITestFakeServices",
            "--ui-testing",
            "-ResetCurrencyDefaults",
            "-SkipOnboarding",
            "-ApplePersistenceIgnoreState",
            "YES"
        ] + arguments
        app.launch()
    }

    private func openNewFolder() {
        let button = element("mac.sidebar.newFolder")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }

    private func openBrowseCategories() {
        let form = element("mac.folderEditor.form")
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let button = element("folder.categories.browse")
        if button.exists == false {
            form.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func searchField(placeholder: String) -> XCUIElement {
        app.searchFields.matching(
            NSPredicate(format: "placeholderValue == %@", placeholder)
        ).firstMatch
    }

    private func staticText(startingWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                prefix,
                prefix
            )
        ).firstMatch
    }
}
