import ExpenseCore
import SwiftData
import UIKit
import XCTest
@testable import IntelliExpense

@MainActor
final class AgentImportBridgeTests: XCTestCase {
    func testStructuredValidationKeepsDecimalExactAndRejectsInvalidFields() throws {
        let record = validRecord(total: "1234.56")

        let validated = try AgentImportRecordValidator.validate(record)

        XCTAssertEqual(validated.total, Decimal(string: "1234.56")!)
        XCTAssertEqual(validated.currency, "EUR")
        XCTAssertEqual(validated.categoryID, "food")
        XCTAssertEqual(validated.paymentMethod, .card)

        try assertValidationFailure(.merchantInvalid) {
            var invalid = record
            invalid.merchant = "  "
            return invalid
        }
        try assertValidationFailure(.dateInvalid) {
            var invalid = record
            invalid.date = "14/06/2026"
            return invalid
        }
        try assertValidationFailure(.totalInvalid) {
            var invalid = record
            invalid.total = "1234,56"
            return invalid
        }
        try assertValidationFailure(.currencyInvalid) {
            var invalid = record
            invalid.currency = "EURO"
            return invalid
        }
        try assertValidationFailure(.expenseTypeInvalid) {
            var invalid = record
            invalid.expenseType = "meal"
            return invalid
        }
        try assertValidationFailure(.paymentMethodInvalid) {
            var invalid = record
            invalid.paymentMethod = "wire"
            return invalid
        }
    }

    func testStructuredLandingMatrixRequiresAttestationAndAutoSettingForConfirmedReceipt() async throws {
        let manualAttested = try await runStructuredDrop(userConfirmed: true, requiresReview: true)
        XCTAssertEqual(try manualAttested.context.fetch(FetchDescriptor<Receipt>()).count, 0)
        XCTAssertEqual(try manualAttested.context.fetch(FetchDescriptor<ReceiptDraft>()).count, 1)

        let autoAttested = try await runStructuredDrop(userConfirmed: true, requiresReview: false)
        let receipts = try autoAttested.context.fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.vendor, "REWE CITY")
        XCTAssertEqual(receipts.first?.totalAmount, Decimal(string: "84.50")!)
        XCTAssertEqual(receipts.first?.group?.name, "Berlin Trip")
        XCTAssertEqual(receipts.first?.attachments?.count, 1)
        XCTAssertEqual(receipts.first?.extraction?.pipelineVersion, AgentImportBridge.structuredPipelineVersion)
        XCTAssertEqual(receipts.first?.extraction?.rawOCRText, autoAttested.sidecarRawJSON)
        XCTAssertEqual(receipts.first?.extraction?.modelOutputJSON, autoAttested.sidecarRawJSON)
        XCTAssertEqual(try autoAttested.context.fetch(FetchDescriptor<ReceiptDraft>()).count, 0)

