import Foundation

/// A built-in category definition: a stable ASCII identifier plus the display metadata used to render
/// it. Display names live in the String Catalog under `expense.category.<id>` (SPEC §D3).
public struct BuiltInCategory: Equatable, Sendable {
    public var id: String
    public var symbolName: String
    public var colorRole: CategoryColorRole
    /// A documented, always-available fallback symbol for OS versions where `symbolName` is missing
    /// (SPEC §D9). `tag.fill` is the universal generic fallback.
    public var fallbackSymbolName: String

    public init(
        id: String,
        symbolName: String,
        colorRole: CategoryColorRole,
        fallbackSymbolName: String = "tag.fill"
    ) {
        self.id = id
        self.symbolName = symbolName
        self.colorRole = colorRole
        self.fallbackSymbolName = fallbackSymbolName
    }

    /// A folder-snapshot entry built from this catalog definition.
    public var folderCategory: FolderCategory {
        FolderCategory(id: id, symbolName: symbolName, colorRole: colorRole)
    }
}

/// The single source of truth for built-in categories and legacy compatibility (SPEC §D3, §D8, §D9).
///
/// This catalog is intentionally receipt-first: familiar object symbols over abstract accounting
/// icons, a distinct folder-visible hue palette, and a small number of stable IDs. Where the same display word
/// means different things across profiles (e.g. Conference "Materials" vs Home Project "Materials",
/// Conference "Registration" vs Vehicle "Registration"), the catalog uses distinct IDs so every ID
/// keeps exactly one symbol and color.
public enum CategoryCatalog {
    public static let otherID = "other"
    public static let nameKeyPrefix = "expense.category."

    /// The five raw values that predate profiles. They stay canonical and unmigrated (SPEC §D3).
    public static let legacyExpenseTypeIDs: [String] = ["food", "hotel", "flight", "taxi", "other"]

    public static func nameKey(for id: String) -> String {
        nameKeyPrefix + id
    }

    public static var otherFolderCategory: FolderCategory {
        (category(id: otherID) ?? BuiltInCategory(id: otherID, symbolName: "tag.fill", colorRole: .gray)).folderCategory
    }

    public static func category(id: String) -> BuiltInCategory? {
        byID[id]
    }

    public static func isBuiltIn(_ id: String) -> Bool {
        byID[id] != nil
    }

    public static func folderCategory(id: String) -> FolderCategory? {
        category(id: id)?.folderCategory
    }

    /// Ordered folder categories for a list of IDs, silently dropping unknown IDs.
    public static func folderCategories(ids: [String]) -> [FolderCategory] {
        ids.compactMap { folderCategory(id: $0) }
    }

