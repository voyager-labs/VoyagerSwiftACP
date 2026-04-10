import Foundation

extension Notification.Name {
    static let voyagerHelperFolderAccessRequest = Notification.Name("voyagerHelperFolderAccessRequest")
    static let voyagerHelperFolderAccessDidUpdate = Notification.Name("voyagerHelperFolderAccessDidUpdate")
}

public nonisolated enum HelperFolderAccessUserInfoKey {
    public static let schemaVersion = "schema_version"
    public static let desktop = "desktop"
    public static let documents = "documents"
    public static let downloads = "downloads"
}
