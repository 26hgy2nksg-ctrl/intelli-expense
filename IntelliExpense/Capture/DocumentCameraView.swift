#if os(iOS)
@preconcurrency import SwiftUI
import UIKit
@preconcurrency import VisionKit

@MainActor
struct DocumentCameraSupport {
    var isSupported: @MainActor @Sendable () -> Bool

    static let live = DocumentCameraSupport {
        VNDocumentCameraViewController.isSupported
    }

    var canScanDocuments: Bool {
        isSupported()
    }
}

struct DocumentCameraView: UIViewControllerRepresentable {
    var onScanImages: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScanImages: onScanImages,
            onCancel: onCancel,
            onError: onError
        )
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        _ = uiViewController
        _ = context
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let onScanImages: ([UIImage]) -> Void
        private let onCancel: () -> Void
        private let onError: (Error) -> Void

        init(
            onScanImages: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.onScanImages = onScanImages
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { pageIndex in
                scan.imageOfPage(at: pageIndex)
            }
            controller.dismiss(animated: true) {
                self.onScanImages(images)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) {
                self.onCancel()
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true) {
                self.onError(error)
            }
        }
    }
}
#endif
