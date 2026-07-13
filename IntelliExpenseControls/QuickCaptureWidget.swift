import Foundation
import SwiftUI
import WidgetKit

// MARK: - Widget

/// Home Screen action launcher: the four capture doorways — Scan · Photo · File · Manual —
/// each a `Link` into the existing `intelliexpense://capture?kind=…` route (SPEC-quick-capture-widget).
/// It shows no app data (a launcher, not a dashboard), so it is a `StaticConfiguration` with a
/// single `.never` entry — no App Group, no SwiftData, no CloudKit read.
struct QuickCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: QuickCaptureProvider()) { _ in
            QuickCaptureWidgetView()
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName(
            LocalizedStringResource(
                "widget.quickCapture.displayName",
                defaultValue: "Quick Capture",
                table: "AppShortcuts"
            )
        )
        .description(
            LocalizedStringResource(
                "widget.quickCapture.description",
                defaultValue: "Scan, choose a photo, import a file, or enter a receipt by hand.",
                table: "AppShortcuts"
            )
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private static var kind: String {
        #if INTELLI_EXPENSE_SANDBOX
        return "com.nags.intelliexpense.sandbox.widgets.quickCapture"
        #else
        return "com.nags.intelliexpense.widgets.quickCapture"
        #endif
    }
}

// MARK: - Timeline

struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        // The launcher never changes, so it never needs refreshing.
        completion(Timeline(entries: [QuickCaptureEntry(date: Date())], policy: .never))
    }
}

// MARK: - Layout

private enum WidgetPalette {
    static let brand = Color("LedgerGreen")
    static let heroPanel = Color(uiColor: .secondarySystemFill)
    static let photo = Color("CapturePhoto")
    static let photoSoft = Color("CapturePhotoSoft")
    static let file = Color("CaptureFile")
    static let fileSoft = Color("CaptureFileSoft")
    static let manual = Color("CaptureManual")
    static let manualSoft = Color("CaptureManualSoft")
    static let tileRadius: CGFloat = 12
    static let panelRadius: CGFloat = 16
}

private struct QuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                grid
            default:
                heroRow
            }
        }
        .widgetURL(AppDeepLinkRouter.captureURL(kind: .scan))
    }

    /// Medium — Scan is the neutral hero panel with the single saturated Ledger Green chip;
    /// Photo/File/Manual are a quiet action-hue overflow list beside it: the capture launcher
    /// hierarchy, rebuilt at widget scale.
    private var heroRow: some View {
        HStack(spacing: 12) {
            HeroScanTile(action: .scan)
            VStack(spacing: 8) {
                ForEach(QuickCaptureAction.secondary) { action in
                    OverflowRow(action: action)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Small — the same four as a 2×2 grid, Scan anchoring the top-leading cell.
    private var grid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                GridTile(action: .scan, showsLabel: showsSmallLabels)
                GridTile(action: .photo, showsLabel: showsSmallLabels)
            }
            HStack(spacing: 8) {
                GridTile(action: .file, showsLabel: showsSmallLabels)
                GridTile(action: .manual, showsLabel: showsSmallLabels)
            }
        }
    }

    /// At the largest Dynamic Type sizes the small grid drops labels to glyph-only so the
    /// four tiles keep their tap targets; VoiceOver still speaks the full label per tile.
    private var showsSmallLabels: Bool {
        sizeCategory.isAccessibilityCategory == false
    }
}

/// The medium hero: a neutral semantic panel holding a small saturated brand camera chip
/// + the "Scan" label. The one saturated hit is the small chip, so the brand stays rationed
/// and the panel never becomes a green slab.
private struct HeroScanTile: View {
    let action: QuickCaptureAction
    @ScaledMetric(relativeTo: .title2) private var chipSize: CGFloat = 46

