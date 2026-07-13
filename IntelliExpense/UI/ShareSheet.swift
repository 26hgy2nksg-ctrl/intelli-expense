import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ExportShareItem: Identifiable {
    let id = UUID()
    var url: URL
}

#if os(iOS)
struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        _ = context
        return UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        _ = uiViewController
        _ = context
    }
}
#elseif os(macOS)
struct MacExportReadyView: View {
    var item: ExportShareItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(item.url.lastPathComponent, systemImage: "doc.zipper")
                .contentScaledFont(.headline)
            ShareLink(item: item.url) {
                Label("export.button", systemImage: "square.and.arrow.up")
            }
            .draggable(MacReceiptTransferItem(receiptKey: "export", url: item.url))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("export.showInFinder", systemImage: "folder")
            }
            .accessibilityIdentifier("mac.export.showInFinder")
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
#endif
