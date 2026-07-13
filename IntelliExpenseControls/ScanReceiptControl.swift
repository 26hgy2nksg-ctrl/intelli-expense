import AppIntents
import SwiftUI
import WidgetKit

struct ScanReceiptControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ScanReceiptIntent()) {
                Label(
                    LocalizedStringResource(
                        "control.scanReceipt.label",
                        defaultValue: "Scan Receipt",
                        table: "AppShortcuts"
                    ),
                    systemImage: "document.viewfinder"
                )
            }
        }
        .displayName(
            LocalizedStringResource(
                "control.scanReceipt.displayName",
                defaultValue: "Scan Receipt",
                table: "AppShortcuts"
            )
        )
        .description(
            LocalizedStringResource(
                "control.scanReceipt.description",
                defaultValue: "Open Intelli-Expense to scan a receipt.",
                table: "AppShortcuts"
            )
        )
    }

    private static var kind: String {
        #if INTELLI_EXPENSE_SANDBOX
        return "com.nags.intelliexpense.sandbox.controls.scanReceipt"
        #else
        return "com.nags.intelliexpense.controls.scanReceipt"
        #endif
    }
}

@main
struct IntelliExpenseControlsBundle: WidgetBundle {
    var body: some Widget {
        ScanReceiptControl()
        QuickCaptureWidget()
    }
}
