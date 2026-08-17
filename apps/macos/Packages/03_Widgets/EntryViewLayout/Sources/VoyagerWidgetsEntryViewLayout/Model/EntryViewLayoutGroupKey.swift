import Foundation
import VoyagerShared

public enum EntryViewLayoutGroupKey: String, Equatable, Codable, Sendable, CaseIterable {
    case none = "None"
    case name = "Name"
    case kind = "Kind"
    case application = "Application"
    case dateLastOpened = "Date Last Opened"
    case dateAdded = "Date Added"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    case size = "Size"
    case tags = "Tags"
}

public extension EntryViewLayoutGroupKey {
    /// Convert from a shared `GroupKey` raw value to the Widget enum.
    static func fromShared(_ rawValue: String) -> EntryViewLayoutGroupKey {
        .init(rawValue: rawValue) ?? .none
    }
}
