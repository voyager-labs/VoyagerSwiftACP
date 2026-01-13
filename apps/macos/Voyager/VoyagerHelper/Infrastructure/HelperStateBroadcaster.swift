@preconcurrency import Foundation

@MainActor
// Helper 상태를 캐시하고 알림으로 브로드캐스트하는 관리자
final class HelperStateBroadcaster {
    // Backend 상태 캐시용 구조체
    private struct BackendState: Sendable {
        var ready = false
        var pid: Int?
        var host: String?
        var port: Int?
        var startDate: Date?
    }

    private var backendState = BackendState()
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    // 등록된 알림 옵저버를 정리한다
    deinit {
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // Helper 상태 요청 알림을 구독한다
    func startObservingRequests() {
        guard observer == nil else { return }
        let token = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperStateRequest,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.postCurrentState()
            }
        }
        observer = token
    }

    // Backend 준비 완료 시 상태를 갱신한다
    func updateBackendReady(host: String, port: Int, pid: Int, startDate: Date) {
        backendState.ready = true
        backendState.pid = pid
        backendState.host = host
        backendState.port = port
        backendState.startDate = startDate
    }

    // Backend 종료 시 상태를 초기화한다
    func markBackendStopped() {
        backendState.ready = false
        backendState.pid = nil
        backendState.host = nil
        backendState.port = nil
        backendState.startDate = nil
    }

    // 현재 상태를 알림으로 전송한다
    func postCurrentState() {
        let payload = buildPayload()
        DistributedNotificationCenter.default().post(
            name: .voyagerHelperStateDidUpdate,
            object: nil,
            userInfo: payload,
        )
    }

    // 알림 payload를 생성한다
    private func buildPayload() -> [String: Any] {
        var backend: [String: Any] = [
            HelperStateUserInfoKey.Backend.ready: backendState.ready,
        ]

        if let pid = backendState.pid {
            backend[HelperStateUserInfoKey.Backend.pid] = pid
        }

        if let startDate = backendState.startDate {
            let uptime = Date().timeIntervalSince(startDate)
            backend[HelperStateUserInfoKey.Backend.uptimeSeconds] = uptime
        }

        if let host = backendState.host, let port = backendState.port {
            let url = "http://\(host):\(port)"
            backend[HelperStateUserInfoKey.Backend.endpoint] = [
                HelperStateUserInfoKey.Endpoint.host: host,
                HelperStateUserInfoKey.Endpoint.port: port,
                HelperStateUserInfoKey.Endpoint.url: url,
            ]
        }

        return [
            HelperStateUserInfoKey.schemaVersion: 1,
            HelperStateUserInfoKey.generatedAt: Date().timeIntervalSince1970,
            HelperStateUserInfoKey.helperReady: true,
            HelperStateUserInfoKey.backend: backend,
        ]
    }
}
