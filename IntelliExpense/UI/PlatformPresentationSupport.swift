import SwiftUI

private struct MacContentZoomFactorKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var macContentZoomFactor: CGFloat {
        get { self[MacContentZoomFactorKey.self] }
        set { self[MacContentZoomFactorKey.self] = newValue }
    }
}

private struct ContentScaledFontModifier: ViewModifier {
    @Environment(\.macContentZoomFactor) private var factor
    var font: Font

    func body(content: Content) -> some View {
        content.font(font.scaled(by: factor))
    }
}

extension View {
    func contentScaledFont(_ font: Font) -> some View {
        modifier(ContentScaledFontModifier(font: font))
    }

    @ViewBuilder
    func macGroupedForm(accessibilityIdentifier: String) -> some View {
        #if os(macOS)
        self
            .formStyle(.grouped)
            .accessibilityIdentifier(accessibilityIdentifier)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macFormPresentation(
        accessibilityIdentifier: String,
        minWidth: CGFloat = 520,
        idealWidth: CGFloat = 560,
        maxWidth: CGFloat = 680,
        minHeight: CGFloat = 480,
        idealHeight: CGFloat = 640,
        maxHeight: CGFloat = 800
    ) -> some View {
        #if os(macOS)
        self
            .presentationSizing(.form)
            .frame(
                minWidth: minWidth,
                idealWidth: idealWidth,
                maxWidth: maxWidth,
                minHeight: minHeight,
                idealHeight: idealHeight,
                maxHeight: maxHeight
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macCatalogPresentation(
        accessibilityIdentifier: String,
        minWidth: CGFloat = 560,
        idealWidth: CGFloat = 640,
        maxWidth: CGFloat = 760,
        minHeight: CGFloat = 440,
        idealHeight: CGFloat = 560,
        maxHeight: CGFloat = 720
    ) -> some View {
        #if os(macOS)
        self
            .presentationSizing(.page)
            .frame(
                minWidth: minWidth,
                idealWidth: idealWidth,
                maxWidth: maxWidth,
                minHeight: minHeight,
                idealHeight: idealHeight,
                maxHeight: maxHeight
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macDefaultAction() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.defaultAction)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macCancelAction() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }
}
