import Foundation

public struct FolderProfileIdentity: Equatable, Sendable {
    public var symbolName: String
    public var colorRole: CategoryColorRole?

    public init(symbolName: String, colorRole: CategoryColorRole?) {
        self.symbolName = symbolName
        self.colorRole = colorRole
    }
}

/// A folder profile is a preset, not a rigid type (SPEC §D2). It seeds a folder's visible category
/// snapshot at creation time and offers profile-specific suggestions, but the folder owns its
/// editable list afterward. Display names live in the String Catalog under `folder.profile.<id>`.
public struct FolderProfile: Equatable, Sendable, Identifiable {
    public var id: String
    /// Whether the profile is date-bound (trip-like). Date fields are shown by default for these and
    /// hidden-but-toggleable for the rest (SPEC §D4).
    public var isDateBound: Bool
    /// Default visible categories in order, always ending in `other`.
    public var defaultCategoryIDs: [String]
    /// Profile-specific add-on suggestions shown directly below the selected set (SPEC §D4).
    public var suggestedCategoryIDs: [String]
    /// Folder glyph identity used in rows, cards, and profile pickers.
    public var identity: FolderProfileIdentity

    public init(
        id: String,
        isDateBound: Bool,
        defaultCategoryIDs: [String],
        suggestedCategoryIDs: [String],
        identity: FolderProfileIdentity
    ) {
        self.id = id
        self.isDateBound = isDateBound
        self.defaultCategoryIDs = defaultCategoryIDs
        self.suggestedCategoryIDs = suggestedCategoryIDs
        self.identity = identity
    }

    public var nameKey: String {
        "folder.profile.\(id)"
    }

    /// The default visible-category snapshot for this profile.
    public var defaultSnapshot: FolderCategorySnapshot {
        FolderCategorySnapshot(categories: CategoryCatalog.folderCategories(ids: defaultCategoryIDs))
    }
}

/// The deliberately small, receipt-first preset catalog (SPEC §D8). Order matches the profile picker.
public enum FolderProfileCatalog {
    public static let workTripID = "workTrip"
    public static let customID = "custom"

    public static func profile(id: String) -> FolderProfile? {
        byID[id]
    }

    public static var workTrip: FolderProfile {
        profile(id: workTripID) ?? all[0]
    }

    public static var customIdentity: FolderProfileIdentity {
        FolderProfileIdentity(symbolName: "folder.fill", colorRole: nil)
    }

    /// The default visible-category snapshot for a profile ID, falling back to Work Trip for unknown
    /// IDs. This is the lazy migration default for pre-profile folders (SPEC §6, §11.1).
    public static func defaultSnapshot(forProfileID id: String) -> FolderCategorySnapshot {
        (profile(id: id) ?? workTrip).defaultSnapshot
    }

    public static func identity(forProfileID id: String) -> FolderProfileIdentity {
        profile(id: id)?.identity ?? customIdentity
    }

    /// Suggested add-on categories for a profile, excluding those already selected. Custom folders
    /// have no short suggestion list — every built-in is reachable through Browse instead.
    public static func suggestedCategories(forProfileID id: String, excluding selectedIDs: Set<String>) -> [FolderCategory] {
        guard let profile = profile(id: id) else { return [] }
        return profile.suggestedCategoryIDs
            .filter { selectedIDs.contains($0) == false }
            .compactMap { CategoryCatalog.folderCategory(id: $0) }
    }

