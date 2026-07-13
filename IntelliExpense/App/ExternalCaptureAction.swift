#if os(iOS)
import Foundation

/// The in-app capture flow an external `capture` request resolves to. Kept as a pure,
/// value-typed mapping (no view state) so the widget/deep-link → flow selection is
/// unit-testable without instantiating WidgetKit or the tab view — mirroring the
/// scan-only assertion in `ScanReceiptIntentTests`.
enum ExternalCaptureAction: Equatable {
    /// Routes through `startAccessoryCapture(sourceType:)` — scanner or photo picker.
    case accessoryCapture(ReceiptAttachmentSourceType)
    /// Routes through `startAccessoryFileImport()` — the image/PDF file importer.
    case fileImport
    /// Routes through `startAccessoryManualEntry()` — the manual review form.
    case manualEntry
}

extension CaptureKind {
    /// The existing in-app flow this kind opens. `CaptureKind` maps 1:1 onto
    /// `ReceiptAttachmentSourceType` for scan/photo/file; `manual` has no attachment
    /// source and opens the manual-entry form the pipeline enum deliberately omits.
    var externalCaptureAction: ExternalCaptureAction {
        switch self {
        case .scan:
            .accessoryCapture(.cameraScan)
        case .photo:
            .accessoryCapture(.photoImport)
        case .file:
            .fileImport
        case .manual:
            .manualEntry
        }
    }
}
#endif
