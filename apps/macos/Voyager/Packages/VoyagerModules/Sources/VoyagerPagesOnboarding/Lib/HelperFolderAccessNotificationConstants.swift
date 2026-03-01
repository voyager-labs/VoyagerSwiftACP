import Foundation

enum HelperFolderAccessNotificationName {
    static let request = "voyagerHelperFolderAccessRequest"
    static let didUpdate = "voyagerHelperFolderAccessDidUpdate"
}

enum HelperFolderAccessUserInfoKey {
    static let schemaVersion = "schema_version"
    static let desktop = "desktop"
    static let documents = "documents"
    static let downloads = "downloads"
}
