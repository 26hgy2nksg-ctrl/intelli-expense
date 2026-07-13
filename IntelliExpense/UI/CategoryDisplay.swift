import ExpenseCore
import SwiftUI

// MARK: - Display metadata

extension CategoryColorRole {
    /// Maps a category hue onto one named asset-catalog token pair.
    var assetColorName: String {
        switch self {
        case .orange: "CategoryOrange"
        case .amber: "CategoryAmber"
        case .brown: "CategoryBrown"
        case .mint: "CategoryMint"
        case .teal: "CategoryTeal"
        case .cyan: "CategoryCyan"
        case .blue: "CategoryBlue"
        case .indigo: "CategoryIndigo"
        case .purple: "CategoryPurple"
        case .plum: "CategoryPlum"
        case .slate: "CategorySlate"
        case .gray: "CategoryGray"
        }
    }
}

extension FolderCategory {
    /// Localized display name for built-ins; verbatim user text for custom categories (SPEC §9).
    var displayName: String {
        if let customName {
            return customName
        }
        if let key = displayNameKey {
            return String(localized: String.LocalizationValue(key))
        }
        return CategoryResolver.humanize(id)
    }

    var color: Color {
        Color(colorRole.assetColorName)
    }
}

extension FolderProfile {
    var displayName: String {
        String(localized: String.LocalizationValue(nameKey))
    }
}

extension FolderProfileIdentity {
    var color: Color {
        if let colorRole {
            Color(colorRole.assetColorName)
        } else {
            Color("LedgerGreen")
        }
    }

    var backgroundColor: Color {
        if let colorRole {
            Color(colorRole.assetColorName).opacity(0.14)
        } else {
            Color("LedgerGreenSoft")
        }
    }
}

/// Bridges receipts to the ordered set of categories they actually use, honoring the owning folder's
/// visible order and appending used-but-hidden categories afterward (SPEC §D7). Used by breakdowns,
/// glyph rows, featured chips, and filter menus so no surface shows empty categories.
enum CategoryUsage {
    static func orderedCategoryIDs(for receipts: [Receipt], in group: ExpenseGroup?) -> [String] {
        let visibleOrder = group?.visibleCategoryIDs ?? []
        let usedIDs = Set(receipts.map(\.categoryID))
        return CategoryOrdering.usedCategoryIDs(visibleOrder: visibleOrder, usedIDs: usedIDs)
    }

    static func orderedCategories(for receipts: [Receipt], in group: ExpenseGroup?) -> [FolderCategory] {
        let snapshot = group?.categorySnapshot
        return orderedCategoryIDs(for: receipts, in: group)
            .map { CategoryResolver.category(forID: $0, in: snapshot) }
    }

    /// The categories offered in a folder's filter menu: visible categories first, then any
    /// used-but-hidden ones (SPEC §D7).
    static func filterCategories(for group: ExpenseGroup) -> [FolderCategory] {
        let snapshot = group.categorySnapshot
        let usedIDs = Set(group.activeReceipts.map(\.categoryID))
        let orderedIDs = CategoryOrdering.usedCategoryIDs(
            visibleOrder: group.visibleCategoryIDs,
            usedIDs: usedIDs.union(group.visibleCategoryIDs)
        )
        return orderedIDs.map { CategoryResolver.category(forID: $0, in: snapshot) }
    }
}

// MARK: - Reusable glyph tile

/// A category's symbol rendered in its role-colored rounded square. Used across the selector,
/// breakdown rows, featured chips, and receipt rows so every surface reads as one system.
struct CategoryGlyph: View {
    var category: FolderCategory
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        Image(systemName: category.symbolName)
            .imageScale(.small)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A profile identity symbol rendered in the same soft rounded tile wherever folders appear.
struct FolderProfileGlyph: View {
    var identity: FolderProfileIdentity
    var size: CGFloat
    var cornerRadius: CGFloat = 8
    var imageScale: Image.Scale = .medium

