import Foundation
import SwiftData

enum PersistenceStack {
    static let cloudKitContainerIdentifier = "iCloud.com.alikaradeniz.expense"

    static var schema: Schema {
        Schema([
            ReceiptDraft.self,
            ReceiptDraftPage.self,
            ExpenseGroup.self,
            Receipt.self,
            ReceiptAttachment.self,
            ExtractionRecord.self
        ])
    }

    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory ? inMemoryModelConfiguration() : productionModelConfiguration()
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func shouldUseInMemoryStoreForCurrentProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--ui-testing") || environment["XCTestConfigurationFilePath"] != nil
    }

    static func inMemoryModelConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "IntelliExpenseInMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }

    static func productionModelConfiguration() -> ModelConfiguration {
        #if INTELLI_EXPENSE_SANDBOX
        ModelConfiguration(
            "IntelliExpenseSandbox",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        #else
        ModelConfiguration(
            "IntelliExpense",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        #endif
    }

    static func usesProductionCloudKitDatabase(_ configuration: ModelConfiguration) -> Bool {
        String(describing: configuration.cloudKitDatabase) == productionCloudKitDatabaseDescription
    }

    private static var productionCloudKitDatabaseDescription: String {
        String(describing: ModelConfiguration.CloudKitDatabase.private(cloudKitContainerIdentifier))
    }
}
