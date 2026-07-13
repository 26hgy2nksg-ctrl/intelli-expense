import SwiftUI
#if os(iOS)
import UIKit

struct ReceiptImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    private let pages: [Data]

    @State private var selectedPage: Int
    @State private var isChromeVisible = true
    @State private var resetToken = UUID()

    init(pages: [Data], initialPage: Int) {
        self.pages = pages
        let lastIndex = max(pages.count - 1, 0)
        _selectedPage = State(initialValue: min(max(initialPage, 0), lastIndex))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if pages.isEmpty {
                Color.black
            } else {
                TabView(selection: $selectedPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        if shouldLoadPage(index) {
                            ZoomableReceiptPage(
                                imageData: pages[index],
                                resetToken: resetToken,
                                onSingleTap: toggleChrome
                            )
                            .accessibilityLabel(Text("receipt.image.accessibility"))
                            .tag(index)
                        } else {
                            Color.black.tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if isChromeVisible {
                HStack(alignment: .center) {
                    if pages.count > 1 {
                        Text(pageIndicatorText)
                            .contentScaledFont(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    Button("common.done") {
                        dismiss()
                    }
                    .contentScaledFont(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("receipt.image.viewer.done")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt.image.viewer")
        .onChange(of: selectedPage) { _, _ in
            resetToken = UUID()
            UIAccessibility.post(notification: .announcement, argument: pageIndicatorText)
        }
    }

    private var pageIndicatorText: String {
        String.localizedStringWithFormat(
            String(localized: "viewer.page.indicator"),
            selectedPage + 1,
            pages.count
        )
    }

    private func shouldLoadPage(_ index: Int) -> Bool {
        abs(index - selectedPage) <= 1
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible.toggle()
        }
    }
}
private struct ZoomableReceiptPage: UIViewRepresentable {
    var imageData: Data
    var resetToken: UUID
    var onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> ReceiptZoomScrollView {
        let scrollView = ReceiptZoomScrollView()
        scrollView.delegate = context.coordinator
        context.coordinator.scrollView = scrollView

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: ReceiptZoomScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if context.coordinator.imageData != imageData {
            context.coordinator.imageData = imageData
            uiView.setImage(UIImage(data: imageData))
        }
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            uiView.resetZoom()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: ReceiptZoomScrollView?
        var imageData: Data?
        var resetToken: UUID?
        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ReceiptZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ReceiptZoomScrollView)?.centerImage()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            (scrollView as? ReceiptZoomScrollView)?.centerImage()
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            let point = recognizer.location(in: scrollView.imageView)
            scrollView.toggleZoom(around: point)
        }
    }
}

private final class ReceiptZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    private var imageSize: CGSize = .zero
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
        imageSize = image?.size ?? .zero
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        contentSize = imageSize
        lastBoundsSize = .zero
        setNeedsLayout()
        layoutIfNeeded()
        resetZoom()
    }

    func resetZoom() {
        updateZoomScales(reset: true)
        centerImage()
    }

    func toggleZoom(around point: CGPoint) {
        guard imageSize != .zero else { return }
        if zoomScale > minimumZoomScale * 1.1 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let targetScale = min(maximumZoomScale, max(3, minimumZoomScale * 3))
            let rectSize = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
            let rectOrigin = CGPoint(x: point.x - rectSize.width / 2, y: point.y - rectSize.height / 2)
            zoom(to: CGRect(origin: rectOrigin, size: rectSize), animated: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            updateZoomScales(reset: zoomScale <= minimumZoomScale)
        }
        centerImage()
    }

    func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func updateZoomScales(reset: Bool) {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            minimumZoomScale = 1
            maximumZoomScale = 6
            zoomScale = 1
            return
        }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        minimumZoomScale = fitScale
        maximumZoomScale = max(6, fitScale * 6, fitScale + 0.01)
        if reset || zoomScale < fitScale {
            zoomScale = fitScale
        }
    }
}
#elseif os(macOS)

struct ReceiptImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    private let pages: [Data]
    @State private var selectedPage: Int
    @State private var magnification: CGFloat = 1

    init(pages: [Data], initialPage: Int) {
        self.pages = pages
        let lastIndex = max(pages.count - 1, 0)
        _selectedPage = State(initialValue: min(max(initialPage, 0), lastIndex))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if pages.count > 1 {
                    Picker("viewer.page.picker", selection: $selectedPage) {
                        ForEach(pages.indices, id: \.self) { index in
                            Text(String.localizedStringWithFormat(String(localized: "viewer.page.indicator"), index + 1, pages.count))
                                .tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Spacer()
                Button("common.done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView([.horizontal, .vertical]) {
                if let image = currentImage {
                    Image(receiptImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(magnification)
                        .frame(minWidth: 520, minHeight: 420)
                        .padding(24)
                        .accessibilityIdentifier("receipt.image.viewer.magnification")
                } else {
                    ContentUnavailableView("receipt.detail.noOCR", systemImage: "photo")
                        .frame(minWidth: 520, minHeight: 420)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .focusedSceneValue(
            \.macZoomCommands,
            MacZoomCommands(
                zoomIn: zoomIn,
                zoomOut: zoomOut,
                reset: resetZoom,
                canZoomIn: magnification < 6,
                canZoomOut: magnification > 1,
                canReset: magnification != 1
            )
        )
        .onChange(of: selectedPage) { _, _ in resetZoom() }
    }

    private var currentImage: ReceiptPlatformImage? {
        guard pages.indices.contains(selectedPage) else { return nil }
        return ReceiptPlatformImage.receiptImage(data: pages[selectedPage])
    }

    private func zoomIn() {
        magnification = min(6, magnification + 0.5)
    }

    private func zoomOut() {
        magnification = max(1, magnification - 0.5)
    }

    private func resetZoom() {
        magnification = 1
    }
}
#endif
