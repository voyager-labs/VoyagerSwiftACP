import Foundation

/// Helper 폴더 권한 요청/응답 알림 이름 정의
public extension Notification.Name {
    static let voyagerHelperFolderAccessRequest = Notification.Name("voyagerHelperFolderAccessRequest")
    static let voyagerHelperFolderAccessDidUpdate = Notification.Name("voyagerHelperFolderAccessDidUpdate")
}