        let autoUnattested = try await runStructuredDrop(userConfirmed: false, requiresReview: false)
        XCTAssertEqual(try autoUnattested.context.fetch(FetchDescriptor<Receipt>()).count, 0)
        XCTAssertEqual(try autoUnattested.context.fetch(FetchDescriptor<ReceiptDraft>()).count, 1)
    }

    func testPendingAgentEntrySavesThroughExistingReviewFlowWithAgentProvenance() async throws {
        let result = try await runStructuredDrop(userConfirmed: true, requiresReview: true)
        let draft = try XCTUnwrap(try result.context.fetch(FetchDescriptor<ReceiptDraft>()).first)
        let entries = AgentPendingEntry.entries(from: [draft])
        let entry = try XCTUnwrap(entries.first)
        let form = try XCTUnwrap(entry.makeReviewForm(defaultCurrencyCode: "USD", defaultPaymentMethod: .cash))

        XCTAssertEqual(form.vendor, "REWE CITY")
        XCTAssertEqual(form.amountText, "84.50")
        XCTAssertEqual(form.currencyCode, "EUR")
        XCTAssertEqual(form.categoryID, "food")
        XCTAssertEqual(form.paymentMethod, .card)

        let receipt = try form.save(in: result.context, group: entry.resolvedGroup(in: [result.group]))

        XCTAssertEqual(receipt.vendor, "REWE CITY")
        XCTAssertEqual(receipt.group?.name, "Berlin Trip")
        XCTAssertEqual(receipt.extraction?.pipelineVersion, AgentImportBridge.structuredPipelineVersion)
        XCTAssertEqual(receipt.extraction?.rawOCRText, result.sidecarRawJSON)
        XCTAssertEqual(receipt.extraction?.modelOutputJSON, result.sidecarRawJSON)
        XCTAssertTrue(try result.context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
    }

    func testPendingAgentEntryDismissKeepsDraftForLaterConfirmation() async throws {
        let result = try await runStructuredDrop(userConfirmed: true, requiresReview: true)
        let draft = try XCTUnwrap(try result.context.fetch(FetchDescriptor<ReceiptDraft>()).first)
        let entry = try XCTUnwrap(AgentPendingEntry.entries(from: [draft]).first)
        let form = try XCTUnwrap(entry.makeReviewForm(defaultCurrencyCode: "USD", defaultPaymentMethod: .cash))

        XCTAssertTrue(form.preservesPendingDraftOnDiscard)
        form.discardIfUnsaved(in: result.context)

        let draftsAfterDismiss = try result.context.fetch(FetchDescriptor<ReceiptDraft>())
        XCTAssertEqual(draftsAfterDismiss.count, 1)
        XCTAssertEqual(AgentPendingEntry.entries(from: draftsAfterDismiss).count, 1)
        XCTAssertTrue(try result.context.fetch(FetchDescriptor<Receipt>()).isEmpty)

        _ = try form.save(in: result.context, group: entry.resolvedGroup(in: [result.group]))

        XCTAssertTrue(try result.context.fetch(FetchDescriptor<ReceiptDraft>()).isEmpty)
        XCTAssertEqual(try result.context.fetch(FetchDescriptor<Receipt>()).count, 1)
    }

    func testManifestIncludesArchivedFlagAndReceiptMetadata() throws {
        let context = try makeContext()
        let active = ExpenseGroup(
            name: "Berlin Trip",
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30)
        )
        let archived = ExpenseGroup(
            name: "Old Trip",
            startDate: date(2025, 6, 1),
            endDate: date(2025, 6, 30),
            isArchived: true,
            archivedAt: date(2025, 7, 1)
        )
        let eurReceipt = Receipt(
            vendor: "REWE",
            date: date(2026, 6, 14),
            totalAmount: Decimal(string: "84.50")!,
            currencyCode: "EUR",
            expenseType: .food,
            paymentMethod: .card,
            group: active
        )
        let usdReceipt = Receipt(
            vendor: "Taxi",
            date: date(2026, 6, 15),
            totalAmount: Decimal(string: "20")!,
            currencyCode: "USD",
            expenseType: .taxi,
            paymentMethod: .cash,
            group: active
        )
        active.receipts = [eurReceipt, usdReceipt]
        context.insert(active)
        context.insert(archived)
        context.insert(eurReceipt)
        context.insert(usdReceipt)
        try context.save()

        let inbox = try AgentImportInbox(rootURL: makeTemporaryRoot())
        try inbox.writeManifest(groups: [active, archived])

        let manifest = try JSONDecoder().decode(AgentImportManifest.self, from: Data(contentsOf: inbox.manifestURL))
        let activeTrip = try XCTUnwrap(manifest.trips.first { $0.name == "Berlin Trip" })
        let archivedTrip = try XCTUnwrap(manifest.trips.first { $0.name == "Old Trip" })
        XCTAssertFalse(activeTrip.archived)
        XCTAssertEqual(activeTrip.receiptCount, 2)
        XCTAssertEqual(activeTrip.currenciesPresent, ["EUR", "USD"])
        XCTAssertEqual(activeTrip.startDate, "2026-06-01")
        XCTAssertEqual(activeTrip.endDate, "2026-06-30")
        XCTAssertTrue(archivedTrip.archived)
    }

    func testJSONNumberTotalFailsWithoutCallingExtraction() async throws {
        let root = makeTemporaryRoot()
        let inbox = try AgentImportInbox(rootURL: root)
        try inbox.ensureDirectories()
        let receiptURL = inbox.inboxURL.appendingPathComponent("drop.jpg")
        try makeImageData(label: "Number total").write(to: receiptURL)
        let sidecar = """
        {
          "protocolVersion": 1,
          "mode": "structured",
          "sourceLabel": "codex",
          "receipt": {
            "merchant": "REWE CITY",
            "date": "2026-06-14",
            "total": 84.50,
            "currency": "EUR",
            "expenseType": "food",
            "paymentMethod": "card",
            "userConfirmed": true
          }
        }
        """
        try Data(sidecar.utf8).write(to: inbox.inboxURL.appendingPathComponent("drop.json"))
        let context = try makeContext()
        let processor = makeProcessor(inbox: inbox, context: context, failIfPipelineRuns: true)

        await processor.processPendingDrops(
            groups: [],
            requiresReview: false,
            defaultCurrencyCode: "USD",
            defaultPaymentMethod: .card
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<Receipt>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptDraft>()).count, 0)
        let failure = try readOnlyFailure(inbox: inbox)
        XCTAssertEqual(failure.reason, .invalidJSON)
    }

    func testRawSidecarLessDropUsesPipelineAndCreatesDraft() async throws {
        let root = makeTemporaryRoot()
        let inbox = try AgentImportInbox(rootURL: root)
        try inbox.ensureDirectories()
        let receiptURL = inbox.inboxURL.appendingPathComponent("raw.jpg")
        try makeImageData(label: "Raw drop").write(to: receiptURL)
        let context = try makeContext()
        var pipelineCalls = 0
        let processor = makeProcessor(inbox: inbox, context: context) {
            pipelineCalls += 1
            return self.makePipeline(
                context: context,
                ocrText: "Cafe\nTotal USD 12.40\nCash"
            )
        }

        let result = await processor.processPendingDrops(
            groups: [],
            requiresReview: true,
            defaultCurrencyCode: "USD",
            defaultPaymentMethod: .cash
        )

        XCTAssertEqual(pipelineCalls, 1)
        XCTAssertEqual(result.rawReview?.form.vendor, "Cafe")
        let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.rawOCRText, "Cafe\nTotal USD 12.40\nCash")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Receipt>()).count, 0)
    }

    private func runStructuredDrop(
        userConfirmed: Bool,
        requiresReview: Bool
    ) async throws -> (context: ModelContext, inbox: AgentImportInbox, group: ExpenseGroup, sidecarRawJSON: String) {
        let root = makeTemporaryRoot()
        let inbox = try AgentImportInbox(rootURL: root)
        try inbox.ensureDirectories()
        let context = try makeContext()
        let group = ExpenseGroup(name: "Berlin Trip")
        context.insert(group)
        try context.save()

        let receiptURL = inbox.inboxURL.appendingPathComponent("drop.jpg")
        try makeImageData(label: "REWE").write(to: receiptURL)
        let sidecar = AgentImportSidecar(
            protocolVersion: AgentImportBridge.protocolVersion,
            mode: .structured,
            suggestedTrip: AgentImportTripSuggestion(id: nil, name: "Berlin Trip"),
            note: "Entered from a fixture folder.",
            sourceLabel: "codex",
            receipt: validRecord(total: "84.50", userConfirmed: userConfirmed)
        )
        let sidecarRawJSON = try encodeSidecar(sidecar)
        try Data(sidecarRawJSON.utf8).write(to: inbox.inboxURL.appendingPathComponent("drop.json"))
        let processor = makeProcessor(inbox: inbox, context: context, failIfPipelineRuns: true)

        await processor.processPendingDrops(
            groups: [group],
            requiresReview: requiresReview,
            defaultCurrencyCode: "USD",
            defaultPaymentMethod: .cash
        )

        XCTAssertTrue(try inbox.pendingDrops().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: inbox.processedURL, includingPropertiesForKeys: nil).count, 1)
        return (context, inbox, group, sidecarRawJSON)
    }

    private func makeProcessor(
        inbox: AgentImportInbox,
        context: ModelContext,
        failIfPipelineRuns: Bool
    ) -> AgentImportProcessor {
        makeProcessor(inbox: inbox, context: context) {
            if failIfPipelineRuns {
                XCTFail("Structured agent imports must not run OCR, parsing, or model extraction.")
            }
            return self.makePipeline(context: context, ocrText: "")
        }
    }

    private func makeProcessor(
        inbox: AgentImportInbox,
        context: ModelContext,
        makePipeline: @escaping () -> ReceiptProcessingPipeline
    ) -> AgentImportProcessor {
        let builder = ReceiptCapturePageBuilder(maxImageDimension: 500, thumbnailDimension: 120)
        return AgentImportProcessor(
            inbox: inbox,
            fileProcessor: ReceiptFileIngestionProcessor(
                pageBuilder: builder,
                pdfRasterizer: PDFReceiptPageRasterizer(pageBuilder: builder),
                makePipeline: makePipeline
            ),
            context: context
        )
    }

    private func makePipeline(context: ModelContext, ocrText: String) -> ReceiptProcessingPipeline {
        ReceiptProcessingPipeline(
            context: context,
            ocrService: FakeOCRService(
                result: .success(
                    OCRResult(
                        pages: [
                            OCRTextPage(id: "page-0", pageIndex: 0, text: ocrText, confidence: 0.9)
                        ]
                    )
                )
            ),
            modelService: FakeExtractionModelService(result: .success(ModelExtractedReceipt())),
            availabilityProvider: FakeModelAvailabilityProvider(status: .modelNotReady),
            parser: ReceiptParser(
                referenceDate: date(2026, 12, 31),
                defaultCurrencyCode: "USD",
                locale: Locale(identifier: "en_US")
            ),
            mergePolicy: ReceiptMergePolicy(),
            locale: Locale(identifier: "en_US")
        )
    }

    private func assertValidationFailure(
        _ expectedReason: AgentImportFailureReason,
        mutate: () -> AgentStructuredReceiptRecord
    ) throws {
        do {
            _ = try AgentImportRecordValidator.validate(mutate())
            XCTFail("Expected validation to fail with \(expectedReason.rawValue)")
        } catch let error as AgentImportValidationError {
            XCTAssertEqual(error.reason, expectedReason)
        }
    }

    private func validRecord(
        total: String = "84.50",
        userConfirmed: Bool = true
    ) -> AgentStructuredReceiptRecord {
        AgentStructuredReceiptRecord(
            merchant: "REWE CITY",
            date: "2026-06-14",
            total: total,
            currency: "EUR",
            expenseType: ExpenseType.food.rawValue,
            paymentMethod: PaymentMethod.card.rawValue,
            notes: "Team dinner",
            userConfirmed: userConfirmed
        )
    }

    private func encodeSidecar(_ sidecar: AgentImportSidecar) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sidecar)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func readOnlyFailure(inbox: AgentImportInbox) throws -> AgentImportFailure {
        let folders = try FileManager.default.contentsOfDirectory(at: inbox.failedURL, includingPropertiesForKeys: nil)
        let folder = try XCTUnwrap(folders.first)
        return try JSONDecoder().decode(
            AgentImportFailure.self,
            from: Data(contentsOf: folder.appendingPathComponent("reason.json"))
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
    }

    private func makeTemporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentImportBridgeTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func makeImageData(label: String) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 420))
        let image = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 420))
            label.draw(
                in: CGRect(x: 24, y: 170, width: 272, height: 80),
                withAttributes: [
                    .font: UIFont.preferredFont(forTextStyle: .title1),
                    .foregroundColor: UIColor.label
                ]
            )
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        ).date!
    }
}
