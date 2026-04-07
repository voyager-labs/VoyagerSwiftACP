import Foundation

extension Notification.Name {
    static let voyagerHelperFolderAccessRequest = Notification.Name("voyagerHelperFolderAccessRequest")
    static let voyagerHelperFolderAccessDidUpdate = Notification.Name("voyagerHelperFolderAccessDidUpdate")
}

nonisolated enum HelperFolderAccessUserInfoKey {
    static let schemaVersion = "schema_version"
    static let mode = "mode"
    static let desktop = "desktop"
    static let documents = "documents"
    static let downloads = "downloads"
}

nonisolated enum HelperFolderAccessMode: String, Sendable {
    case check
    case request
}
