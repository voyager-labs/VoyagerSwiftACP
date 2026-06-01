import Foundation

/// Helper 폴더 권한 요청/응답 알림 이름 정의
extension Notification.Name {
    static let voyagerHelperFolderAccessRequest = Notification.Name("voyagerHelperFolderAccessRequest")
    static let voyagerHelperFolderAccessDidUpdate = Notification.Name("voyagerHelperFolderAccessDidUpdate")
}

/// Helper 폴더 권한 알림 payload key 정의
nonisolated enum HelperFolderAccessUserInfoKey {
    static let schemaVersion = "schema_version"
    static let mode = "mode"
    static let desktop = "desktop"
    static let documents = "documents"
    static let downloads = "downloads"
}
