@preconcurrency import Foundation

/// Helper 상태를 캐시하고 알림으로 브로드캐스트하는 관리자
@MainActor
final class HelperStateBroadcaster {
    /// DB 초기화/마이그레이션 완료 전에는 false. 완료 후 true로 설정해 메인 앱에 준비 완료를 알린다.
    private var helperFullyReady = false
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// 등록된 알림 옵저버를 정리한다
    deinit {
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// Helper 상태 요청 알림을 구독한다
    func startObservingRequests() {
        guard observer == nil else { return }
        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("voyagerHelperStateRequest"),
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.postCurrentState()
            }
        }
        observer = token
    }

    /// DB 초기화/마이그레이션 완료 후 호출한다. 이후 postCurrentState()는 helperReady: true로 전송한다.
    func markHelperFullyReady() {
        helperFullyReady = true
    }

    /// 현재 상태를 알림으로 전송한다
    func postCurrentState() {
        let payload = buildPayload()
        DistributedNotificationCenter.default().post(
            name: Notification.Name("voyagerHelperStateDidUpdate"),
            object: nil,
            userInfo: payload,
        )
    }

    /// 알림 payload를 생성한다
    private func buildPayload() -> [String: Any] {
        let helperBundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        var payload: [String: Any] = [
            "schema_version": 3,
            "generated_at": Date().timeIntervalSince1970,
            "helper_ready": helperFullyReady,
        ]

        if let helperBundleVersion {
            payload["helper_bundle_version"] = helperBundleVersion
        }

        return payload
    }
}