    var body: some View {
        Link(destination: action.url) {
            VStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: chipSize, height: chipSize)
                    .background(WidgetPalette.brand, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(action.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WidgetPalette.heroPanel, in: RoundedRectangle(cornerRadius: WidgetPalette.panelRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(action.accessibilityLabel))
    }
}

/// A secondary action in the medium overflow list: an action-tinted glyph tile + label.
private struct OverflowRow: View {
    let action: QuickCaptureAction
    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 34

    var body: some View {
        Link(destination: action.url) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(action.accentColor)
                    .frame(width: tileSize, height: tileSize)
                    .background(action.softColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(action.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(action.accessibilityLabel))
    }
}

/// A small-family cell: Scan is the filled brand tile, the rest are soft action-tint tiles.
private struct GridTile: View {
    let action: QuickCaptureAction
    var showsLabel: Bool
    @ScaledMetric(relativeTo: .title3) private var tileSize: CGFloat = 40

    var body: some View {
        Link(destination: action.url) {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.title3)
                    .foregroundStyle(action.isPrimary ? Color.white : action.accentColor)
                    .frame(width: tileSize, height: tileSize)
                    .background(
                        action.isPrimary ? WidgetPalette.brand : action.softColor,
                        in: RoundedRectangle(cornerRadius: WidgetPalette.tileRadius, style: .continuous)
                    )
                    .accessibilityHidden(true)
                if showsLabel {
                    Text(action.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(action.accessibilityLabel))
    }
}

// MARK: - Actions

/// One capture doorway. Ledger Green stays reserved for `.scan`; secondary colors are
/// widget-scoped action hues, not category semantics.
private struct QuickCaptureAction: Identifiable {
    let kind: CaptureKind
    let systemImage: String
    let label: LocalizedStringResource
    let accessibilityLabel: LocalizedStringResource

    var id: String { kind.rawValue }
    var isPrimary: Bool { kind == .scan }
    var url: URL { AppDeepLinkRouter.captureURL(kind: kind) }
    var accentColor: Color {
        switch kind {
        case .scan:
            WidgetPalette.brand
        case .photo:
            WidgetPalette.photo
        case .file:
            WidgetPalette.file
        case .manual:
            WidgetPalette.manual
        }
    }
    var softColor: Color {
        switch kind {
        case .scan:
            WidgetPalette.heroPanel
        case .photo:
            WidgetPalette.photoSoft
        case .file:
            WidgetPalette.fileSoft
        case .manual:
            WidgetPalette.manualSoft
        }
    }

    static let scan = QuickCaptureAction(
        kind: .scan,
        systemImage: "camera.viewfinder",
        label: LocalizedStringResource("widget.capture.scan", defaultValue: "Scan", table: "AppShortcuts"),
        accessibilityLabel: LocalizedStringResource("widget.capture.scan.a11y", defaultValue: "Scan a receipt", table: "AppShortcuts")
    )
    static let photo = QuickCaptureAction(
        kind: .photo,
        systemImage: "photo",
        label: LocalizedStringResource("widget.capture.photo", defaultValue: "Photo", table: "AppShortcuts"),
        accessibilityLabel: LocalizedStringResource("widget.capture.photo.a11y", defaultValue: "Choose photo", table: "AppShortcuts")
    )
    static let file = QuickCaptureAction(
        kind: .file,
        systemImage: "doc",
        label: LocalizedStringResource("widget.capture.file", defaultValue: "File", table: "AppShortcuts"),
        accessibilityLabel: LocalizedStringResource("widget.capture.file.a11y", defaultValue: "Import file", table: "AppShortcuts")
    )
    static let manual = QuickCaptureAction(
        kind: .manual,
        systemImage: "square.and.pencil",
        label: LocalizedStringResource("widget.capture.manual", defaultValue: "Manual", table: "AppShortcuts"),
        accessibilityLabel: LocalizedStringResource("widget.capture.manual.a11y", defaultValue: "Enter manually", table: "AppShortcuts")
    )

    /// Every action, Scan first — used by the small 2×2 grid.
    static let all: [QuickCaptureAction] = [.scan, .photo, .file, .manual]
    /// The overflow actions (everything but the hero Scan) — used by the medium list.
    static let secondary: [QuickCaptureAction] = [.photo, .file, .manual]
}