    init(
        identity: FolderProfileIdentity,
        size: CGFloat,
        cornerRadius: CGFloat = 8,
        imageScale: Image.Scale = .medium
    ) {
        self.identity = identity
        self.size = size
        self.cornerRadius = cornerRadius
        self.imageScale = imageScale
    }

    init(
        profileID: String,
        size: CGFloat,
        cornerRadius: CGFloat = 8,
        imageScale: Image.Scale = .medium
    ) {
        self.init(
            identity: FolderProfileCatalog.identity(forProfileID: profileID),
            size: size,
            cornerRadius: cornerRadius,
            imageScale: imageScale
        )
    }

    var body: some View {
        Image(systemName: identity.symbolName)
            .imageScale(imageScale)
            .foregroundStyle(identity.color)
            .frame(width: size, height: size)
            .background(identity.backgroundColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Profile-scoped category selector (SPEC §D6)

/// The single-choice category selector shown in Review and Receipt Detail. It renders only the
/// folder's visible categories, adapting from equal tiles (≤5) to a two-row grid (6–8) to a vertical
/// list at accessibility sizes, and surfaces an out-of-set "Current" chip that marks the field for
/// attention until the user picks a visible category.
struct CategorySelector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var categories: [FolderCategory]
    @Binding var selection: String?
    /// The receipt's current category when it is not part of `categories` (e.g. after moving folders).
    var currentOutOfSet: FolderCategory?
    @ScaledMetric(relativeTo: .caption) private var iconTileSize = 28
    @State private var selectionFeedbackTrigger = 0

    private var tiles: [SelectorTile] {
        var result: [SelectorTile] = []
        if let currentOutOfSet {
            result.append(SelectorTile(category: currentOutOfSet, needsAttention: true))
        }
        result.append(contentsOf: categories.map { SelectorTile(category: $0, needsAttention: false) })
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("receipt.field.type")
                .contentScaledFont(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(tiles) { tile in
                    tileButton(tile, layout: .row)
                }
            }
        } else if tiles.count <= 5 {
            HStack(spacing: 6) {
                ForEach(tiles) { tile in
                    tileButton(tile, layout: .tile)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                ForEach(tiles) { tile in
                    tileButton(tile, layout: .tile)
                }
            }
        }
    }

    private enum TileLayout { case tile, row }

    @ViewBuilder
    private func tileButton(_ tile: SelectorTile, layout: TileLayout) -> some View {
        let category = tile.category
        let isSelected = selection == category.id
        Button {
            selection = category.id
            selectionFeedbackTrigger += 1
        } label: {
            Group {
                switch layout {
                case .tile:
                    VStack(spacing: 4) {
                        CategoryGlyph(category: category, size: iconTileSize)
                        Text(category.displayName)
                            .contentScaledFont(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                case .row:
                    HStack(spacing: 12) {
                        CategoryGlyph(category: category, size: iconTileSize)
                        Text(category.displayName)
                            .contentScaledFont(.body.weight(.medium))
                        Spacer(minLength: 8)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color("LedgerGreen"))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .background(tileBackground(category: category, isSelected: isSelected, attention: tile.needsAttention))
            .overlay(tileRing(category: category, isSelected: isSelected, attention: tile.needsAttention))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tile.needsAttention ? currentAccessibilityLabel(category) : category.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("review.category.\(category.id)")
    }

    private func tileBackground(category: FolderCategory, isSelected: Bool, attention: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? category.color.opacity(0.14) : Color.secondary.opacity(0.08))
    }

    @ViewBuilder
    private func tileRing(category: FolderCategory, isSelected: Bool, attention: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .inset(by: 2)
                .stroke(attention ? Color("AttentionFieldEdge") : category.color, lineWidth: 1.5)
        } else if attention {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .inset(by: 2)
                .stroke(Color("AttentionFieldEdge"), lineWidth: 1.5)
        }
    }

    private func currentAccessibilityLabel(_ category: FolderCategory) -> String {
        String.localizedStringWithFormat(String(localized: "review.category.current"), category.displayName)
    }

    private struct SelectorTile: Identifiable {
        var category: FolderCategory
        var needsAttention: Bool
        var id: String { category.id }
    }
}
