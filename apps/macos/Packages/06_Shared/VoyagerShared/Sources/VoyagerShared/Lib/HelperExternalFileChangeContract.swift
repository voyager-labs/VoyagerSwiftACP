import Foundation

public extension Notification.Name {
    nonisolated static let voyagerHelperFSChanged = Notification.Name("voyagerHelperFSChanged")
    nonisolated static let voyagerHelperFSReplayRequest = Notification.Name("voyagerHelperFSReplayRequest")
    nonisolated static let voyagerHelperFSReplay = Notification.Name("voyagerHelperFSReplay")
    nonisolated static let voyagerHelperFSReplayAck = Notification.Name("voyagerHelperFSReplayAck")
    nonisolated static let voyagerHelperFSWatchRootsChanged = Notification.Name("voyagerHelperFSWatchRootsChanged")
}

nonisolated public enum HelperExternalFileChangeUserInfoKey {
    public static let schemaVersion = "schema_version"
    public static let generatedAt = "generated_at"
    public static let paths = "paths"
    public static let consume = "consume"
}

nonisolated public struct HelperExternalFileChangeReplayRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let consume: Bool

    nonisolated public init(schemaVersion: Int = 1, consume: Bool = true) {
        self.schemaVersion = schemaVersion
        self.consume = consume
    }

    nonisolated public func asUserInfo() -> [String: Any] {
        [
            HelperExternalFileChangeUserInfoKey.schemaVersion: schemaVersion,
            HelperExternalFileChangeUserInfoKey.consume: consume,
        ]
    }

    nonisolated public static func from(userInfo: [AnyHashable: Any]?) -> Self? {
        guard let userInfo else { return nil }
        guard let schemaVersion = parseInt(userInfo[HelperExternalFileChangeUserInfoKey.schemaVersion]),
              schemaVersion == 1
        else {
            return nil
        }
        guard let consume = parseBool(userInfo[HelperExternalFileChangeUserInfoKey.consume]) else {
            return nil
        }

        return Self(schemaVersion: schemaVersion, consume: consume)
    }

    nonisolated private static func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    nonisolated private static func parseBool(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool { return boolValue }
        if let number = value as? NSNumber { return number.boolValue }
        if let stringValue = value as? String { return Bool(stringValue) }
        return nil
    }
}

nonisolated public struct HelperExternalFileChangePayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let paths: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case paths
    }

    nonisolated public init(
        paths: [String],
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.paths = Self.canonicalPaths(paths)
    }

    nonisolated public func merging(paths newPaths: [String], generatedAt: Date = Date()) -> Self {
        Self(
            paths: paths + newPaths,
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
        )
    }

    nonisolated public func asUserInfo() -> [String: Any] {
        [
            HelperExternalFileChangeUserInfoKey.schemaVersion: schemaVersion,
            HelperExternalFileChangeUserInfoKey.generatedAt: generatedAt.timeIntervalSince1970,
            HelperExternalFileChangeUserInfoKey.paths: paths,
        ]
    }

    nonisolated public static func from(userInfo: [AnyHashable: Any]?, allowEmptyPaths: Bool = false) -> Self? {
        guard let userInfo else { return nil }
        guard let schemaVersion = parseInt(userInfo[HelperExternalFileChangeUserInfoKey.schemaVersion]),
              schemaVersion == 1
        else {
            return nil
        }
        guard let paths = userInfo[HelperExternalFileChangeUserInfoKey.paths] as? [String] else {
            return nil
        }
        if !allowEmptyPaths, paths.isEmpty {
            return nil
        }

        let generatedAt = if let timestamp = parseDouble(userInfo[HelperExternalFileChangeUserInfoKey.generatedAt]) {
            Date(timeIntervalSince1970: timestamp)
        } else {
            Date()
        }

        return Self(paths: paths, schemaVersion: schemaVersion, generatedAt: generatedAt)
    }

    nonisolated public static func canonicalPaths(_ paths: [String]) -> [String] {
        Array(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
    }

    nonisolated private static func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    nonisolated private static func parseDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let number = value as? NSNumber { return number.doubleValue }
        if let stringValue = value as? String { return Double(stringValue) }
        return nil
    }
}
