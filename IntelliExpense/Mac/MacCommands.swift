#if os(macOS)
import SwiftUI

struct MacMoveDestination: Identifiable {
    let id: String
    var title: String
    var move: () -> Void
}

struct MacExpenseCommands {
    var newTrip: () -> Void
    var importReceipts: () -> Void
    var exportTrip: () -> Void
    var focusSearch: () -> Void
    var selectAll: () -> Void
    var archiveOrDeleteSelection: () -> Void
    var quickLookSelection: () -> Void
    var renameSelectedTrip: () -> Void
    var showArchived: () -> Void
    var undo: () -> Void
    var redo: () -> Void
    var archiveTitle: String
    var undoTitle: String
    var redoTitle: String
    var moveDestinations: [MacMoveDestination]
    var canSelectAll: Bool
    var canActOnSelection: Bool
    var canQuickLook: Bool
    var canRenameTrip: Bool
    var canUndo: Bool
    var canRedo: Bool
}

struct MacZoomCommands {
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var reset: () -> Void
    var canZoomIn: Bool
    var canZoomOut: Bool
    var canReset: Bool
}

private struct MacExpenseCommandsKey: FocusedValueKey {
    typealias Value = MacExpenseCommands
}

private struct MacZoomCommandsKey: FocusedValueKey {
    typealias Value = MacZoomCommands
}

extension FocusedValues {
    var macExpenseCommands: MacExpenseCommands? {
        get { self[MacExpenseCommandsKey.self] }
        set { self[MacExpenseCommandsKey.self] = newValue }
    }

    var macZoomCommands: MacZoomCommands? {
        get { self[MacZoomCommandsKey.self] }
        set { self[MacZoomCommandsKey.self] = newValue }
    }
}

struct IntelliExpenseMacCommands: Commands {
    @FocusedValue(\.macExpenseCommands) private var commands
    @FocusedValue(\.macZoomCommands) private var zoomCommands

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(commands?.undoTitle ?? "") {
                commands?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(commands?.canUndo != true)

            Button(commands?.redoTitle ?? "") {
                commands?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(commands?.canRedo != true)
        }

        CommandGroup(replacing: .newItem) {
            Button("groups.create") {
                commands?.newTrip()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(commands == nil)
        }

        CommandGroup(after: .newItem) {
            Button("menu.importReceipts") {
                commands?.importReceipts()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(commands == nil)

            Button("group.export") {
                commands?.exportTrip()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(commands == nil)

            Divider()

            Button("receipt.action.quickLook") {
                commands?.quickLookSelection()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(commands?.canQuickLook != true)

            Button(commands?.archiveTitle ?? String(localized: "receipt.archive")) {
                commands?.archiveOrDeleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(commands?.canActOnSelection != true)

            Button(commands?.archiveTitle ?? String(localized: "receipt.archive")) {
                commands?.archiveOrDeleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(commands?.canActOnSelection != true)
        }

        CommandGroup(after: .pasteboard) {
            Menu("receipt.action.moveToTrip") {
                ForEach(commands?.moveDestinations ?? []) { destination in
                    Button(destination.title, action: destination.move)
                }
            }
            .disabled(commands?.canActOnSelection != true)

            Divider()

            Button("Find") {
                commands?.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(commands == nil)

            Button("Select All") {
                commands?.selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(commands?.canSelectAll != true)
        }

        CommandGroup(replacing: .textFormatting) { }

        CommandGroup(after: .sidebar) {
            Button("menu.showArchived") {
                commands?.showArchived()
            }

            Divider()

            Button("menu.zoomIn") {
                zoomCommands?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(zoomCommands?.canZoomIn != true)

            Button("menu.zoomOut") {
                zoomCommands?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoomCommands?.canZoomOut != true)

            Button("menu.actualSize") {
                zoomCommands?.reset()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoomCommands?.canReset != true)
        }

        CommandGroup(after: .toolbar) {
            Button("trip.rename") {
                commands?.renameSelectedTrip()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(commands?.canRenameTrip != true)
        }

        ImportFromDevicesCommands()
    }
}
#endif
