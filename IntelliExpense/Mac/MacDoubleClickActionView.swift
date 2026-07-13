#if os(macOS)
import AppKit
import SwiftUI

/// Adds a double-click action without holding the primary mouse event that
/// drives native `List` selection.
struct MacDoubleClickActionView: NSViewRepresentable {
    var action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> GestureAnchorView {
        let anchorView = GestureAnchorView()
        anchorView.recognizer = Self.makeRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        return anchorView
    }

    func updateNSView(_ nsView: GestureAnchorView, context: Context) {
        context.coordinator.action = action
        nsView.installRecognizerIfPossible()
    }

    static func makeRecognizer(
        target: AnyObject? = nil,
        action: Selector? = nil
    ) -> NSClickGestureRecognizer {
        let recognizer = NSClickGestureRecognizer(target: target, action: action)
        recognizer.numberOfClicksRequired = 2
        recognizer.delaysPrimaryMouseButtonEvents = false
        return recognizer
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            action()
        }
    }

    @MainActor
    final class GestureAnchorView: NSView {
        var recognizer: NSClickGestureRecognizer?
        private weak var recognizerHost: NSView?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            detachRecognizer()
            Task { @MainActor [weak self] in
                self?.installRecognizerIfPossible()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installRecognizerIfPossible()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func installRecognizerIfPossible() {
            guard let recognizer,
                  let host = nearestRowHost,
                  recognizerHost !== host
            else { return }

            detachRecognizer()
            host.addGestureRecognizer(recognizer)
            recognizerHost = host
        }

        private var nearestRowHost: NSView? {
            var candidate = superview
            while let view = candidate {
                if view is NSTableCellView || view is NSTableRowView {
                    return view
                }
                candidate = view.superview
            }
            return superview
        }

        private func detachRecognizer() {
            guard let recognizer, let recognizerHost else { return }
            recognizerHost.removeGestureRecognizer(recognizer)
            self.recognizerHost = nil
        }
    }
}
#endif
