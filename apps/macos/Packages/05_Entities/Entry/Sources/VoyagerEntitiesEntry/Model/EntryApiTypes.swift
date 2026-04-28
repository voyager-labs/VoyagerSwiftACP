import Foundation
import UniformTypeIdentifiers

public struct ApplicationInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String?
    public let isDefault: Bool

    public nonisolated init(id: String, name: String, bundleID: String?, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.isDefault = isDefault
    }
}

public struct EntryItemMetadata: Equatable, Sendable {
    public let kind: String
    public let creatorApplication: String?
    public let lastUsedDate: Date?

    public nonisolated init(kind: String, creatorApplication: String?, lastUsedDate: Date?) {
        self.kind = kind
        self.creatorApplication = creatorApplication
        self.lastUsedDate = lastUsedDate
    }
}

public enum OpenKind: Equatable, Sendable {
    case defaultApp
    case bundleID(String)
}

public enum FileOpError: Error, Equatable, Sendable {
    case notFound
    case unsupportedType
    case cancelled
    case fileExists(itemName: String)
    case system(message: String, suggestion: String? = nil)

    public var message: String {
        switch self {
        case .notFound:
            "The item could not be found."
        case .unsupportedType:
            "This item type is not supported."
        case .cancelled:
            "The operation was cancelled."
        case let .fileExists(itemName):
            "A newer item named \"\(itemName)\" already exists in this location."
        case let .system(message, _):
            message
        }
    }

    public var suggestion: String? {
        switch self {
        case let .system(_, hint):
            hint
        default:
            nil
        }
    }

    public var isFileExists: Bool {
        if case .fileExists = self {
            return true
        }
        return false
    }

    public var itemName: String? {
        if case let .fileExists(name) = self {
            return name
        }
        return nil
    }
}