    private static let byID: [String: FolderProfile] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    public static let all: [FolderProfile] = [
        FolderProfile(
            id: "workTrip",
            isDateBound: true,
            defaultCategoryIDs: ["flight", "hotel", "food", "taxi", "other"],
            suggestedCategoryIDs: ["parking_tolls", "laundry", "baggage", "business_calls"],
            identity: FolderProfileIdentity(symbolName: "suitcase.fill", colorRole: .blue)
        ),
        FolderProfile(
            id: "conference",
            isDateBound: true,
            defaultCategoryIDs: ["registration", "flight", "hotel", "food", "taxi", "materials", "other"],
            suggestedCategoryIDs: ["booth_display", "shipping", "wifi_tech", "printing", "professional_development"],
            identity: FolderProfileIdentity(symbolName: "person.3.fill", colorRole: .purple)
        ),
        FolderProfile(
            id: "clientVisit",
            isDateBound: true,
            defaultCategoryIDs: ["food", "taxi", "parking_tolls", "fuel", "supplies", "other"],
            suggestedCategoryIDs: ["train_bus", "client_materials", "tips"],
            identity: FolderProfileIdentity(symbolName: "person.2.fill", colorRole: .cyan)
        ),
        FolderProfile(
            id: "homeProject",
            isDateBound: false,
            defaultCategoryIDs: ["building_materials", "tools", "labor", "delivery", "permits", "fixtures", "other"],
            suggestedCategoryIDs: ["paint", "electrical", "plumbing", "rental_equipment"],
            identity: FolderProfileIdentity(symbolName: "hammer.fill", colorRole: .amber)
        ),
        FolderProfile(
            id: "medicalClaim",
            isDateBound: false,
            defaultCategoryIDs: ["consultation", "pharmacy", "tests_labs", "dental", "vision", "hospital", "transport", "other"],
            suggestedCategoryIDs: ["insurance_premium", "therapy", "medical_equipment"],
            identity: FolderProfileIdentity(symbolName: "cross.case.fill", colorRole: .mint)
        ),
        FolderProfile(
            id: "vehicleCosts",
            isDateBound: false,
            defaultCategoryIDs: ["fuel", "service", "repairs", "parking", "tolls", "vehicle_registration", "insurance", "other"],
            suggestedCategoryIDs: ["tires", "washing", "oil", "lease_finance"],
            identity: FolderProfileIdentity(symbolName: "car.fill", colorRole: .teal)
        ),
        FolderProfile(
            id: "businessPurchases",
            isDateBound: false,
            defaultCategoryIDs: ["supplies", "software", "printing", "shipping", "professional_fees", "equipment", "other"],
            suggestedCategoryIDs: ["advertising", "utilities", "bank_fees", "insurance"],
            identity: FolderProfileIdentity(symbolName: "cart.fill", colorRole: .indigo)
        ),
        FolderProfile(
            id: "moving",
            isDateBound: true,
            defaultCategoryIDs: ["movers", "packing", "storage", "fuel", "hotel", "food", "delivery", "other"],
            suggestedCategoryIDs: ["truck_rental", "utilities_setup", "cleaning"],
            identity: FolderProfileIdentity(symbolName: "shippingbox.fill", colorRole: .brown)
        ),
        FolderProfile(
            id: "event",
            isDateBound: true,
            defaultCategoryIDs: ["venue", "catering", "decor", "printing", "supplies", "travel", "other"],
            suggestedCategoryIDs: ["audio_visual", "staff", "gifts"],
            identity: FolderProfileIdentity(symbolName: "party.popper.fill", colorRole: .plum)
        ),
        FolderProfile(
            id: "warranty",
            isDateBound: false,
            defaultCategoryIDs: ["purchase", "accessories", "delivery", "installation", "repair", "warranty_plan", "other"],
            suggestedCategoryIDs: ["replacement_parts", "service_visit"],
            identity: FolderProfileIdentity(symbolName: "checkmark.seal.fill", colorRole: .orange)
        ),
        FolderProfile(
            id: "custom",
            isDateBound: false,
            defaultCategoryIDs: ["food", "supplies", "transport", "other"],
            suggestedCategoryIDs: [],
            identity: customIdentity
        )
    ]
}

public extension FolderCategorySnapshot {
    /// The compact default set for Unfiled review, used until a folder is chosen (SPEC §D6).
    static var unfiledDefault: FolderCategorySnapshot {
        FolderCategorySnapshot(categories: CategoryCatalog.folderCategories(
            ids: ["food", "travel", "supplies", "medical", "vehicle", "other"]
        ))
    }
}