    /// Validates a category identifier for storage and CSV export: lowercase ASCII letters, digits,
    /// and underscores only (SPEC §D11, §10). All built-in and generated custom IDs satisfy this.
    public static func isValidIdentifier(_ id: String) -> Bool {
        guard id.isEmpty == false else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") || scalar == "_"
        }
    }

    private static let byID: [String: BuiltInCategory] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// Every built-in category. Order is not significant; profiles define visible ordering.
    public static let all: [BuiltInCategory] = [
        // Current / Work Trip
        BuiltInCategory(id: "food", symbolName: "fork.knife", colorRole: .orange),
        BuiltInCategory(id: "hotel", symbolName: "bed.double.fill", colorRole: .indigo),
        BuiltInCategory(id: "flight", symbolName: "airplane", colorRole: .blue),
        BuiltInCategory(id: "taxi", symbolName: "car.fill", colorRole: .teal),
        BuiltInCategory(id: "other", symbolName: "tag.fill", colorRole: .gray),
        BuiltInCategory(id: "parking_tolls", symbolName: "parkingsign.circle.fill", colorRole: .cyan),
        BuiltInCategory(id: "laundry", symbolName: "washer.fill", colorRole: .mint),
        BuiltInCategory(id: "baggage", symbolName: "suitcase.rolling.fill", colorRole: .brown),
        BuiltInCategory(id: "business_calls", symbolName: "phone.fill", colorRole: .purple),

        // Conference
        BuiltInCategory(id: "registration", symbolName: "ticket.fill", colorRole: .purple),
        BuiltInCategory(id: "materials", symbolName: "doc.text.fill", colorRole: .brown, fallbackSymbolName: "doc.text.fill"),
        BuiltInCategory(id: "booth_display", symbolName: "rectangle.3.group.fill", colorRole: .amber),
        BuiltInCategory(id: "shipping", symbolName: "shippingbox.fill", colorRole: .mint),
        BuiltInCategory(id: "wifi_tech", symbolName: "wifi", colorRole: .cyan),
        BuiltInCategory(id: "printing", symbolName: "printer.fill", colorRole: .slate),
        BuiltInCategory(id: "professional_development", symbolName: "graduationcap.fill", colorRole: .plum),

        // Client Visit / Day Trip
        BuiltInCategory(id: "fuel", symbolName: "fuelpump.fill", colorRole: .amber),
        BuiltInCategory(id: "supplies", symbolName: "bag.fill", colorRole: .brown),
        BuiltInCategory(id: "train_bus", symbolName: "train.side.front.car", colorRole: .indigo),
        BuiltInCategory(id: "client_materials", symbolName: "doc.text.fill", colorRole: .slate, fallbackSymbolName: "doc.text.fill"),
        BuiltInCategory(id: "tips", symbolName: "hand.thumbsup.fill", colorRole: .mint),

        // Business Purchases / Tax
        BuiltInCategory(id: "software", symbolName: "laptopcomputer", colorRole: .cyan),
        BuiltInCategory(id: "professional_fees", symbolName: "briefcase.fill", colorRole: .purple),
        BuiltInCategory(id: "equipment", symbolName: "desktopcomputer", colorRole: .blue),
        BuiltInCategory(id: "advertising", symbolName: "megaphone.fill", colorRole: .orange),
        BuiltInCategory(id: "utilities", symbolName: "bolt.fill", colorRole: .amber),
        BuiltInCategory(id: "bank_fees", symbolName: "banknote.fill", colorRole: .teal, fallbackSymbolName: "banknote.fill"),
        BuiltInCategory(id: "insurance", symbolName: "shield.fill", colorRole: .indigo, fallbackSymbolName: "shield.fill"),

        // Home Project
        BuiltInCategory(id: "building_materials", symbolName: "hammer.fill", colorRole: .brown),
        BuiltInCategory(id: "tools", symbolName: "wrench.and.screwdriver.fill", colorRole: .teal),
        BuiltInCategory(id: "labor", symbolName: "person.fill", colorRole: .orange),
        BuiltInCategory(id: "delivery", symbolName: "truck.box.fill", colorRole: .cyan),
        BuiltInCategory(id: "permits", symbolName: "doc.text.fill", colorRole: .slate, fallbackSymbolName: "doc.text.fill"),
        BuiltInCategory(id: "fixtures", symbolName: "lightbulb.fill", colorRole: .amber),
        BuiltInCategory(id: "paint", symbolName: "paintbrush.fill", colorRole: .purple),
        BuiltInCategory(id: "electrical", symbolName: "bolt.circle.fill", colorRole: .plum),
        BuiltInCategory(id: "plumbing", symbolName: "drop.fill", colorRole: .blue),
        BuiltInCategory(id: "rental_equipment", symbolName: "wrench.adjustable.fill", colorRole: .mint),

        // Medical Claim
        BuiltInCategory(id: "consultation", symbolName: "stethoscope", colorRole: .mint),
        BuiltInCategory(id: "pharmacy", symbolName: "pills.fill", colorRole: .orange),
        BuiltInCategory(id: "tests_labs", symbolName: "testtube.2", colorRole: .purple),
        BuiltInCategory(id: "dental", symbolName: "cross.case.fill", colorRole: .cyan, fallbackSymbolName: "cross.case.fill"),
        BuiltInCategory(id: "vision", symbolName: "eyeglasses", colorRole: .indigo),
        BuiltInCategory(id: "hospital", symbolName: "building.2.fill", colorRole: .blue),
        BuiltInCategory(id: "transport", symbolName: "car.fill", colorRole: .teal),
        BuiltInCategory(id: "insurance_premium", symbolName: "shield.fill", colorRole: .slate, fallbackSymbolName: "shield.fill"),
        BuiltInCategory(id: "therapy", symbolName: "brain.head.profile", colorRole: .plum),
        BuiltInCategory(id: "medical_equipment", symbolName: "cross.case.fill", colorRole: .brown, fallbackSymbolName: "cross.case.fill"),
        BuiltInCategory(id: "medical", symbolName: "cross.case.fill", colorRole: .mint, fallbackSymbolName: "cross.case.fill"),

        // Vehicle Costs
        BuiltInCategory(id: "service", symbolName: "wrench.fill", colorRole: .teal),
        BuiltInCategory(id: "repairs", symbolName: "wrench.and.screwdriver.fill", colorRole: .orange),
        BuiltInCategory(id: "parking", symbolName: "parkingsign.circle.fill", colorRole: .cyan),
        BuiltInCategory(id: "tolls", symbolName: "road.lanes", colorRole: .purple),
        BuiltInCategory(id: "vehicle_registration", symbolName: "doc.text.fill", colorRole: .slate, fallbackSymbolName: "doc.text.fill"),
        BuiltInCategory(id: "tires", symbolName: "tirepressure", colorRole: .brown),
        BuiltInCategory(id: "washing", symbolName: "water.waves", colorRole: .blue),
        BuiltInCategory(id: "oil", symbolName: "oilcan.fill", colorRole: .plum),
        BuiltInCategory(id: "lease_finance", symbolName: "creditcard.fill", colorRole: .mint, fallbackSymbolName: "banknote.fill"),
        BuiltInCategory(id: "vehicle", symbolName: "car.fill", colorRole: .teal),

        // Moving / Relocation
        BuiltInCategory(id: "movers", symbolName: "box.truck.fill", colorRole: .blue),
        BuiltInCategory(id: "packing", symbolName: "shippingbox.fill", colorRole: .brown),
        BuiltInCategory(id: "storage", symbolName: "archivebox.fill", colorRole: .purple),
        BuiltInCategory(id: "truck_rental", symbolName: "box.truck.fill", colorRole: .teal),
        BuiltInCategory(id: "utilities_setup", symbolName: "bolt.fill", colorRole: .slate),
        BuiltInCategory(id: "cleaning", symbolName: "bubbles.and.sparkles.fill", colorRole: .mint),

        // Event / Function
        BuiltInCategory(id: "venue", symbolName: "building.columns.fill", colorRole: .indigo),
        BuiltInCategory(id: "catering", symbolName: "fork.knife.circle.fill", colorRole: .orange),
        BuiltInCategory(id: "decor", symbolName: "party.popper.fill", colorRole: .plum),
        BuiltInCategory(id: "travel", symbolName: "airplane", colorRole: .blue),
        BuiltInCategory(id: "audio_visual", symbolName: "display", colorRole: .cyan),
        BuiltInCategory(id: "staff", symbolName: "person.2.fill", colorRole: .purple),
        BuiltInCategory(id: "gifts", symbolName: "gift.fill", colorRole: .amber),

        // Warranty / Big Purchase
        BuiltInCategory(id: "purchase", symbolName: "cart.fill", colorRole: .orange),
        BuiltInCategory(id: "accessories", symbolName: "puzzlepiece.extension.fill", colorRole: .purple),
        BuiltInCategory(id: "installation", symbolName: "square.and.arrow.down.fill", colorRole: .teal),
        BuiltInCategory(id: "repair", symbolName: "wrench.fill", colorRole: .amber),
        BuiltInCategory(id: "warranty_plan", symbolName: "checkmark.seal.fill", colorRole: .mint),
        BuiltInCategory(id: "replacement_parts", symbolName: "puzzlepiece.extension.fill", colorRole: .brown),
        BuiltInCategory(id: "service_visit", symbolName: "calendar.badge.clock", colorRole: .indigo)
    ]
}

