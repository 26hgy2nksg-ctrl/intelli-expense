import ExpenseCore
import CloudKit
import SwiftData
import XCTest
@testable import IntelliExpense

@MainActor
final class PersistenceTests: XCTestCase {
    func testModelDefaultsAreCloudKitCompatible() {
        let group = ExpenseGroup()
        XCTAssertEqual(group.name, "")
        XCTAssertFalse(group.isArchived)
        XCTAssertNil(group.archivedAt)
        XCTAssertNil(group.pinnedAt)
        XCTAssertNotNil(group.receipts)

        let receipt = Receipt()
        XCTAssertEqual(receipt.vendor, "")
        XCTAssertEqual(receipt.totalAmount, .zero)
        XCTAssertEqual(receipt.currencyCode, "USD")
        XCTAssertEqual(receipt.expenseType, .other)
        XCTAssertEqual(receipt.paymentMethod, .card)
        XCTAssertFalse(receipt.isArchived)
        XCTAssertNil(receipt.archivedAt)
        XCTAssertNil(receipt.group)
        XCTAssertNotNil(receipt.attachments)
        XCTAssertNil(receipt.extraction)

        let attachment = ReceiptAttachment()
        XCTAssertEqual(attachment.imageData, Data())
        XCTAssertNil(attachment.thumbnailData)
        XCTAssertNil(attachment.receipt)

        let extraction = ExtractionRecord()
        XCTAssertEqual(extraction.rawOCRText, "")
        XCTAssertNil(extraction.modelOutputJSON)
        XCTAssertNil(extraction.ocrConfidence)
        XCTAssertNil(extraction.receipt)
    }

