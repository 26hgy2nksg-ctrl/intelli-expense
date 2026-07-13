import SwiftUI

extension ToolbarItemPlacement {
    static var expenseLeadingAction: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarLeading
        #endif
    }

    static var expenseTrailingAction: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}
