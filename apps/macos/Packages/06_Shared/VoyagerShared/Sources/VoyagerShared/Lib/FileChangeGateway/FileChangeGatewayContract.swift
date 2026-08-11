import CoreServices
import Foundation

public extension Notification.Name {
    static let voyagerFileChangeGatewayInterestsUpdated = Notification.Name("voyagerFileChangeGatewayInterestsUpdated")
    static let voyagerFileChangeGatewayInterestsRemoved = Notification.Name("voyagerFileChangeGatewayInterestsRemoved")
    static let voyagerFileChangeGatewayEvents = Notification.Name("voyagerFileChangeGatewayEvents")
}

public enum FileChangeWatchPurpose: String, Sendable, Codable, Equatable {
    case visibleFolderReload
    case collectionStale
    case automation
}

public enum FileChangeWatchOwner: String, Sendable, Codable, Equatable {
    case fileManager
    case collection
    case automation
}

public struct FileChangeWatchInterest: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var owner: FileChangeWatchOwner
    public var purpose: FileChangeWatchPurpose
    public var roots: [String]
    public var includeSubfolders: Bool
    public var excludedRoots: [String]

    nonisolated public init(
        id: String,
        owner: FileChangeWatchOwner,
        purpose: FileChangeWatchPurpose,
        roots: [String],
        includeSubfolders: Bool = true,
        excludedRoots: [String] = [],
    ) {
        self.id = id
        self.owner = owner
        self.purpose = purpose
        self.roots = roots
        self.includeSubfolders = includeSubfolders
        self.excludedRoots = excludedRoots
    }
}

public struct FileChangeGatewayEvent: Sendable, Codable, Equatable {
    public var path: String
    public var flags: UInt32
    public var emittedAt: Date

    nonisolated public init(path: String, flags: UInt32, emittedAt: Date = Date()) {
        self.path = FileChangeScopePolicy.normalizedPath(path)
        self.flags = flags
        self.emittedAt = emittedAt
    }
}

public struct FileChangeGatewayEventBatch: Sendable, Equatable {
    public let events: [FileChangeGatewayEvent]
    public let deliveryChainToken: String?

    nonisolated public init(
        events: [FileChangeGatewayEvent],
        deliveryChainToken: String? = nil,
    ) {
        self.events = events
        self.deliveryChainToken = deliveryChainToken
    }
}

public enum FileChangeGatewayLimits {
    public static let maxActiveWatchRoots = 64
    public static let maxEventsPerBatch = 256
}

public enum FileChangeGatewayPayload {
    private static let interestsKey = "interests"
    private static let idsKey = "ids"
    private static let eventsKey = "events"

    nonisolated public static func userInfo(forInterests interests: [FileChangeWatchInterest]) -> [AnyHashable: Any] {
        [interestsKey: encodedArray(interests)]
    }

    nonisolated public static func interests(from userInfo: [AnyHashable: Any]?) -> [FileChangeWatchInterest] {
        decodedArray(userInfo?[interestsKey])
    }

    nonisolated public static func userInfo(forRemovedInterestIDs ids: [String]) -> [AnyHashable: Any] {
        [idsKey: ids]
    }

    nonisolated public static func removedInterestIDs(from userInfo: [AnyHashable: Any]?) -> [String] {
        userInfo?[idsKey] as? [String] ?? []
    }

    nonisolated public static func userInfo(forEvents events: [FileChangeGatewayEvent]) -> [AnyHashable: Any] {
        [eventsKey: encodedArray(events)]
    }

    nonisolated public static func events(from userInfo: [AnyHashable: Any]?) -> [FileChangeGatewayEvent] {
        decodedArray(userInfo?[eventsKey])
    }

    nonisolated private static func encodedArray(_ values: [some Encodable]) -> [[String: Any]] {
        values.compactMap { value in
            guard let data = try? JSONEncoder().encode(value),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return object
        }
    }

