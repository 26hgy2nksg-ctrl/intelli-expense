import AppKit
import Foundation
import SwiftData
import XCTest
@testable import IntelliExpense

@MainActor
final class MacDesktopBehaviorTests: XCTestCase {
    func testDoubleClickRenameRecognizerDoesNotDelayPrimaryFolderSelection() {
        let recognizer = MacDoubleClickActionView.makeRecognizer()

        XCTAssertEqual(recognizer.numberOfClicksRequired, 2)
        XCTAssertFalse(recognizer.delaysPrimaryMouseButtonEvents)
    }

    func testUITestLaunchConfigurationDisablesRestorationPath() {
        let configuration = AppLaunchConfiguration(arguments: ["--ui-testing"])

        XCTAssertTrue(configuration.isUITesting)
        XCTAssertFalse(AppLaunchConfiguration(arguments: []).isUITesting)
    }

    func testGroupReassignmentUndoRoundTripsRelationshipAndInverse() throws {
        let context = try makeContext()
        let berlin = ExpenseGroup(name: "Berlin")
        let tokyo = ExpenseGroup(name: "Tokyo")
        let receipt = Receipt(vendor: "Cafe", totalAmount: 12, currencyCode: "EUR", group: berlin)
        berlin.receipts = [receipt]
        context.insert(berlin)
        context.insert(tokyo)
        context.insert(receipt)
        try context.save()
        context.undoManager?.removeAllActions()

        try MacReceiptOperations.move([receipt], to: tokyo, in: context)
        XCTAssertEqual(receipt.group?.name, "Tokyo")
        XCTAssertFalse(berlin.receipts?.contains(where: { $0 === receipt }) == true)
        XCTAssertTrue(tokyo.receipts?.contains(where: { $0 === receipt }) == true)

        context.undoManager?.undo()
        XCTAssertEqual(receipt.group?.name, "Berlin")
        XCTAssertTrue(berlin.receipts?.contains(where: { $0 === receipt }) == true)
        XCTAssertFalse(tokyo.receipts?.contains(where: { $0 === receipt }) == true)

        context.undoManager?.redo()
        XCTAssertEqual(receipt.group?.name, "Tokyo")
        XCTAssertFalse(berlin.receipts?.contains(where: { $0 === receipt }) == true)
        XCTAssertTrue(tokyo.receipts?.contains(where: { $0 === receipt }) == true)
    }

    func testBatchArchiveAndUndoAreOneOperation() throws {
        let context = try makeContext()
        let first = Receipt(vendor: "First")
        let second = Receipt(vendor: "Second")
        context.insert(first)
        context.insert(second)
        try context.save()
        context.undoManager?.removeAllActions()

        try MacReceiptOperations.archive([first, second], in: context)
        XCTAssertTrue(first.isArchived)
        XCTAssertTrue(second.isArchived)
        XCTAssertTrue(context.undoManager?.canUndo == true)

        context.undoManager?.undo()
        XCTAssertFalse(first.isArchived)
        XCTAssertFalse(second.isArchived)
        XCTAssertFalse(context.undoManager?.canUndo == true)
    }

    func testArchivedReceiptDeletionCanBeUndone() throws {
        let context = try makeContext()
        let receipt = Receipt(vendor: "Archived", isArchived: true, archivedAt: Date())
        context.insert(receipt)
        try context.save()
        context.undoManager?.removeAllActions()

        try MacReceiptOperations.delete([receipt], in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Receipt>()).isEmpty)