// MARK: - Custom categories

public enum CustomCategory {
    public static let idPrefix = "custom_"
    public static let defaultSymbolName = "tag.fill"
    public static let maximumNameLength = 40
    public static let autoAssignedColorPriority: [CategoryColorRole] = [
        .orange, .teal, .purple, .amber, .cyan, .indigo, .mint, .blue, .brown, .plum, .slate
    ]

    /// Derives a stable ASCII, storage- and CSV-safe identifier from a user-authored label
    /// (e.g. "Booth Setup" -> "custom_booth_setup"). Returns `nil` when the label yields no usable
    /// slug. `existingIDs` is used to disambiguate collisions within a single folder snapshot.
    public static func makeIdentifier(from name: String, existingIDs: Set<String> = []) -> String? {
        let slug = slugify(name)
        guard slug.isEmpty == false else { return nil }
        var candidate = idPrefix + slug
        guard CategoryCatalog.isValidIdentifier(candidate) else { return nil }

        var suffix = 2
        while existingIDs.contains(candidate) {
            candidate = "\(idPrefix)\(slug)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Builds a folder-local custom category from a user label. Color is assigned deterministically
    /// from the current folder snapshot, and gray is reserved for Other and unresolved categories.
    public static func make(
        name: String,
        symbolName: String = defaultSymbolName,
        existingIDs: Set<String> = [],
        existingCategories: [FolderCategory] = []
    ) -> FolderCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        guard let id = makeIdentifier(from: trimmed, existingIDs: existingIDs) else { return nil }
        let clamped = String(trimmed.prefix(maximumNameLength))
        return FolderCategory(
            id: id,
            symbolName: symbolName,
            colorRole: autoAssignedColorRole(avoiding: existingCategories),
            customName: clamped
        )
    }

    public static func autoAssignedColorRole(avoiding existingCategories: [FolderCategory]) -> CategoryColorRole {
        let counts = Dictionary(grouping: existingCategories.map(\.colorRole), by: { $0 })
            .mapValues(\.count)

        if let unused = autoAssignedColorPriority.first(where: { counts[$0, default: 0] == 0 }) {
            return unused
        }

        return autoAssignedColorPriority.min { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount == rhsCount {
                return priorityIndex(lhs) < priorityIndex(rhs)
            }
            return lhsCount < rhsCount
        } ?? .orange
    }

    public static func assigningAutoColor(to category: FolderCategory, avoiding existingCategories: [FolderCategory]) -> FolderCategory {
        guard category.isCustom, category.colorRole == .gray else { return category }
        var updated = category
        updated.colorRoleRawValue = autoAssignedColorRole(avoiding: existingCategories).rawValue
        return updated
    }

    public static func healingGrayCustomCategories(in categories: [FolderCategory]) -> [FolderCategory] {
        var healed: [FolderCategory] = []
        for category in FolderCategorySnapshot.normalized(categories) {
            let next = assigningAutoColor(to: category, avoiding: healed)
            healed.append(next)
        }
        return FolderCategorySnapshot.normalized(healed)
    }

    private static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        var scalars = String.UnicodeScalarView()
        var lastWasUnderscore = false
        for scalar in lowered.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                scalars.append(scalar)
                lastWasUnderscore = false
            } else if lastWasUnderscore == false {
                scalars.append("_")
                lastWasUnderscore = true
            }
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func priorityIndex(_ role: CategoryColorRole) -> Int {
        autoAssignedColorPriority.firstIndex(of: role) ?? Int.max
    }
}
