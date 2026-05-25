import Foundation

public enum CollectionFileReferenceSnapshotStatus: String, Sendable {
    case usable
    case missing
    case stale
    case unreadable
}

public struct CollectionFileReferenceSnapshot: Equatable, Sendable {
    public let status: CollectionFileReferenceSnapshotStatus
    public let itemPaths: [String]
    public let itemCount: Int?

    public init(
        status: CollectionFileReferenceSnapshotStatus,
        itemPaths: [String] = [],
        itemCount: Int? = nil
    ) {
        self.status = status
        self.itemPaths = itemPaths
        self.itemCount = itemCount
    }
}

public enum CollectionFileReferenceExtractor {
    public static func referenceSnapshot(at fileURL: URL) -> CollectionFileReferenceSnapshot {
        do {
            let file = try loadCollectionFile(at: fileURL.standardizedFileURL)
            guard file.snapshot != nil else {
                return CollectionFileReferenceSnapshot(status: .missing)
            }
            guard file.snapshotMeta != nil,
                  let snapshot = CollectionSnapshotHydration.usableSnapshot(for: file)
            else {
                return CollectionFileReferenceSnapshot(status: .stale)
            }

            let paths = itemPaths(from: snapshot)
            return CollectionFileReferenceSnapshot(
                status: .usable,
                itemPaths: paths,
                itemCount: paths.count
            )
        } catch {
            return CollectionFileReferenceSnapshot(status: .unreadable)
        }
    }

    private static func loadCollectionFile(at fileURL: URL) throws -> VoyagerCollectionFile {
        let payloadURL: URL
        let containerFormat: CollectionFileContainerFormat
        let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues?.isDirectory == true {
            payloadURL = fileURL.appendingPathComponent("collection.plist")
            containerFormat = .package
        } else {
            payloadURL = fileURL
            containerFormat = .legacySingleFile
        }
        let data = try Data(contentsOf: payloadURL)
        return try VoyagerCollectionFileCompatibilityOwner.decode(
            data,
            containerFormat: containerFormat
        ).file
    }

    private static func itemPaths(from snapshot: CollectionPersistedSnapshot) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for item in snapshot.items {
            guard case let .string(rawPath) = item else { continue }
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            guard !standardized.isEmpty, seen.insert(standardized).inserted else { continue }
            paths.append(standardized)
        }
        return paths
    }
}