        context.undoManager?.undo()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Receipt>()).map(\.vendor), ["Archived"])
    }

    func testPendingDockBadgeCountsOnlyAgentDraftsAwaitingReview() {
        let payload = AgentPendingReceiptPayload(
            protocolVersion: 1,
            sourceLabel: "Test",
            suggestedTrip: nil,
            resolvedTripID: nil,
            resolvedTripName: nil,
            sidecarRawJSON: "{}",
            record: AgentStructuredReceiptRecord(
                merchant: "Cafe",
                date: "2026-07-11",
                total: "12.00",
                currency: "EUR",
                expenseType: "food",
                paymentMethod: "card",
                notes: nil,
                userConfirmed: true
            ),
            fileName: "receipt.jpg",
            contentHash: "test"
        )
        let pending = ReceiptDraft(
            rawOCRText: String(data: try! JSONEncoder().encode(payload), encoding: .utf8)!,
            pipelineVersion: AgentImportBridge.structuredPipelineVersion
        )
        let rawCapture = ReceiptDraft(rawOCRText: "receipt text")

        XCTAssertEqual(MacDockBadge.pendingCount(in: [pending, rawCapture]), 1)
        XCTAssertEqual(MacDockBadge.label(for: 0), nil)
        XCTAssertEqual(MacDockBadge.label(for: 2), "2")
    }

    func testSidebarUnfiledBadgeCountsOnlyActiveLooseReceipts() {
        let activeUnfiled = Receipt(vendor: "Loose")
        let archivedUnfiled = Receipt(vendor: "Archived loose", isArchived: true)
        let folder = ExpenseGroup(name: "Filed")
        let filed = Receipt(vendor: "Filed", group: folder)
        folder.receipts = [filed]

        let metrics = MacSidebarMetrics(
            groups: [folder],
            receipts: [activeUnfiled, archivedUnfiled, filed]
        )

        XCTAssertEqual(metrics.unfiledReceiptCount, 1)
    }

    func testSidebarArchivedBadgeCountsFoldersAndIgnoresLooseArchivedReceipts() {
        let activeFolder = ExpenseGroup(name: "Active")
        let archivedFolder = ExpenseGroup(name: "Archived", isArchived: true)
        let looseArchivedReceipt = Receipt(vendor: "Loose", isArchived: true)

        let archivedFolderMetrics = MacSidebarMetrics(
            groups: [activeFolder, archivedFolder],
            receipts: []
        )
        let looseArchivedReceiptMetrics = MacSidebarMetrics(
            groups: [activeFolder],
            receipts: [looseArchivedReceipt]
        )
        let emptyMetrics = MacSidebarMetrics(groups: [activeFolder], receipts: [])

        XCTAssertEqual(archivedFolderMetrics.archivedFolderCount, 1)
        XCTAssertTrue(archivedFolderMetrics.showsArchivedDestination)
        XCTAssertEqual(looseArchivedReceiptMetrics.archivedFolderCount, 0)
        XCTAssertTrue(looseArchivedReceiptMetrics.showsArchivedDestination)
        XCTAssertFalse(emptyMetrics.showsArchivedDestination)
    }

    func testSidebarExpansionRestorationDefaultsInvalidValuesToExpanded() {
        XCTAssertTrue(
            MacSidebarFoldersExpansion.isExpanded(restoredValue: "")
        )
        XCTAssertTrue(
            MacSidebarFoldersExpansion.isExpanded(restoredValue: "not-a-valid-value")
        )
        XCTAssertFalse(
            MacSidebarFoldersExpansion.isExpanded(restoredValue: "collapsed")
        )
        XCTAssertEqual(MacSidebarFoldersExpansion.restoredValue(isExpanded: true), "expanded")
        XCTAssertEqual(MacSidebarFoldersExpansion.restoredValue(isExpanded: false), "collapsed")
    }

    func testContentZoomStepsClampAndReset() {
        var zoom = MacContentZoom(step: 0)
        XCTAssertEqual(zoom.factor, 1)

        zoom.zoomIn()
        XCTAssertGreaterThan(zoom.factor, 1)
        zoom.reset()
        XCTAssertEqual(zoom.step, 0)

        for _ in 0..<20 { zoom.zoomOut() }
        XCTAssertFalse(zoom.canZoomOut)
        XCTAssertTrue(zoom.canZoomIn)
    }

    func testSearchMatchesVendorAndNotesUsingLocalizedComparison() {
        let receipt = Receipt(vendor: "Café Müller", notes: "Team dinner")

        XCTAssertTrue(MacReceiptSearch.matches(receipt, query: "cafe"))
        XCTAssertTrue(MacReceiptSearch.matches(receipt, query: "DINNER"))
        XCTAssertFalse(MacReceiptSearch.matches(receipt, query: "hotel"))
    }

    func testMultiPageDragMaterializesOneFolderWithEveryPage() throws {
        let url = try MacReceiptFileMaterializer.transferURL(
            vendor: "Café / Test",
            pages: [Data([0xFF, 0xD8]), Data([0x89, 0x50, 0x4E, 0x47])]
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path).count, 2)
    }

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
        context.undoManager = UndoManager()
        return context
    }

}
