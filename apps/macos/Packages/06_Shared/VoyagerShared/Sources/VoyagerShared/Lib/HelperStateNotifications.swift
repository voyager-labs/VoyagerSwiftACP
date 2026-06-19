import Foundation

/// Helper 상태 요청/응답 알림 이름 정의
public extension Notification.Name {
    static let voyagerHelperStateRequest = Notification.Name("voyagerHelperStateRequest")
    static let voyagerHelperStateDidUpdate = Notification.Name("voyagerHelperStateDidUpdate")
}

/// Helper 상태 알림 payload key 정의
nonisolated public enum HelperStateUserInfoKey {
    public static let schemaVersion = "schema_version"
    public static let generatedAt = "generated_at"
    public static let helperReady = "helper_ready"
    public static let helperBundleVersion = "helper_bundle_version"
}
