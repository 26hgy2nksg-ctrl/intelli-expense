import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ShareExtensionPhase: Equatable {
    case ready
    case saving
    case saved
}

@MainActor
final class ShareExtensionModel: ObservableObject {
    @Published private(set) var thumbnails: [UIImage] = []
    @Published private(set) var sharedImageCount = 0
    @Published private(set) var phase: ShareExtensionPhase = .ready
    @Published var errorMessage: String?

    private weak var extensionContext: NSExtensionContext?
    private let providers: [NSItemProvider]
    private let inbox: SharedReceiptInbox?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
        self.providers = Self.imageProviders(from: extensionContext)
        self.sharedImageCount = providers.count
        self.inbox = try? SharedReceiptInbox()
    }

    var canSave: Bool {
        providers.isEmpty == false && phase == .ready
    }

    func loadPreviewThumbnails() async {
        guard thumbnails.isEmpty, providers.isEmpty == false else { return }
        var loadedThumbnails: [UIImage] = []
        for provider in providers.prefix(3) {
            guard let data = try? await loadImageData(from: provider),
                  let image = UIImage(data: data)
            else {
                continue
            }
            loadedThumbnails.append(image)
        }
        thumbnails = loadedThumbnails
    }

    func save() async {
        guard canSave, let inbox else { return completeWithError(ShareExtensionError.unavailable) }

        phase = .saving
        errorMessage = nil
        do {
            var imageData: [Data] = []
            for provider in providers {
                imageData.append(try await loadImageData(from: provider))
            }
            _ = try inbox.write(images: imageData)
            phase = .saved
            openHostApp()
        } catch {
            phase = .ready
            errorMessage = String(localized: "share.error")
        }
    }

    func openHostApp() {
        guard phase == .saved else { return }
        guard let extensionContext else {
            errorMessage = String(localized: "share.open.error")
            return
        }

        extensionContext.open(ShareExtensionHandoffURL.sharedInbox) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.complete()
                } else {
                    self.errorMessage = String(localized: "share.open.error")
                }
            }
        }
    }

    func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    func cancel() {
        completeWithError(ShareExtensionError.cancelled)
    }

    private static func imageProviders(from extensionContext: NSExtensionContext?) -> [NSItemProvider] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        return items.flatMap { item in
            (item.attachments ?? []).filter { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data {
        let typeIdentifier = preferredImageTypeIdentifier(for: provider)
        do {
            return try await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier)
        } catch {
            return try await loadFileRepresentation(from: provider, typeIdentifier: typeIdentifier)
        }
    }

    private func preferredImageTypeIdentifier(for provider: NSItemProvider) -> String {
        provider.registeredContentTypes(conformingTo: .image).first?.identifier ?? UTType.image.identifier
    }

    private func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? ShareExtensionError.noImageData)
                }
            }
        }
    }

    private func loadFileRepresentation(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                do {
                    if let url {
                        continuation.resume(returning: try Data(contentsOf: url))
                    } else {
                        continuation.resume(throwing: error ?? ShareExtensionError.noImageData)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func completeWithError(_ error: Error) {
        extensionContext?.cancelRequest(withError: error as NSError)
    }
}

private enum ShareExtensionError: LocalizedError {
    case cancelled
    case noImageData
    case unavailable
}

private enum ShareExtensionHandoffURL {
    static let sharedInbox = URL(string: "intelliexpense://shared-inbox")!
}
