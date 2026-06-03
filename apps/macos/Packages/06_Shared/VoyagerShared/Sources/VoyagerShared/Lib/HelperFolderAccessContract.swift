import Foundation

public enum HelperFolderAccessContract {
    nonisolated public static let requestName = Notification.Name("voyagerHelperFolderAccessRequest")
    nonisolated public static let responseName = Notification.Name("voyagerHelperFolderAccessDidUpdate")
}

nonisolated public enum HelperFolderAccessUserInfoKey {
    public static let schemaVersion = "schema_version"
    public static let mode = "mode"
    public static let desktop = "desktop"
    public static let documents = "documents"
    public static let downloads = "downloads"
}

nonisolated public enum HelperFolderAccessMode: String, Sendable {
    case check
    case request
}
