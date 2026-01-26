import Foundation

// Helper 상태 요청/응답 알림 이름 정의
extension Notification.Name {
    static let voyagerHelperStateRequest = Notification.Name("voyagerHelperStateRequest")
    static let voyagerHelperStateDidUpdate = Notification.Name("voyagerHelperStateDidUpdate")
}

// Helper 상태 알림 payload key 정의
nonisolated enum HelperStateUserInfoKey {
    static let schemaVersion = "schema_version"
    static let generatedAt = "generated_at"
    static let helperReady = "helper_ready"
    static let helperBundleVersion = "helper_bundle_version"
    static let backend = "backend"

    // Backend 상태 영역 key 정의
    enum Backend {
        static let ready = "ready"
        static let pid = "pid"
        static let uptimeSeconds = "uptime_seconds"
        static let endpoint = "endpoint"
    }

    // Endpoint 정보 영역 key 정의
    enum Endpoint {
        static let host = "host"
        static let port = "port"
        static let url = "url"
    }
}
