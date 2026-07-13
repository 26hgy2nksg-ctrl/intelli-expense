import SwiftUI
import UIKit

struct ShareExtensionView: View {
    @ObservedObject var model: ShareExtensionModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 12)
                thumbnailStrip
                VStack(spacing: 8) {
                    Text("share.title")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(bodyKey)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 12)
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.loadPreviewThumbnails()
        }
    }

    private var bodyKey: LocalizedStringKey {
        switch model.phase {
        case .ready, .saving:
            "share.body"
        case .saved:
            "share.saved.body"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .ready:
                Button("share.cancel", role: .cancel) {
                    model.cancel()
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await model.save() }
                } label: {
                    Text("share.confirm")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("LedgerGreen"))
                .disabled(model.canSave == false)
            case .saving:
                ProgressView("share.saving")
                    .controlSize(.large)
            case .saved:
                Button("share.done") {
                    model.complete()
                }
                .buttonStyle(.bordered)

                Button("share.open") {
                    model.openHostApp()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("LedgerGreen"))
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var thumbnailStrip: some View {
        if model.thumbnails.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(Color("LedgerGreen"))
                Text(String.localizedStringWithFormat(String(localized: "share.count"), model.sharedImageCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        } else {
            HStack(spacing: 8) {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 96)
                        .clipShape(.rect(cornerRadius: 8))
                }
                if model.sharedImageCount > model.thumbnails.count {
                    Text("+\(model.sharedImageCount - model.thumbnails.count)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 96)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