    nonisolated private static func decodedArray<T: Decodable>(_ rawValue: Any?) -> [T] {
        guard let rawArray = rawValue as? [[String: Any]] else { return [] }
        return rawArray.compactMap { rawItem in
            guard let data = try? JSONSerialization.data(withJSONObject: rawItem) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    }
}

public enum FileChangeScopePolicy {
    nonisolated public static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    nonisolated public static func canonicalPath(_ path: String) -> String {
        var pendingComponents = Array((normalizedPath(path) as NSString).pathComponents.dropFirst())
        var resolvedURL = URL(fileURLWithPath: "/")
        var resolvedSymlinkCount = 0

        while let component = pendingComponents.first {
            pendingComponents.removeFirst()
            let candidateURL = resolvedURL.appendingPathComponent(component)
            guard resolvedSymlinkCount < 40,
                  let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: candidateURL.path)
            else {
                resolvedURL = candidateURL
                continue
            }

            pendingComponents = symlinkDestinationComponents(
                destination,
                relativeTo: resolvedURL,
            ) + pendingComponents
            resolvedURL = URL(fileURLWithPath: "/")
            resolvedSymlinkCount += 1
        }

        return resolvedURL.path
    }

    nonisolated public static func normalizedAbsolutePaths(_ paths: [String]) -> [String] {
        Array(Set(paths.filter { !$0.isEmpty && $0.hasPrefix("/") }.map(normalizedPath))).sorted()
    }

    nonisolated public static func allowedWatchRoots(from roots: [String]) -> [String] {
        normalizedAbsolutePaths(roots).filter { !isBroadRoot($0) }
    }

    nonisolated public static func isBroadRoot(_ path: String) -> Bool {
        let canonicalPath = normalizedPath(path)
        guard !canonicalPath.isEmpty else { return true }

        let homePath = normalizedPath(NSHomeDirectory())
        let cloudStoragePath = normalizedPath(homePath + "/Library/CloudStorage")
        let mobileDocumentsPath = normalizedPath(homePath + "/Library/Mobile Documents")
        let libraryPath = normalizedPath(homePath + "/Library")

        return canonicalPath == "/"
            || canonicalPath == homePath
            || canonicalPath == libraryPath
            || canonicalPath == cloudStoragePath
            || canonicalPath == mobileDocumentsPath
    }

    nonisolated public static func interestAffectedPaths(
        events: [FileChangeGatewayEvent],
        interest: FileChangeWatchInterest,
    ) -> [String] {
        let roots = normalizedAbsolutePaths(interest.roots)
        let excludedRoots = normalizedAbsolutePaths(interest.excludedRoots)
        return events.compactMap { event in
            guard event.isStaleWorthyPathChange else { return nil }
            let path = normalizedPath(event.path)
            guard roots
                .contains(where: { affects(root: $0, path: path, includeSubfolders: interest.includeSubfolders) })
            else {
                return nil
            }
            guard !excludedRoots.contains(where: { affects(root: $0, path: path, includeSubfolders: true) }) else {
                return nil
            }
            return path
        }
    }

    nonisolated public static func affects(root: String, path: String, includeSubfolders: Bool) -> Bool {
        let root = canonicalPath(root)
        let path = canonicalPath(path)
        guard !root.isEmpty, !path.isEmpty else { return false }
        if includeSubfolders == false {
            return path == root || (path as NSString).deletingLastPathComponent == root
        }
        return path == root || (root == "/" ? path.hasPrefix("/") : path.hasPrefix(root + "/"))
    }

    nonisolated private static func symlinkDestinationComponents(
        _ destination: String,
        relativeTo resolvedURL: URL,
    ) -> [String] {
        var components = destination.hasPrefix("/")
            ? []
            : Array((resolvedURL.path as NSString).pathComponents.dropFirst())
        for component in (destination as NSString).pathComponents {
            switch component {
            case "/", ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(component)
            }
        }
        return components
    }
}

public extension FileChangeGatewayEvent {
    nonisolated var isStaleWorthyPathChange: Bool {
        flags.fileChangeGatewayContainsAnyFlag([
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
            kFSEventStreamEventFlagItemCreated,
            kFSEventStreamEventFlagItemRemoved,
            kFSEventStreamEventFlagItemRenamed,
            kFSEventStreamEventFlagItemModified,
        ])
    }
}

private extension UInt32 {
    nonisolated func fileChangeGatewayContainsAnyFlag(_ flags: [Int]) -> Bool {
        flags.contains { flag in
            self & UInt32(flag) != 0
        }
    }
}
