import Foundation

/// The fixed set of category hues used for folder/category identity.
///
/// Legacy role raw values still decode into the nearest hue so existing snapshots keep rendering,
/// while new snapshots always encode the hue vocabulary.
public enum CategoryColorRole: String, Codable, Sendable, CaseIterable {
    case orange
    case amber
    case brown
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case plum
    case slate
    case gray

    public init(persistedRawValue rawValue: String) {
        switch rawValue {
        case "orange": self = .orange
        case "amber": self = .amber
        case "brown": self = .brown
        case "mint": self = .mint
        case "teal": self = .teal
        case "cyan": self = .cyan
        case "blue": self = .blue
        case "indigo": self = .indigo
        case "purple": self = .purple
        case "plum": self = .plum
        case "slate": self = .slate
        case "gray": self = .gray
        case "food": self = .orange
        case "lodging": self = .indigo
        case "travel": self = .blue
        case "transport": self = .teal
        case "services": self = .purple
        case "goods": self = .brown
        case "tech": self = .cyan
        case "health": self = .mint
        case "generic": self = .gray
        default: self = .gray
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(persistedRawValue: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A category as it appears inside a single folder's ordered visible list.
///
/// A `FolderCategory` is deliberately self-contained: it stores its own symbol and color role so a
/// folder's category snapshot carries all display metadata it needs, even for CloudKit peers running
/// a different catalog version, and even for folder-local custom categories that never appear in the
/// built-in catalog. Built-in categories resolve their display name from `expense.category.<id>`;
/// custom categories carry their user-authored `customName` verbatim.
public struct FolderCategory: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var symbolName: String
    public var colorRoleRawValue: String
    /// User-authored label for folder-local custom categories. `nil` for built-in categories.
    public var customName: String?

    public init(id: String, symbolName: String, colorRole: CategoryColorRole, customName: String? = nil) {
        self.id = id
        self.symbolName = symbolName
        self.colorRoleRawValue = colorRole.rawValue
        self.customName = customName
    }

    public var colorRole: CategoryColorRole {
        CategoryColorRole(persistedRawValue: colorRoleRawValue)
    }

    /// A custom category is one the user authored locally; it is not part of the built-in catalog.
    public var isCustom: Bool {
        customName != nil
    }

    public var isOther: Bool {
        id == CategoryCatalog.otherID
    }

    /// The String Catalog key for a built-in category's display name.
    /// Custom categories are user data and are never localized.
    public var displayNameKey: String? {
        isCustom ? nil : CategoryCatalog.nameKey(for: id)
    }
}

/// An ordered, versioned snapshot of a folder's visible categories.
///
/// The snapshot is copied from the folder's profile at creation time and then owned by the folder
/// (SPEC §D2). It always contains exactly one `Other`, pinned to the end. It is persisted on
/// `ExpenseGroup` as a JSON string, which keeps the SwiftData/CloudKit model simple, versioned, and
/// testable (SPEC §6).
public struct FolderCategorySnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    /// Hard cap on visible categories, including `Other` (SPEC §D4/§D6).
    public static let maximumVisibleCategories = 9

    public var version: Int
    public var categories: [FolderCategory]

    public init(version: Int = FolderCategorySnapshot.currentVersion, categories: [FolderCategory]) {
        self.version = version
        self.categories = FolderCategorySnapshot.normalized(categories)
    }

    /// The ordered category IDs in this snapshot.
    public var categoryIDs: [String] {
        categories.map(\.id)
    }

    public func contains(_ id: String) -> Bool {
        categories.contains { $0.id == id }
    }

    public func category(id: String) -> FolderCategory? {
        categories.first { $0.id == id }
    }

    /// The categories a user may still select; identical to `categories` but excludes `Other` when a
    /// caller wants "at least one non-Other" checks.
    public var nonOtherCategories: [FolderCategory] {
        categories.filter { $0.isOther == false }
    }

    public var hasRoomForMore: Bool {
        categories.count < FolderCategorySnapshot.maximumVisibleCategories
    }

    // MARK: - JSON persistence

    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    public init?(jsonString: String) {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(FolderCategorySnapshot.self, from: data) else {
            return nil
        }
        self = FolderCategorySnapshot(version: decoded.version, categories: decoded.categories)
    }

    // MARK: - Normalization

    /// Enforces the two invariants the whole feature depends on: unique IDs, and exactly one `Other`
    /// pinned to the end. Callers never have to remember to re-pin `Other`.
    public static func normalized(_ categories: [FolderCategory]) -> [FolderCategory] {
        var seen = Set<String>()
        var ordered: [FolderCategory] = []
        var other: FolderCategory?

        for category in categories {
            guard seen.contains(category.id) == false else { continue }
            seen.insert(category.id)
            if category.isOther {
                other = category
            } else {
                ordered.append(category)
            }
        }

        ordered.append(other ?? CategoryCatalog.otherFolderCategory)
        return ordered
    }
}

/// Resolves display metadata for a category ID from the most authoritative source available: the
/// built-in catalog first for known IDs, then the owning folder's self-contained snapshot for custom
/// categories, then a neutral, humanized fallback for orphaned IDs. This lets catalog role/symbol
/// refreshes apply to existing folders without rewriting their snapshots, while custom categories
/// keep their user-authored metadata.
public enum CategoryResolver {
    public static func category(forID id: String, in snapshot: FolderCategorySnapshot?) -> FolderCategory {
        if let builtIn = CategoryCatalog.folderCategory(id: id) {
            return builtIn
        }
        if let match = snapshot?.category(id: id) {
            return match
        }
        return FolderCategory(
            id: id,
            symbolName: CustomCategory.defaultSymbolName,
            colorRole: .gray,
            customName: humanize(id)
        )
    }

    /// Turns an identifier into a readable label ("custom_booth_setup" -> "Booth Setup").
    public static func humanize(_ id: String) -> String {
        var base = id
        if base.hasPrefix(CustomCategory.idPrefix) {
            base = String(base.dropFirst(CustomCategory.idPrefix.count))
        }
        let words = base.split(separator: "_").map { $0.capitalized }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? id : joined
    }
}
