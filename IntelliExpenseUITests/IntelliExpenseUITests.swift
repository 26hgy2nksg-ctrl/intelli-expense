import XCTest

final class IntelliExpenseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryTabs() {
        launchApp("-SkipOnboarding")

        XCTAssertTrue(app.tabBars.buttons["Folders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Receipts"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    @MainActor
    func testFirstLaunchWelcomeContinuesToMainTabs() {
        launchApp("-ResetOnboarding")

        XCTAssertTrue(app.staticTexts["Welcome to Intelli-Expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture"].exists)
        XCTAssertTrue(app.staticTexts["Confirm"].exists)
        XCTAssertTrue(app.staticTexts["Export"].exists)
        XCTAssertTrue(app.staticTexts["On-device intelligence fills in the merchant, date, and total — you check every field before it's saved."].exists)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.tabBars.buttons["Folders"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingCurrencyPickerCanChangeDefaultCurrency() {
        launchApp("-ResetOnboarding")

        let currencyRow = app.buttons["onboarding.currency.row"]
        XCTAssertTrue(currencyRow.waitForExistence(timeout: 5))
        currencyRow.tap()

        selectCurrency("INR")

        XCTAssertTrue(currencyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(currencyRow.label.contains("INR"))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.tabBars.buttons["Folders"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsCurrencyPickerReplacesTextEntryAndPrefillsManualReview() {
        launchApp("-SkipOnboarding")

        app.tabBars.buttons["Settings"].tap()
        let settingsRow = app.buttons["settings.currency.row"]
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Default currency"].exists)

        settingsRow.tap()
        selectCurrency("CAD")

        XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsRow.label.contains("CAD"))

        app.tabBars.buttons["Folders"].tap()
        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        let reviewCurrencyRow = app.buttons["review.currency.row"]
        XCTAssertTrue(reviewCurrencyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewCurrencyRow.label.contains("CAD"))
        XCTAssertFalse(app.textFields["Currency"].exists)
    }

    @MainActor
    func testPhotoImportCaptureReviewSaveHappyPath() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Vendor"].value as? String, "REWE CITY")
        XCTAssertEqual(app.textFields["Amount"].value as? String, "84.50")
        saveReviewAndOpenReceipts()
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSeededSharedInboxRunsProcessingAndOpensReview() {
        launchApp("-SkipOnboarding", "-UITestSeedSharedInbox")

        XCTAssertTrue(app.buttons["processing.cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["Vendor"].value as? String, "REWE CITY")
        XCTAssertEqual(app.textFields["Amount"].value as? String, "84.50")
        saveReviewAndOpenReceipts()
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCaptureDeepLinkShowsCameraDeniedFallback() throws {
        launchApp("-SkipOnboarding", "-UITestForceCameraDenied")

        try openDeepLink("intelliexpense://capture")

        XCTAssertTrue(app.staticTexts["Camera access is off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Photo and file import still work."].exists)
    }

    @MainActor
    func testCaptureDeepLinkDoesNotDiscardOpenReview() throws {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))

        try openDeepLink("intelliexpense://capture")

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["review.close"].exists)
    }

    @MainActor
    func testCaptureDeepLinkBeforeOnboardingKeepsWelcomeAndDropsRequest() throws {
        launchApp("-ResetOnboarding", "-UITestForceCameraDenied")
        XCTAssertTrue(app.staticTexts["Welcome to Intelli-Expense"].waitForExistence(timeout: 5))

        try openDeepLink("intelliexpense://capture")

        XCTAssertTrue(app.staticTexts["Welcome to Intelli-Expense"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Camera access is off"].exists)
    }

    @MainActor
    func testWidgetScanKindDeepLinkShowsCameraDeniedFallback() throws {
        launchApp("-SkipOnboarding", "-UITestForceCameraDenied")

        try openDeepLink("intelliexpense://capture?kind=scan")

        XCTAssertTrue(app.staticTexts["Camera access is off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Photo and file import still work."].exists)
    }

    @MainActor
    func testWidgetPhotoKindDeepLinkOpensPhotoReview() throws {
        launchApp("-SkipOnboarding")

        try openDeepLink("intelliexpense://capture?kind=photo")

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["Vendor"].value as? String, "REWE CITY")
        XCTAssertEqual(app.textFields["Amount"].value as? String, "84.50")

        let diagnostics = app.descendants(matching: .any)["receipt.diagnostic.disclosure"]
        var scrollAttempts = 0
        while diagnostics.exists == false && scrollAttempts < 6 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        XCTAssertTrue(app.staticTexts["Text-only model input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Model attempts"].exists)
    }

    @MainActor
    func testWidgetManualKindDeepLinkOpensManualReviewForm() throws {
        launchApp("-SkipOnboarding")

        try openDeepLink("intelliexpense://capture?kind=manual")

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        // Manual entry opens the empty form — not the prefilled photo fixture.
        XCTAssertNotEqual(app.textFields["Vendor"].value as? String, "REWE CITY")
        XCTAssertNotEqual(app.textFields["Amount"].value as? String, "84.50")
    }

    @MainActor
    func testWidgetFileKindDeepLinkOpensImporterNotReviewOrScan() throws {
        launchApp("-SkipOnboarding", "-UITestForceCameraDenied")

        try openDeepLink("intelliexpense://capture?kind=file")

        // File import waits on the system file picker — it must not open review,
        // and it must not fall back to the scan/camera-denied path.
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Camera access is off"].exists)
    }

    @MainActor
    func testWidgetUnknownKindDeepLinkFallsBackToScan() throws {
        launchApp("-SkipOnboarding", "-UITestForceCameraDenied")

        try openDeepLink("intelliexpense://capture?kind=nonsense")

        XCTAssertTrue(app.staticTexts["Camera access is off"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewImageOpensFullScreenViewer() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.buttons["review.image.open"].tap()

        XCTAssertTrue(app.otherElements["receipt.image.viewer"].waitForExistence(timeout: 5))
        app.buttons["receipt.image.viewer.done"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewDateUsesExplicitConfirmationSheet() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        let dateRow = app.buttons["review.date.row"]
        XCTAssertTrue(dateRow.waitForExistence(timeout: 5))
        dateRow.tap()

        XCTAssertTrue(app.navigationBars["Date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review.date.cancel"].exists)
        XCTAssertTrue(app.buttons["review.date.done"].exists)

        app.buttons["review.date.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Date"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Review & Confirm"].exists)

        dateRow.tap()
        XCTAssertTrue(app.navigationBars["Date"].waitForExistence(timeout: 5))
        app.buttons["review.date.done"].tap()
        XCTAssertTrue(app.navigationBars["Date"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Review & Confirm"].exists)
    }

    @MainActor
    func testNewFolderDatesUseExplicitConfirmationSheets() {
        launchApp("-SkipOnboarding")
        openCreateTrip()

        XCTAssertTrue(app.navigationBars["New Folder"].waitForExistence(timeout: 5))
        assertDateConfirmationSheet(
            rowIdentifier: "group.editor.startDate.row",
            title: "Start date",
            identifierPrefix: "group.editor.startDate"
        )
        assertDateConfirmationSheet(
            rowIdentifier: "group.editor.endDate.row",
            title: "End date",
            identifierPrefix: "group.editor.endDate"
        )
    }

    @MainActor
    func testReceiptDetailDateUsesExplicitConfirmationSheet() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()
        saveReviewAndOpenReceipts()
        app.staticTexts["REWE CITY"].tap()

        assertDateConfirmationSheet(
            rowIdentifier: "receipt.detail.date.row",
            title: "Date",
            identifierPrefix: "receipt.detail.date"
        )
    }

    @MainActor
    func testReceiptDetailImageOpensFullScreenViewer() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()
        saveReviewAndOpenReceipts()

        app.staticTexts["REWE CITY"].tap()
        app.buttons["receipt.image.open"].tap()

        XCTAssertTrue(app.otherElements["receipt.image.viewer"].waitForExistence(timeout: 5))
        app.buttons["receipt.image.viewer.done"].tap()
        XCTAssertTrue(app.navigationBars["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testManualEntryPathSavesPhotoLessTaxiReceipt() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.image.open"].exists)
        XCTAssertFalse(app.staticTexts["Manual entry"].exists)
        XCTAssertTrue(app.staticTexts["Fields"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Vendor"].isHittable)
        XCTAssertTrue(app.textFields["Amount"].isHittable)
        app.textFields["Amount"].tap()
        app.typeText("41.00")
        app.buttons["Done"].tap()
        app.buttons["Vehicle"].tap()
        app.buttons["Cash"].tap()
        saveReviewAndOpenReceipts()
        XCTAssertTrue(app.staticTexts["Manual entry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnfiledExportProducesShareSheet() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.textFields["Amount"].tap()
        app.typeText("12.34")
        app.buttons["Done"].tap()
        app.buttons["Vehicle"].tap()
        app.buttons["Cash"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 5))

        app.tabBars.buttons["Folders"].tap()
        XCTAssertTrue(app.buttons["groups.unfiled.link"].waitForExistence(timeout: 5))
        app.buttons["groups.unfiled.link"].tap()
        XCTAssertTrue(app.navigationBars["Unfiled"].waitForExistence(timeout: 5))

        app.buttons["group.export"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["unfiled-receipts"].exists)
    }

    @MainActor
    func testCaptureAccessoryExistsOnlyOnPrimaryTabsAndProvidesDirectScanAndSheet() {
        launchApp("-SkipOnboarding")

        XCTAssertTrue(app.buttons["capture.accessory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scan Receipt"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Receipts"].tap()
        XCTAssertTrue(app.buttons["capture.accessory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scan Receipt"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["capture.accessory"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Scan Receipt"].waitForNonExistence(timeout: 2))
        app.tabBars.buttons["Folders"].tap()
        XCTAssertTrue(app.buttons["capture.accessory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scan Receipt"].waitForExistence(timeout: 5))

        app.buttons["capture.accessory"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.buttons["review.close"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 5))

        XCTAssertTrue(app.buttons["capture.accessory.menu"].waitForExistence(timeout: 5))
        app.buttons["capture.accessory.menu"].tap()
        assertAddReceiptSheetVisible()
    }

    @MainActor
    func testAddReceiptSheetOpensFromAccessoryAndToolbar() {
        launchApp("-SkipOnboarding")

        XCTAssertTrue(app.buttons["capture.accessory.menu"].waitForExistence(timeout: 5))
        app.buttons["capture.accessory.menu"].tap()
        assertAddReceiptSheetVisible()
        XCTAssertTrue(app.staticTexts["capture.sheet.destination"].label.contains("Unfiled"))
        dismissAddReceiptSheet()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 2))

        app.tabBars.buttons["Receipts"].tap()
        XCTAssertTrue(app.buttons["capture.accessory.menu"].waitForExistence(timeout: 5))
        app.buttons["capture.accessory.menu"].tap()
        assertAddReceiptSheetVisible()
        dismissAddReceiptSheet()

        app.navigationBars["Receipts"].buttons["Add receipt"].tap()
        assertAddReceiptSheetVisible()
        app.buttons["capture.sheet.manual"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTripsHomeFeaturedCardOpensMostRecentTrip() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Berlin June")

        app.staticTexts["Berlin June"].tap()
        XCTAssertTrue(app.navigationBars["Berlin June"].waitForExistence(timeout: 5))
        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 5))

        app.tabBars.buttons["Folders"].tap()
        let featuredCard = app.descendants(matching: .any).matching(identifier: "groups.featured.card").element(boundBy: 0)
        XCTAssertTrue(featuredCard.waitForExistence(timeout: 5))
        XCTAssertTrue(featuredCard.label.contains("Berlin June"))

        featuredCard.tap()
        XCTAssertTrue(app.navigationBars["Berlin June"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group.export"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTripDetailBreakdownRowsShowAllTypesAndToggleSelection() {
        launchApp("-SkipOnboarding", "-UITestSeedTripBreakdownRows")

        let featuredCard = app.descendants(matching: .any).matching(identifier: "groups.featured.card").element(boundBy: 0)
        XCTAssertTrue(featuredCard.waitForExistence(timeout: 5))
        featuredCard.tap()
        XCTAssertTrue(app.navigationBars["Breakdown Rows"].waitForExistence(timeout: 5))

        for identifier in [
            "group.breakdown.food",
            "group.breakdown.hotel",
            "group.breakdown.flight",
            "group.breakdown.taxi",
            "group.breakdown.other"
        ] {
            let row = app.buttons[identifier]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing \(identifier)")
            XCTAssertTrue(row.isHittable, "\(identifier) should be visible without scrolling")
        }

        let foodRow = app.buttons["group.breakdown.food"]
        foodRow.tap()
        XCTAssertTrue(app.staticTexts["Food Vendor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hotel Vendor"].waitForNonExistence(timeout: 2))
        foodRow.tap()
        XCTAssertTrue(app.staticTexts["Hotel Vendor"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTripsHomeKeepsSingleFeaturedCardAndPromotesRemainingTripAfterArchive() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Older Trip")
        createGroup(named: "Newer Trip")

        let featuredCards = app.descendants(matching: .any).matching(identifier: "groups.featured.card")
        XCTAssertEqual(featuredCards.count, 1)
        let featuredCard = featuredCards.element(boundBy: 0)
        XCTAssertTrue(featuredCard.label.contains("Newer Trip"))
        XCTAssertTrue(app.staticTexts["Older Trip"].exists)

        featuredCard.swipeLeft()
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Delete"].exists)
        app.buttons["Archive"].tap()

        XCTAssertTrue(app.staticTexts["Newer Trip"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trips.archived.link"].waitForExistence(timeout: 5))
        XCTAssertEqual(featuredCards.count, 1)
        XCTAssertTrue(featuredCards.element(boundBy: 0).label.contains("Older Trip"))
    }

    @MainActor
    func testPinningCompactFolderPromotesItAndUnpinRestoresActivityOrder() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Pinned Folder")
        createGroup(named: "Activity Leader")

        let pinnedFolderRow = app.staticTexts["Pinned Folder"]
        XCTAssertTrue(pinnedFolderRow.waitForExistence(timeout: 5))
        pinnedFolderRow.press(forDuration: 1)

        let pinButton = app.buttons["folder.action.pin"]
        XCTAssertTrue(pinButton.waitForExistence(timeout: 5))
        pinButton.tap()

        let featuredCard = app.descendants(matching: .any)
            .matching(identifier: "groups.featured.card")
            .element(boundBy: 0)
        XCTAssertTrue(featuredCard.waitForExistence(timeout: 5))
        XCTAssertTrue(featuredCard.label.contains("Pinned Folder"))
        XCTAssertEqual(featuredCard.value as? String, "Pinned")

        featuredCard.press(forDuration: 1)
        let unpinButton = app.buttons["folder.action.unpin"]
        XCTAssertTrue(unpinButton.waitForExistence(timeout: 5))
        unpinButton.tap()

        XCTAssertTrue(featuredCard.waitForExistence(timeout: 5))
        XCTAssertTrue(featuredCard.label.contains("Activity Leader"))
    }

    @MainActor
    func testArchivedTripHidesReceiptsAndRestoreReturnsThem() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Berlin Archive")

        app.staticTexts["Berlin Archive"].tap()
        XCTAssertTrue(app.navigationBars["Berlin Archive"].waitForExistence(timeout: 5))
        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()
        saveReviewAndOpenReceipts()
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Folders"].tap()
        archiveTrip(named: "Berlin Archive")
        XCTAssertTrue(app.buttons["trips.archived.link"].waitForExistence(timeout: 5))

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        // The folder row sits below the category selector; scroll it into view on the review list.
        let reviewGroupRow = app.buttons["review.group.row"]
        var reviewScrolls = 0
        while reviewGroupRow.exists == false && reviewScrolls < 6 {
            app.swipeUp()
            reviewScrolls += 1
        }
        XCTAssertTrue(reviewGroupRow.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewGroupRow.label.contains("Unfiled"))
        XCTAssertFalse(reviewGroupRow.label.contains("Berlin Archive"))
        app.buttons["review.close"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 5))

        app.tabBars.buttons["Receipts"].tap()
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForNonExistence(timeout: 5))

        app.tabBars.buttons["Folders"].tap()
        app.buttons["trips.archived.link"].tap()
        XCTAssertTrue(app.navigationBars["Archived"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Berlin Archive"].waitForExistence(timeout: 5))
        app.staticTexts["Berlin Archive"].swipeRight()
        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 5))
        app.buttons["Restore"].tap()

        XCTAssertTrue(app.navigationBars["Folders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Berlin Archive"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Receipts"].tap()
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testArchivedTripDeleteUsesExistingConfirmationDialog() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Purge Later")

        archiveTrip(named: "Purge Later")
        app.buttons["trips.archived.link"].tap()
        XCTAssertTrue(app.navigationBars["Archived"].waitForExistence(timeout: 5))

        app.staticTexts["Purge Later"].swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete 1 folder?"].waitForExistence(timeout: 5))
        app.buttons["Keep receipts in Unfiled"].tap()

        XCTAssertTrue(app.navigationBars["Folders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Purge Later"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testTripEditorDeleteAppearsOnlyForExistingTripsAndOpensDialog() {
        launchApp("-SkipOnboarding")

        openCreateTrip()
        XCTAssertTrue(app.navigationBars["New Folder"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group.editor.delete"].exists)
        app.buttons["Cancel"].tap()

        createGroup(named: "Editor Delete")
        app.staticTexts["Editor Delete"].tap()
        XCTAssertTrue(app.navigationBars["Editor Delete"].waitForExistence(timeout: 5))
        app.buttons["group.edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Folder"].waitForExistence(timeout: 5))
        // The delete action sits below the category composer sections; scroll it into view.
        let deleteButton = app.buttons["group.editor.delete"]
        var scrollAttempts = 0
        while deleteButton.exists == false && scrollAttempts < 6 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["Delete 1 folder?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testGroupDetailToolbarUsesSingleExportIconAndStillShares() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Berlin June")

        app.staticTexts["Berlin June"].tap()
        XCTAssertTrue(app.navigationBars["Berlin June"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group.export"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Berlin June"].buttons["Add receipt"].exists)

        app.buttons["group.export"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testBrowseCategoriesStaysPresentedAfterFirstTap() {
        launchApp("-SkipOnboarding")
        createGroup(named: "Browse Test")
        app.staticTexts["Browse Test"].tap()
        XCTAssertTrue(app.navigationBars["Browse Test"].waitForExistence(timeout: 5))
        app.buttons["group.edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Folder"].waitForExistence(timeout: 5))

        scrollToButton("folder.categories.browse")
        app.buttons["folder.categories.browse"].tap()

        let browseNavigationBar = app.navigationBars["Browse Existing Categories"]
        XCTAssertTrue(browseNavigationBar.waitForExistence(timeout: 5))
        let unexpectedDismissal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: browseNavigationBar
        )
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedDismissal], timeout: 1), .timedOut)
    }

    @MainActor
    func testDiscardPromptsOnlyAfterReviewEdits() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.buttons["review.close"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 5))

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.textFields["Vendor"].tap()
        app.typeText("Edited Vendor")
        app.buttons["review.close"].tap()

        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.alerts["Discard changes?"].buttons["Discard"].tap()
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testReviewSaveBarHidesDuringAmountEditingAndDoneRestoresSave() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.textFields["Amount"].tap()

        XCTAssertFalse(app.buttons["review.save"].isHittable)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review.save"].isHittable)
        saveReviewAndOpenReceipts()
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIncompleteReviewSaveShowsAndClearsMissingFieldsMessage() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.manual"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        app.buttons["review.save"].tap()

        let missingMessage = app.staticTexts["review.save.missing"]
        XCTAssertTrue(missingMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(missingMessage.label.contains("Amount"))

        app.textFields["Amount"].tap()
        app.typeText("41.00")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Vehicle"].tap()
        app.buttons["Cash"].tap()

        XCTAssertTrue(missingMessage.waitForNonExistence(timeout: 2))
        saveReviewAndOpenReceipts()
        XCTAssertTrue(app.staticTexts["Manual entry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDuplicateBannerViewButtonNavigatesToMatchingReceipt() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()
        saveReviewAndOpenReceipts()

        app.tabBars.buttons["Folders"].tap()
        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Possible duplicate receipt"].waitForExistence(timeout: 5))
        app.buttons["View"].tap()

        XCTAssertTrue(app.navigationBars["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProcessingOverlayCanCancelSlowFixtureCapture() {
        launchApp("-SkipOnboarding", "-FakeSlowOCR")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        let cancel = app.buttons["processing.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Vendor"].value as? String, "Vendor")
        XCTAssertFalse(app.alerts["Capture failed"].exists)
    }

    @MainActor
    func testArchiveAndRestoreReceiptThroughDetailAndArchivedFilter() {
        launchApp("-SkipOnboarding")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()
        saveReviewAndOpenReceipts()

        app.staticTexts["REWE CITY"].tap()
        scrollToButton("receipt.action.archive")
        app.buttons["receipt.action.archive"].tap()

        XCTAssertTrue(app.navigationBars["Receipts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForNonExistence(timeout: 2))

        app.buttons["receipts.filter.menu"].tap()
        app.buttons["receipts.filter.archived"].tap()

        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Archived"].exists)

        app.staticTexts["REWE CITY"].tap()
        scrollToButton("receipt.action.restore")
        app.buttons["receipt.action.restore"].tap()

        XCTAssertTrue(app.navigationBars["Receipts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForNonExistence(timeout: 2))

        app.buttons["receipts.filter.menu"].tap()
        app.buttons["receipts.filter.active"].tap()

        XCTAssertTrue(app.staticTexts["REWE CITY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAvailabilityGateAndModelPreparingDegradationStates() {
        launchApp("-SkipOnboarding", "-FakeAINotEnabled")
        XCTAssertTrue(app.staticTexts["Turn on Apple Intelligence"].waitForExistence(timeout: 5))

        launchApp("-SkipOnboarding", "-FakeDeviceNotEligible")
        XCTAssertTrue(app.staticTexts["Apple Intelligence required"].waitForExistence(timeout: 5))

        launchApp("-SkipOnboarding", "-FakeModelNotReady")
        XCTAssertTrue(app.staticTexts["Apple Intelligence is still downloading"].waitForExistence(timeout: 5))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.tabBars.buttons["Folders"].waitForExistence(timeout: 5))

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Smart extraction is getting ready. Deterministic results are shown for now."].exists)
    }

    @MainActor
    func testUnsupportedLanguageDegradationReachesReview() {
        launchApp("-SkipOnboarding", "-FakeUnsupportedLanguage")

        openAddReceiptSheet()
        app.buttons["capture.sheet.photo"].tap()

        XCTAssertTrue(app.navigationBars["Review & Confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Smart extraction does not support this receipt language yet. Deterministic results are shown."].exists)
    }

    @MainActor
    private func launchApp(_ arguments: String...) {
        app = XCUIApplication()
        app.launchArguments = ["-UITestFakeServices", "--ui-testing", "-ResetCurrencyDefaults"] + arguments
        app.launch()
    }

    @MainActor
    private func openAddReceiptSheet() {
        let menuButton = app.buttons["capture.accessory.menu"].firstMatch
        if menuButton.waitForExistence(timeout: 1) {
            menuButton.tap()
        } else {
            let addButton = app.buttons["Add receipt"].firstMatch
            XCTAssertTrue(addButton.waitForExistence(timeout: 5))
            addButton.tap()
        }
        assertAddReceiptSheetVisible()
    }

    @MainActor
    private func assertAddReceiptSheetVisible() {
        let sheet = app.descendants(matching: .any).matching(identifier: "capture.sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture.sheet.scan"].exists)
        XCTAssertTrue(app.buttons["capture.sheet.photo"].exists)
        XCTAssertTrue(app.buttons["capture.sheet.file"].exists)
        XCTAssertTrue(app.buttons["capture.sheet.manual"].exists)
        XCTAssertTrue(app.staticTexts["capture.sheet.destination"].exists)
    }

    @MainActor
    private func dismissAddReceiptSheet() {
        let sheet = app.descendants(matching: .any).matching(identifier: "capture.sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(
                forDuration: 0.1,
                thenDragTo: sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            )
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func openDeepLink(_ url: String) throws {
        app.open(try XCTUnwrap(URL(string: url)))
    }

    @MainActor
    private func saveReviewAndOpenReceipts() {
        let reviewNavigationBar = app.navigationBars["Review & Confirm"]
        XCTAssertTrue(reviewNavigationBar.waitForExistence(timeout: 5))

        let saveButton = app.buttons["review.save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: saveButton)
        waitForExpectations(timeout: 5)
        saveButton.tap()
        XCTAssertTrue(reviewNavigationBar.waitForNonExistence(timeout: 8))

        let receiptsTab = app.tabBars.buttons["Receipts"]
        XCTAssertTrue(receiptsTab.waitForExistence(timeout: 5))
        receiptsTab.tap()
        XCTAssertTrue(app.navigationBars["Receipts"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func scrollToButton(_ identifier: String) {
        let button = app.buttons[identifier]
        for _ in 0..<5 where button.exists == false {
            app.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
    }

    @MainActor
    private func archiveTrip(named name: String) {
        app.tabBars.buttons["Folders"].tap()
        if app.navigationBars[name].waitForExistence(timeout: 1) {
            let tripsBackButton = app.navigationBars[name].buttons["Folders"]
            XCTAssertTrue(tripsBackButton.waitForExistence(timeout: 5))
            tripsBackButton.tap()
        }
        XCTAssertTrue(app.navigationBars["Folders"].waitForExistence(timeout: 5))

        let featuredCard = app.descendants(matching: .any).matching(identifier: "groups.featured.card").element(boundBy: 0)
        if featuredCard.waitForExistence(timeout: 1), featuredCard.label.contains(name) {
            featuredCard.swipeLeft()
        } else {
            let tripText = app.staticTexts[name].firstMatch
            XCTAssertTrue(tripText.waitForExistence(timeout: 5))
            tripText.swipeLeft()
        }
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func openCreateTrip() {
        let createRow = app.buttons["groups.create.row"].firstMatch
        if createRow.waitForExistence(timeout: 1) {
            createRow.tap()
        } else {
            let create = app.buttons["New Folder"].firstMatch
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            create.tap()
        }
    }

    @MainActor
    private func selectCurrency(_ code: String) {
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5))
        let searchField = app.textFields["currencyPicker.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(code)
        let option = app.buttons["currency.option.\(code)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func createGroup(named name: String) {
        openCreateTrip()
        XCTAssertTrue(app.navigationBars["New Folder"].waitForExistence(timeout: 5))
        app.textFields["Name"].tap()
        app.typeText(name)
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertDateConfirmationSheet(
        rowIdentifier: String,
        title: String,
        identifierPrefix: String
    ) {
        let row = app.buttons[rowIdentifier]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["\(identifierPrefix).cancel"].exists)
        XCTAssertTrue(app.buttons["\(identifierPrefix).done"].exists)

        app.buttons["\(identifierPrefix).cancel"].tap()
        XCTAssertTrue(app.navigationBars[title].waitForNonExistence(timeout: 5))

        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        app.buttons["\(identifierPrefix).done"].tap()
        XCTAssertTrue(app.navigationBars[title].waitForNonExistence(timeout: 5))
    }
}
