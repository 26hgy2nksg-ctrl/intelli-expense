import Foundation

struct SharedInboxItem: Identifiable, Equatable {
    var id: String { url.lastPathComponent }
    var url: URL
    var createdAt: Date
    var pageFilenames: [String]

    var pageURLs: [URL] {
        pageFilenames.map { url.appendingPathComponent($0) }
    }

    func readPageData() throws -> [Data] {
        try pageURLs.map { try Data(contentsOf: $0) }
    }
}

struct SharedReceiptInbox {
    static let appGroupIdentifier = "group.com.nags.intelliexpense"
    private static let inboxDirectoryName = "SharedInbox"
    private static let manifestFilename = "manifest.json"
    private let fileManager: FileManager
    let containerURL: URL

    init(containerURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let containerURL {
            self.containerURL = containerURL
        } else if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) {
            self.containerURL = appGroupURL
        } else {
            throw SharedReceiptInboxError.appGroupUnavailable
        }
    }

    func write(images: [Data]) throws -> URL {
        guard images.isEmpty == false else {
            throw SharedReceiptInboxError.emptyImages
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let itemURL = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)

        do {
            let pageFilenames = images.indices.map { "page-\($0).jpg" }
            for (data, filename) in zip(images, pageFilenames) {
                try data.write(to: itemURL.appendingPathComponent(filename), options: [.atomic])
            }
            let manifest = Manifest(version: 1, createdAt: Date(), pageFilenames: pageFilenames)
            try encoder.encode(manifest).write(
                to: itemURL.appendingPathComponent(Self.manifestFilename),
                options: [.atomic]
            )
            return itemURL
        } catch {
            try? fileManager.removeItem(at: itemURL)
            throw error
        }
    }

    func pendingItems() throws -> [SharedInboxItem] {
        try itemCandidateURLs().compactMap { itemURL in
            try? item(at: itemURL)
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func remove(_ item: SharedInboxItem) throws {
        guard fileManager.fileExists(atPath: item.url.path) else { return }
        try fileManager.removeItem(at: item.url)
    }

    func sweep(olderThan cutoff: Date) throws {
        for itemURL in try itemCandidateURLs() {
            guard (try? item(at: itemURL)) == nil else { continue }
            let date = candidateDate(for: itemURL)
            if date < cutoff {
                try fileManager.removeItem(at: itemURL)
            }
        }
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
    }

    private var rootURL: URL {
        containerURL.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
    }

    private func itemCandidateURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func item(at itemURL: URL) throws -> SharedInboxItem {
        let manifest = try decoder.decode(
            Manifest.self,
            from: Data(contentsOf: itemURL.appendingPathComponent(Self.manifestFilename))
        )
        guard manifest.version == 1, manifest.pageFilenames.isEmpty == false else {
            throw SharedReceiptInboxError.invalidManifest
        }
        let pageURLs = manifest.pageFilenames.map { itemURL.appendingPathComponent($0) }
        guard pageURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw SharedReceiptInboxError.missingPage
        }
        return SharedInboxItem(
            url: itemURL,
            createdAt: manifest.createdAt,
            pageFilenames: manifest.pageFilenames
        )
    }

    private func candidateDate(for itemURL: URL) -> Date {
        let values = try? itemURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601DateFormatter(includingFractionalSeconds: true).string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.iso8601DateFormatter(includingFractionalSeconds: true).date(from: value) ??
                Self.iso8601DateFormatter(includingFractionalSeconds: false).date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date."
            )
        }
        return decoder
    }

    private static func iso8601DateFormatter(includingFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includingFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

enum SharedReceiptInboxError: Error, Equatable {
    case appGroupUnavailable
    case emptyImages
    case invalidManifest
    case missingPage
}

private struct Manifest: Codable {
    var version: Int
    var createdAt: Date
    var pageFilenames: [String]
}