    func testInMemoryContainerPersistsReceiptAttachmentAndExtractionGraph() throws {
        let context = try makeContext()
        let group = ExpenseGroup(name: "Berlin June")
        let receipt = Receipt(
            vendor: "REWE CITY",
            date: date(2026, 6, 14),
            totalAmount: Decimal(string: "84.50")!,
            currencyCode: "eur",
            expenseType: .food,
            paymentMethod: .cash,
            group: group
        )
        let attachment = ReceiptAttachment(
            imageData: Data([0x01, 0x02, 0x03]),
            thumbnailData: Data([0x09]),
            pageIndex: 0,
            sourceType: .photoImport
        )
        let extraction = ExtractionRecord(
            rawOCRText: "REWE CITY\nSUMME 84,50",
            modelOutputJSON: "{\"total\":\"84.50\"}",
            pipelineVersion: "v1-test",
            userCorrectedFields: ["paymentMethod"]
        )

        receipt.attachments = [attachment]
        attachment.receipt = receipt
        receipt.extraction = extraction
        extraction.receipt = receipt

        context.insert(group)
        context.insert(receipt)
        context.insert(attachment)
        context.insert(extraction)
        try context.save()

        let receipts = try fetchReceipts(context)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].group?.name, "Berlin June")
        XCTAssertEqual(receipts[0].currencyCode, "EUR")
        XCTAssertEqual(receipts[0].attachments?.first?.sourceType, .photoImport)
        XCTAssertEqual(receipts[0].extraction?.pipelineVersion, "v1-test")
        XCTAssertEqual(receipts[0].extraction?.userCorrectedFields, ["paymentMethod"])
    }

    func testDeletingGroupCanKeepReceiptsUnfiled() throws {
        let context = try makeContext()
        let group = ExpenseGroup(name: "Paris")
        let receipt = Receipt(vendor: "Cafe", totalAmount: 10, currencyCode: "EUR", isArchived: true, group: group)
        group.receipts = [receipt]

        context.insert(group)
        context.insert(receipt)
        try context.save()

        ReceiptStore.delete(group: group, receiptPolicy: .keepReceiptsUnfiled, in: context)
        try context.save()

        let receipts = try fetchReceipts(context)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertNil(receipts[0].group)
        XCTAssertTrue(receipts[0].isArchived)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExpenseGroup>()).isEmpty)
    }

    func testDeletingGroupCanDeleteReceipts() throws {
        let context = try makeContext()
        let group = ExpenseGroup(name: "Taxi Trip")
        let receipt = Receipt(vendor: "Taxi", totalAmount: 42, currencyCode: "USD", group: group)
        let archived = Receipt(vendor: "Archived Taxi", totalAmount: 7, currencyCode: "USD", isArchived: true, group: group)
        group.receipts = [receipt, archived]

        context.insert(group)
        context.insert(receipt)
        context.insert(archived)
        try context.save()

        ReceiptStore.delete(group: group, receiptPolicy: .deleteReceipts, in: context)
        try context.save()

        XCTAssertTrue(try fetchReceipts(context).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExpenseGroup>()).isEmpty)
    }

    func testArchiveAndRestoreReceiptState() throws {
        let context = try makeContext()
        let receipt = Receipt(vendor: "Cafe", totalAmount: 10, currencyCode: "EUR")
        context.insert(receipt)
        try context.save()

        try ReceiptStore.archive(receipt, in: context)

        XCTAssertTrue(receipt.isArchived)
        XCTAssertNotNil(receipt.archivedAt)

        try ReceiptStore.restore(receipt, in: context)

        XCTAssertFalse(receipt.isArchived)
        XCTAssertNil(receipt.archivedAt)
    }

    func testArchiveAndRestoreGroupStateDoesNotWriteReceiptFlags() throws {
        let context = try makeContext()
        let group = ExpenseGroup(name: "Berlin", pinnedAt: date(2026, 7, 4))
        let activeReceipt = Receipt(vendor: "Active Cafe", totalAmount: 10, currencyCode: "EUR", group: group)
        let individuallyArchivedReceipt = Receipt(vendor: "Old Taxi", totalAmount: 5, currencyCode: "EUR", isArchived: true, group: group)
        group.receipts = [activeReceipt, individuallyArchivedReceipt]
        context.insert(group)
        context.insert(activeReceipt)
        context.insert(individuallyArchivedReceipt)
        try context.save()

        try ReceiptStore.archive(group, in: context)

        XCTAssertTrue(group.isArchived)
        XCTAssertNotNil(group.archivedAt)
        XCTAssertNil(group.pinnedAt)
        XCTAssertFalse(activeReceipt.isArchived)
        XCTAssertTrue(activeReceipt.isEffectivelyArchived)
        XCTAssertTrue(individuallyArchivedReceipt.isArchived)

        try ReceiptStore.restore(group, in: context)

        XCTAssertFalse(group.isArchived)
        XCTAssertNil(group.archivedAt)
        XCTAssertFalse(activeReceipt.isArchived)
        XCTAssertFalse(activeReceipt.isEffectivelyArchived)
        XCTAssertTrue(individuallyArchivedReceipt.isArchived)
        XCTAssertTrue(individuallyArchivedReceipt.isEffectivelyArchived)
    }

    func testPinAndUnpinGroupPersistThePresentationPreference() throws {
        let context = try makeContext()
        let group = ExpenseGroup(name: "Claim")
        let pinDate = date(2026, 7, 4)
        context.insert(group)
        try context.save()

        try ReceiptStore.pin(group, at: pinDate, in: context)
        XCTAssertEqual(group.pinnedAt, pinDate)

        try ReceiptStore.unpin(group, in: context)
        XCTAssertNil(group.pinnedAt)
    }

    func testExpiredDraftSweepDeletesOnlyOldDrafts() throws {
        let context = try makeContext()
        let now = date(2026, 7, 5)
        let oldDraft = ReceiptDraft(
            rawOCRText: "Old",
            createdAt: now.addingTimeInterval(-72 * 60 * 60),
            lastUpdatedAt: now.addingTimeInterval(-60 * 60 * 60)
        )
        let oldPage = ReceiptDraftPage(imageData: Data([0x01]), pageIndex: 0, draft: oldDraft)
        oldDraft.pages = [oldPage]
        let recentDraft = ReceiptDraft(
            rawOCRText: "Recent",
            createdAt: now.addingTimeInterval(-72 * 60 * 60),
            lastUpdatedAt: now.addingTimeInterval(-2 * 60 * 60)
        )
        context.insert(oldDraft)
        context.insert(oldPage)
        context.insert(recentDraft)
        try context.save()

        try ReceiptStore.sweepExpiredDrafts(in: context, now: now)

        let drafts = try context.fetch(FetchDescriptor<ReceiptDraft>())
        XCTAssertEqual(drafts.map(\.rawOCRText), ["Recent"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptDraftPage>()).count, 0)
    }

    func testActiveReceiptsHelperReturnsOnlyUnarchivedReceipts() {
        let group = ExpenseGroup(name: "Trip")
        let active = Receipt(vendor: "Active", totalAmount: 10, currencyCode: "EUR")
        let archived = Receipt(vendor: "Archived", totalAmount: 5, currencyCode: "EUR", isArchived: true)
        group.receipts = [archived, active]

        XCTAssertEqual(Set(group.activeReceipts.map(\.vendor)), ["Active"])
    }

    func testGroupsSortByMostRecentActivityDate() {
        let olderCreated = ExpenseGroup(name: "Older Created", createdAt: date(2026, 5, 1))
        olderCreated.receipts = [
            Receipt(vendor: "Recent Taxi", date: date(2026, 7, 1), totalAmount: 12, currencyCode: "EUR")
        ]
        let newerCreated = ExpenseGroup(name: "Newer Created", createdAt: date(2026, 6, 1))
        newerCreated.receipts = [
            Receipt(vendor: "Old Hotel", date: date(2026, 5, 2), totalAmount: 90, currencyCode: "EUR")
        ]
        let archived = ExpenseGroup(name: "Archived", createdAt: date(2026, 8, 1), isArchived: true)

        XCTAssertEqual(
            ExpenseGroup.sortedByMostRecentActivity([archived, newerCreated, olderCreated]).map(\.name),
            ["Older Created", "Newer Created"]
        )
    }

    func testPinnedFirstSortingPromotesPinnedGroupsAboveNewerActivity() {
        let pinned = ExpenseGroup(
            name: "Pinned",
            createdAt: date(2026, 5, 1),
            pinnedAt: date(2026, 7, 1)
        )
        let active = ExpenseGroup(name: "Active", createdAt: date(2026, 7, 5))

        XCTAssertEqual(
            ExpenseGroup.sortedPinnedFirst([active, pinned]).map(\.name),
            ["Pinned", "Active"]
        )
        XCTAssertEqual(
            ExpenseGroup.sortedByMostRecentActivity([active, pinned]).map(\.name),
            ["Active", "Pinned"],
            "Capture routing must continue to ignore presentation pinning"
        )
    }

    func testPinnedFirstSortingUsesPinRecencyThenActivityAndNameForTies() {
        let newestPin = ExpenseGroup(
            name: "Newest Pin",
            createdAt: date(2026, 4, 1),
            pinnedAt: date(2026, 7, 2)
        )
        let activeTieWinner = ExpenseGroup(
            name: "Zulu",
            createdAt: date(2026, 6, 2),
            pinnedAt: date(2026, 7, 1)
        )
        let nameTieWinner = ExpenseGroup(
            name: "Alpha",
            createdAt: date(2026, 6, 1),
            pinnedAt: date(2026, 7, 1)
        )
        nameTieWinner.receipts = [
            Receipt(vendor: "Recent", date: date(2026, 6, 2), totalAmount: 1, currencyCode: "USD")
        ]
        let archivedPin = ExpenseGroup(
            name: "Archived",
            createdAt: date(2026, 8, 1),
            isArchived: true,
            pinnedAt: date(2026, 8, 1)
        )

        XCTAssertEqual(
            ExpenseGroup.sortedPinnedFirst([nameTieWinner, archivedPin, activeTieWinner, newestPin]).map(\.name),
            ["Newest Pin", "Alpha", "Zulu"]
        )
    }

    func testArchivedGroupsSortByArchivedAtDescending() {
        let older = ExpenseGroup(name: "Older", archivedAt: date(2026, 6, 1))
        older.isArchived = true
        let newer = ExpenseGroup(name: "Newer", archivedAt: date(2026, 7, 1))
        newer.isArchived = true
        let active = ExpenseGroup(name: "Active")

        XCTAssertEqual(
            ExpenseGroup.sortedByMostRecentArchive([older, active, newer]).map(\.name),
            ["Newer", "Older"]
        )
    }

    func testReceiptListGroupFilterComposesWithTypeAndPayment() throws {
        let context = try makeContext()
        let berlin = ExpenseGroup(name: "Berlin")
        let berlinTaxi = Receipt(
            vendor: "Berlin Taxi",
            totalAmount: 40,
            currencyCode: "EUR",
            expenseType: .taxi,
            paymentMethod: .cash,
            group: berlin
        )
        let berlinMeal = Receipt(
            vendor: "Berlin Meal",
            totalAmount: 20,
            currencyCode: "EUR",
            expenseType: .food,
            paymentMethod: .cash,
            group: berlin
        )
        let unfiledTaxi = Receipt(
            vendor: "Unfiled Taxi",
            totalAmount: 30,
            currencyCode: "EUR",
            expenseType: .taxi,
            paymentMethod: .cash
        )
        berlin.receipts = [berlinTaxi, berlinMeal]
        context.insert(berlin)
        [berlinTaxi, berlinMeal, unfiledTaxi].forEach { context.insert($0) }
        try context.save()

        let filter = ReceiptListFilter(
            groupFilter: .group(berlin.persistentModelID),
            typeFilter: "taxi",
            paymentFilter: .cash
        )

        XCTAssertEqual(
            filter.filtered([berlinMeal, unfiledTaxi, berlinTaxi]).map(\.vendor),
            ["Berlin Taxi"]
        )
    }

    func testReceiptListFilterUsesEffectiveArchiveRule() {
        let archivedGroup = ExpenseGroup(name: "Archived Trip", isArchived: true)
        let tripArchivedReceipt = Receipt(vendor: "Trip Receipt", totalAmount: 20, currencyCode: "EUR", group: archivedGroup)
        let individuallyArchivedInArchivedTrip = Receipt(vendor: "Hidden Archived", totalAmount: 30, currencyCode: "EUR", isArchived: true, group: archivedGroup)
        let individuallyArchived = Receipt(vendor: "Archived Receipt", totalAmount: 5, currencyCode: "EUR", isArchived: true)
        let active = Receipt(vendor: "Active Receipt", totalAmount: 10, currencyCode: "EUR")
        archivedGroup.receipts = [tripArchivedReceipt, individuallyArchivedInArchivedTrip]

        XCTAssertEqual(
            ReceiptListFilter(receiptMode: .active)
                .filtered([tripArchivedReceipt, individuallyArchivedInArchivedTrip, individuallyArchived, active])
                .map(\.vendor),
            ["Active Receipt"]
        )
        XCTAssertEqual(
            ReceiptListFilter(receiptMode: .archived)
                .filtered([tripArchivedReceipt, individuallyArchivedInArchivedTrip, individuallyArchived, active])
                .map(\.vendor),
            ["Archived Receipt"]
        )
    }

    func testICloudAccountStatusMappingIsHonestAndMinimal() {
        XCTAssertEqual(ICloudAccountStatus.map(.available), .available)
        XCTAssertEqual(ICloudAccountStatus.map(.noAccount), .unavailable)
        XCTAssertEqual(ICloudAccountStatus.map(.restricted), .unavailable)
        XCTAssertEqual(ICloudAccountStatus.map(.couldNotDetermine), .unavailable)
    }

    func testDefaultCurrencySeedsOnceFromLocaleCurrency() {
        let defaults = makeIsolatedDefaults()

        DefaultCurrencySettings.seedIfNeeded(defaults: defaults, locale: Locale(identifier: "en_IN"))

        XCTAssertEqual(defaults.string(forKey: DefaultCurrencySettings.defaultCodeKey), "INR")
        XCTAssertTrue(defaults.bool(forKey: DefaultCurrencySettings.seedFlagKey))
    }

    func testDefaultCurrencyFallsBackToUSDWhenLocaleHasNoISOCurrency() {
        let defaults = makeIsolatedDefaults()

        DefaultCurrencySettings.seedIfNeeded(defaults: defaults, locale: Locale(identifier: "en_001"))

        XCTAssertEqual(defaults.string(forKey: DefaultCurrencySettings.defaultCodeKey), "USD")
        XCTAssertTrue(defaults.bool(forKey: DefaultCurrencySettings.seedFlagKey))
    }

    func testDefaultCurrencyRetroactiveSeedPreservesExistingLegacyValue() {
        let defaults = makeIsolatedDefaults()
        defaults.set("legacy-token", forKey: DefaultCurrencySettings.defaultCodeKey)

        DefaultCurrencySettings.seedIfNeeded(defaults: defaults, locale: Locale(identifier: "en_IN"))

        XCTAssertEqual(defaults.string(forKey: DefaultCurrencySettings.defaultCodeKey), "legacy-token")
        XCTAssertTrue(defaults.bool(forKey: DefaultCurrencySettings.seedFlagKey))
        XCTAssertNil(CurrencyCatalog.option(for: "legacy-token", locale: Locale(identifier: "en_US")))
    }

    func testDefaultCurrencyPickerSelectionRepairsLegacyValue() {
        let defaults = makeIsolatedDefaults()
        defaults.set("legacy-token", forKey: DefaultCurrencySettings.defaultCodeKey)
        DefaultCurrencySettings.seedIfNeeded(defaults: defaults, locale: Locale(identifier: "en_IN"))

        DefaultCurrencySettings.storeSelectedCode("inr", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: DefaultCurrencySettings.defaultCodeKey), "INR")
        XCTAssertTrue(defaults.bool(forKey: DefaultCurrencySettings.seedFlagKey))
    }

    func testGroupSummaryUsesExpenseCoreTotalsByCurrencyAndType() {
        let group = ExpenseGroup(name: "Mixed Currency")
        group.receipts = [
            Receipt(vendor: "A", totalAmount: Decimal(string: "10.25")!, currencyCode: "EUR", expenseType: .food, paymentMethod: .card),
            Receipt(vendor: "B", totalAmount: Decimal(string: "5.75")!, currencyCode: "EUR", expenseType: .taxi, paymentMethod: .cash),
            Receipt(vendor: "C", totalAmount: Decimal(string: "9.00")!, currencyCode: "USD", expenseType: .food, paymentMethod: .cash),
            Receipt(vendor: "Archived", totalAmount: Decimal(string: "99.00")!, currencyCode: "EUR", expenseType: .hotel, paymentMethod: .card, isArchived: true)
        ]

        let summary = ExpenseGroupSummary.make(for: group)

        XCTAssertEqual(
            summary.totals,
            [
                CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "16.00")!),
                CurrencyTotal(currencyCode: "USD", amount: Decimal(string: "9.00")!)
            ]
        )
        XCTAssertEqual(summary.breakdown["food"]?.count, 2)
        XCTAssertEqual(summary.breakdown["taxi"]?.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "5.75")!)])
        XCTAssertNil(summary.breakdown["hotel"])
    }

    func testCurrencyTotalsPresentationSplitsPrimaryAndSecondaryCurrencies() {
        let locale = Locale(identifier: "en_US")

        let single = ExpenseFormatters.totalPresentation(
            [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "10.00")!)],
            locale: locale
        )
        XCTAssertEqual(single.primary, "€10.00")
        XCTAssertEqual(single.secondary, [])

        let two = ExpenseFormatters.totalPresentation(
            [
                CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "10.00")!),
                CurrencyTotal(currencyCode: "USD", amount: Decimal(string: "25.00")!)
            ],
            locale: locale
        )
        XCTAssertEqual(two.primary, "$25.00")
        XCTAssertEqual(two.secondary, ["€10.00"])

        let three = ExpenseFormatters.totalPresentation(
            [
                CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "10.00")!),
                CurrencyTotal(currencyCode: "USD", amount: Decimal(string: "25.00")!),
                CurrencyTotal(currencyCode: "INR", amount: Decimal(string: "5.00")!)
            ],
            locale: locale
        )
        XCTAssertEqual(three.primary, "$25.00")
        XCTAssertEqual(three.secondary, ["€10.00", "₹5.00"])
    }

    func testReceiptDateSectionsGroupByIssueDayNewestFirst() {
        let firstJune = date(2026, 6, 1)
        let secondJune = date(2026, 6, 2)
        let mayEnd = date(2026, 5, 31)
        let receipts = [
            Receipt(vendor: "Old Taxi", date: mayEnd, totalAmount: 10, currencyCode: "EUR"),
            Receipt(vendor: "Morning Cafe", date: secondJune, totalAmount: 8, currencyCode: "EUR"),
            Receipt(vendor: "Night Hotel", date: secondJune.addingTimeInterval(18 * 60 * 60), totalAmount: 120, currencyCode: "EUR"),
            Receipt(vendor: "First June", date: firstJune, totalAmount: 5, currencyCode: "EUR")
        ]

        let sections = ReceiptDateSections.sections(for: receipts)

        XCTAssertEqual(sections.count, 3)
        XCTAssertTrue(Calendar.current.isDate(sections[0].day, inSameDayAs: secondJune))
        XCTAssertEqual(sections[0].receipts.map(\.vendor), ["Night Hotel", "Morning Cafe"])
        XCTAssertTrue(Calendar.current.isDate(sections[1].day, inSameDayAs: firstJune))
        XCTAssertTrue(Calendar.current.isDate(sections[2].day, inSameDayAs: mayEnd))
    }

    func testAcceptanceBerlinJuneFiveMixedReceiptsShowCorrectTotalsAndBreakdown() {
        let group = ExpenseGroup(name: "Berlin June 2026")
        group.receipts = [
            Receipt(vendor: "REWE", totalAmount: Decimal(string: "10.00")!, currencyCode: "EUR", expenseType: .food, paymentMethod: .card),
            Receipt(vendor: "Cafe", totalAmount: Decimal(string: "20.00")!, currencyCode: "EUR", expenseType: .food, paymentMethod: .cash),
            Receipt(vendor: "Taxi", totalAmount: Decimal(string: "15.50")!, currencyCode: "EUR", expenseType: .taxi, paymentMethod: .cash),
            Receipt(vendor: "Hotel", totalAmount: Decimal(string: "100.00")!, currencyCode: "EUR", expenseType: .hotel, paymentMethod: .card),
            Receipt(vendor: "Kiosk", totalAmount: Decimal(string: "3.50")!, currencyCode: "EUR", expenseType: .other, paymentMethod: .cash)
        ]

        let summary = ExpenseGroupSummary.make(for: group)

        XCTAssertEqual(summary.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "149.00")!)])
        XCTAssertEqual(summary.breakdown["food"]?.count, 2)
        XCTAssertEqual(summary.breakdown["food"]?.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "30.00")!)])
        XCTAssertEqual(summary.breakdown["taxi"]?.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "15.50")!)])
        XCTAssertEqual(summary.breakdown["hotel"]?.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "100.00")!)])
        XCTAssertEqual(summary.breakdown["other"]?.totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "3.50")!)])
        XCTAssertTrue(group.receipts?.contains { $0.paymentMethod == .card } == true)
        XCTAssertTrue(group.receipts?.contains { $0.paymentMethod == .cash } == true)
    }

    func testAcceptanceEditingSavedReceiptFieldsPersistsAndUpdatesGroupTotals() throws {
        let context = try makeContext()
        let group = ExpenseGroup(name: "Berlin June 2026")
        let receipt = Receipt(
            vendor: "Old Vendor",
            date: date(2026, 6, 14),
            totalAmount: Decimal(string: "10.00")!,
            currencyCode: "EUR",
            expenseType: .food,
            paymentMethod: .card,
            group: group
        )
        group.receipts = [receipt]
        context.insert(group)
        context.insert(receipt)
        try context.save()

        receipt.vendor = "Berlin Taxi"
        receipt.date = date(2026, 6, 15)
        receipt.totalAmount = Decimal(string: "42.25")!
        receipt.currencyCode = "EUR"
        receipt.expenseType = .taxi
        receipt.paymentMethod = .cash
        receipt.notes = "Edited after save"
        try context.save()

        let saved = try XCTUnwrap(fetchReceipts(context).first)
        XCTAssertEqual(saved.vendor, "Berlin Taxi")
        XCTAssertEqual(saved.date, date(2026, 6, 15))
        XCTAssertEqual(saved.totalAmount, Decimal(string: "42.25")!)
        XCTAssertEqual(saved.expenseType, .taxi)
        XCTAssertEqual(saved.paymentMethod, .cash)
        XCTAssertEqual(saved.notes, "Edited after save")
        XCTAssertEqual(ExpenseGroupSummary.make(for: group).totals, [CurrencyTotal(currencyCode: "EUR", amount: Decimal(string: "42.25")!)])
        XCTAssertNil(ExpenseGroupSummary.make(for: group).breakdown["food"])
        XCTAssertEqual(ExpenseGroupSummary.make(for: group).breakdown["taxi"]?.count, 1)
    }

    func testProductionConfigurationUsesPrivateCloudKitDatabase() {
        let configuration = PersistenceStack.productionModelConfiguration()

        XCTAssertEqual(PersistenceStack.cloudKitContainerIdentifier, "iCloud.com.nags.intelliexpense")
        XCTAssertTrue(PersistenceStack.usesProductionCloudKitDatabase(configuration))
        XCTAssertFalse(configuration.isStoredInMemoryOnly)
    }

    func testAutomatedTestProcessesUseInMemoryStore() {
        XCTAssertTrue(
            PersistenceStack.shouldUseInMemoryStoreForCurrentProcess(
                arguments: ["IntelliExpense", "--ui-testing"],
                environment: [:]
            )
        )
        XCTAssertTrue(
            PersistenceStack.shouldUseInMemoryStoreForCurrentProcess(
                arguments: ["IntelliExpense"],
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
        XCTAssertFalse(
            PersistenceStack.shouldUseInMemoryStoreForCurrentProcess(
                arguments: ["IntelliExpense"],
                environment: [:]
            )
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceStack.makeModelContainer(inMemory: true))
    }

    private func fetchReceipts(_ context: ModelContext) throws -> [Receipt] {
        try context.fetch(FetchDescriptor<Receipt>())
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "IntelliExpenseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}
