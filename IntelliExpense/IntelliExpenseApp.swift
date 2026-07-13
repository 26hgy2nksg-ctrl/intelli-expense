import SwiftData
import SwiftUI
import TipKit

@main
struct IntelliExpenseApp: App {
    private let modelContainer: ModelContainer

    init() {
        Self.configureTips(arguments: ProcessInfo.processInfo.arguments)
        do {
            self.modelContainer = try PersistenceStack.makeModelContainer(
                inMemory: PersistenceStack.shouldUseInMemoryStoreForCurrentProcess()
            )
            #if INTELLI_EXPENSE_SANDBOX
            let seedContext = ModelContext(modelContainer)
            try SandboxSeedData.seedIfNeeded(in: seedContext)
            #endif
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    @SceneBuilder
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .modelContainer(modelContainer)
        .commands {
            IntelliExpenseMacCommands()
        }

        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        #endif
    }

    private static func configureTips(arguments: [String]) {
        if arguments.contains("--ui-testing") || arguments.contains("-UITestFakeServices") {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}
