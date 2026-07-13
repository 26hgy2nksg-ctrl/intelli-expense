import SwiftUI

#if os(iOS)
import UIKit

typealias ReceiptPlatformImage = UIImage

extension Image {
    init(receiptImage image: ReceiptPlatformImage) {
        self.init(uiImage: image)
    }
}

extension ReceiptPlatformImage {
    func receiptJPEGData(compressionQuality: CGFloat) -> Data? {
        jpegData(compressionQuality: compressionQuality)
    }

    func resizedToFit(maxDimension: CGFloat) -> ReceiptPlatformImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else {
            return self
        }

        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
#elseif os(macOS)
import AppKit

typealias ReceiptPlatformImage = NSImage

extension Image {
    init(receiptImage image: ReceiptPlatformImage) {
        self.init(nsImage: image)
    }
}

extension ReceiptPlatformImage {
    func receiptJPEGData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }

    func resizedToFit(maxDimension: CGFloat) -> ReceiptPlatformImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else {
            return self
        }

        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: targetSize).fill()
        draw(in: CGRect(origin: .zero, size: targetSize))
        image.unlockFocus()
        return image
    }
}
#endif

extension ReceiptPlatformImage {
    static func receiptImage(data: Data) -> ReceiptPlatformImage? {
        ReceiptPlatformImage(data: data)
    }
}

extension View {
    @ViewBuilder
    func receiptDecimalInputKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func receiptCharactersInputBehavior() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }

    @ViewBuilder
    func receiptInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func receiptPageTabViewStyle() -> some View {
        #if os(iOS)
        tabViewStyle(.page)
        #else
        self
        #endif
    }
}

extension Color {
    static var receiptSeparator: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #elseif os(macOS)
        Color(nsColor: .separatorColor)
        #endif
    }

    static var receiptQuaternaryFill: Color {
        #if os(iOS)
        Color(uiColor: .quaternarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .quaternaryLabelColor).opacity(0.12)
        #endif
    }
}
