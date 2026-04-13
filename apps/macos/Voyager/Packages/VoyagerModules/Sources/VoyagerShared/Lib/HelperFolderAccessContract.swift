import Foundation

public enum HelperFolderAccessContract {
    public nonisolated static let requestName = Notification.Name("voyagerHelperFolderAccessRequest")
    public nonisolated static let responseName = Notification.Name("voyagerHelperFolderAccessDidUpdate")
}

public nonisolated enum HelperFolderAccessUserInfoKey {
    public static let schemaVersion = "schema_version"
    public static let mode = "mode"
    public static let desktop = "desktop"
    public static let documents = "documents"
    public static let downloads = "downloads"
}

public nonisolated enum HelperFolderAccessMode: String, Sendable {
    case check
    case request
}
