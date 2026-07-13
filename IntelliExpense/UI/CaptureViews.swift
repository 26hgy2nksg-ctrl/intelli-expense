#if os(iOS)
import SwiftUI
import TipKit

enum AddReceiptAction {
    case scan
    case photo
    case file
    case manual
}

struct CaptureOptionsTip: Tip {
    static let scanReceiptSaved = Tips.Event(id: "capture.scan.saved")

    var title: Text {
        Text("tip.captureOptions.title")
    }

    var message: Text? {
        Text("tip.captureOptions.message")
    }

    var image: Image? {
        Image(systemName: "ellipsis.circle")
    }

    var rules: [Rule] {
        #Rule(Self.scanReceiptSaved) { event in
            event.donations.count > 0
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

struct AddReceiptSheet: View {
    var destinationName: String
    var onSelect: (AddReceiptAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                scanButton
                VStack(spacing: 10) {
                    AddReceiptSheetRow(
                        systemImage: "photo.on.rectangle",
                        titleKey: "capture.photo",
                        captionKey: "capture.photo.caption",
                        identifier: "capture.sheet.photo"
                    ) {
                        onSelect(.photo)
                    }
                    AddReceiptSheetRow(
                        systemImage: "doc",
                        titleKey: "capture.file",
                        captionKey: "capture.file.caption",
                        identifier: "capture.sheet.file"
                    ) {
                        onSelect(.file)
                    }
                    AddReceiptSheetRow(
                        systemImage: "square.and.pencil",
                        titleKey: "capture.manual",
                        captionKey: "capture.manual.caption",
                        identifier: "capture.sheet.manual"
                    ) {
                        onSelect(.manual)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("capture.sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("capture.add.title")
                .contentScaledFont(.title2.weight(.bold))
            Text(destinationText)
                .contentScaledFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("capture.sheet.destination")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanButton: some View {
        Button {
            onSelect(.scan)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .contentScaledFont(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color("LedgerGreen"), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("capture.scan")
                        .contentScaledFont(.headline)
                        .foregroundStyle(.primary)
                    Text("capture.scan.caption")
                        .contentScaledFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .contentScaledFont(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("LedgerGreenSoft"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color("LedgerGreen").opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture.sheet.scan")
    }

    private var destinationText: String {
        String.localizedStringWithFormat(String(localized: "capture.sheet.destination"), destinationName)
    }
}

private struct AddReceiptSheetRow: View {
    var systemImage: String
    var titleKey: LocalizedStringKey
    var captionKey: LocalizedStringKey
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .contentScaledFont(.body.weight(.semibold))
                    .foregroundStyle(Color("LedgerGreen"))
                    .frame(width: 34, height: 34)
                    .background(Color("LedgerGreenSoft"), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleKey)
                        .contentScaledFont(.headline)
                        .foregroundStyle(.primary)
                    Text(captionKey)
                        .contentScaledFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .contentScaledFont(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
#endif
