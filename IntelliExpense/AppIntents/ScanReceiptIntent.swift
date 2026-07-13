import AppIntents
import Foundation

enum ScanReceiptDestination: String, AppEnum {
    case capture

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "intent.scanReceipt.target",
            defaultValue: "Destination",
            table: "AppShortcuts"
        )
    )

    static let caseDisplayRepresentations: [ScanReceiptDestination: DisplayRepresentation] = [
        .capture: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent.scanReceipt.destination.capture",
                defaultValue: "Scan Receipt",
                table: "AppShortcuts"
            )
        )
    ]
}

struct ScanReceiptIntent: OpenIntent, TargetContentProvidingIntent {
    static let title = LocalizedStringResource(
        "intent.scanReceipt.title",
        defaultValue: "Scan Receipt",
        table: "AppShortcuts"
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "intent.scanReceipt.description",
            defaultValue: "Open Intelli-Expense to scan a receipt.",
            table: "AppShortcuts"
        )
    )
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(
        title: LocalizedStringResource(
            "intent.scanReceipt.target",
            defaultValue: "Destination",
            table: "AppShortcuts"
        )
    )
    var target: ScanReceiptDestination

    init() {
        target = .capture
    }

    init(target: ScanReceiptDestination) {
        self.target = target
    }

}

struct IntelliExpenseShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayGreen }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "Scan a receipt in \(.applicationName)",
                "\(.applicationName) scan",
                "New receipt in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "shortcut.scanReceipt.shortTitle",
                defaultValue: "Scan Receipt",
                table: "AppShortcuts"
            ),
            systemImageName: "document.viewfinder"
        )
    }
}
