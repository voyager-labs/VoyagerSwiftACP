import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

public struct HelperEndpoint: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let url: URL
}

public struct HelperState: Sendable, Equatable {
    public struct Backend: Sendable, Equatable {
        public let ready: Bool
        public let pid: Int?
        public let uptimeSeconds: TimeInterval?
        public let endpoint: HelperEndpoint?
    }

    public let helperReady: Bool
    public let backend: Backend
}

public struct HelperStateClient: Sendable {
    public var resolve: @Sendable () async -> HelperState?

    public nonisolated init(resolve: @escaping @Sendable () async -> HelperState?) {
        self.resolve = resolve
    }
}

extension HelperStateClient: DependencyKey {
    public nonisolated static var liveValue: HelperStateClient {
        let resolver = HelperStateResolver()
        return HelperStateClient(resolve: {
            await resolver.resolveState()
        })
    }

    public nonisolated static var testValue: HelperStateClient {
        HelperStateClient(resolve: { nil })
    }

    public nonisolated static var previewValue: HelperStateClient {
        HelperStateClient(resolve: { nil })
    }
}

public extension DependencyValues {
    nonisolated var helperStateClient: HelperStateClient {
        get { self[HelperStateClient.self] }
        set { self[HelperStateClient.self] = newValue }
    }
}

// Helper 상태 요청/응답 흐름을 관리하는 리졸버
private actor HelperStateResolver {
    private let logger = Logger(label: "Voyager")
    private var cachedState: HelperState?
    private var waiters: [CheckedContinuation<HelperState?, Never>] = []
    private var observer: NotificationObserver?
    private var timeoutTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    deinit {
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer.token)
        }
    }

    // Helper 상태를 요청하고 응답을 반환한다
    func resolveState() async -> HelperState? {
        await ensureObserver()
        await sendRequest()

        if let cachedState { return cachedState }

        scheduleTimeoutAndRetry()

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    // 응답 상태를 처리하고 캐시/대기자를 갱신한다
    private func handle(state: HelperState?, userInfoSummary: String) async {
        guard let state else {
            logger.error("Failed to parse helper state notification: \(userInfoSummary)")
            return
        }

        cachedState = state
        cancelTimeouts()
        updateDotenv(state: state)

        if !waiters.isEmpty {
            let currentWaiters = waiters
            waiters.removeAll()
            currentWaiters.forEach { $0.resume(returning: state) }
        }
    }

    // 타임아웃/재시도 타이머를 등록한다
    private func scheduleTimeoutAndRetry() {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.handleTimeout()
        }
    }

    // 1차 타임아웃 처리: 재요청을 예약한다
    private func handleTimeout() async {
        guard cachedState == nil else {
            timeoutTask = nil
            return
        }
        if Task.isCancelled {
            timeoutTask = nil
            return
        }
        logger.warning("Helper state not received within timeout; retrying.")
        timeoutTask = nil
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.sendRequest()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.handleRetryTimeout()
        }
    }

    // 재시도 이후에도 미응답일 때 처리한다
    private func handleRetryTimeout() async {
        guard cachedState == nil else {
            retryTask = nil
            return
        }
        if Task.isCancelled {
            retryTask = nil
            return
        }
        logger.warning("Helper state missing after retry; fallback required.")
        if !waiters.isEmpty {
            let currentWaiters = waiters
            waiters.removeAll()
            currentWaiters.forEach { $0.resume(returning: nil) }
        }
        retryTask = nil
    }

    // 타임아웃/재시도 타이머를 정리한다
    private func cancelTimeouts() {
        timeoutTask?.cancel()
        timeoutTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    // 알림 옵저버를 보장한다
    private func ensureObserver() async {
        guard observer == nil else { return }
        let token = await MainActor.run {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: .voyagerHelperStateDidUpdate,
                object: nil,
                queue: .main,
            ) { [weak self] notification in
                guard let self else { return }
                let userInfo = notification.userInfo
                let state = Self.parseState(from: userInfo)
                let userInfoSummary = Self.describeUserInfo(userInfo)
                Task { await self.handle(state: state, userInfoSummary: userInfoSummary) }
            }
            return NotificationObserver(token: observer)
        }
        observer = token
    }

    // Helper 상태 요청 알림을 전송한다
    private func sendRequest() async {
        await MainActor.run {
            DistributedNotificationCenter.default().post(
                name: .voyagerHelperStateRequest,
                object: nil,
                userInfo: nil,
            )
        }
    }

    // 알림 payload를 HelperState로 파싱한다
    private nonisolated static func parseState(from info: [AnyHashable: Any]?) -> HelperState? {
        let info = info ?? [:]

        if let schemaVersion = Parser.parseInt(from: info[HelperStateUserInfoKey.schemaVersion]),
           schemaVersion != 1
        {
            return nil
        }

        guard let helperReady = info[HelperStateUserInfoKey.helperReady] as? Bool else {
            return nil
        }

        guard let backendInfo = info[HelperStateUserInfoKey.backend] as? [String: Any] else {
            return nil
        }

        guard let backendReady = backendInfo[HelperStateUserInfoKey.Backend.ready] as? Bool else {
            return nil
        }

        let pid = Parser.parseInt(from: backendInfo[HelperStateUserInfoKey.Backend.pid])
        let uptimeSeconds = Parser.parseDouble(from: backendInfo[HelperStateUserInfoKey.Backend.uptimeSeconds])
        let endpoint = parseEndpoint(from: backendInfo[HelperStateUserInfoKey.Backend.endpoint])

        let backend = HelperState.Backend(
            ready: backendReady,
            pid: pid,
            uptimeSeconds: uptimeSeconds,
            endpoint: endpoint,
        )

        return HelperState(helperReady: helperReady, backend: backend)
    }

    // endpoint payload를 파싱한다
    private nonisolated static func parseEndpoint(from value: Any?) -> HelperEndpoint? {
        guard let endpointInfo = value as? [String: Any] else {
            return nil
        }

        guard let host = endpointInfo[HelperStateUserInfoKey.Endpoint.host] as? String else {
            return nil
        }

        guard let port = Parser.parseInt(from: endpointInfo[HelperStateUserInfoKey.Endpoint.port]) else {
            return nil
        }

        if let urlString = endpointInfo[HelperStateUserInfoKey.Endpoint.url] as? String,
           let url = URL(string: urlString)
        {
            return HelperEndpoint(host: host, port: port, url: url)
        }

        let url = URL(string: "http://\(host):\(port)")
        return url.map { HelperEndpoint(host: host, port: port, url: $0) }
    }

    private func updateDotenv(state: HelperState) {
        guard let endpoint = state.backend.endpoint else {
            return
        }

        Dotenv.set(value: endpoint.host, forKey: "PUBLIC_BACKEND_HOST", overwrite: true)
        Dotenv.set(value: String(endpoint.port), forKey: "PUBLIC_BACKEND_PORT", overwrite: true)
        Dotenv.set(value: endpoint.url.absoluteString, forKey: "PUBLIC_BACKEND_URL", overwrite: true)
        logger.info("Backend endpoint updated: \(endpoint.url.absoluteString)")
    }

    // 로그 출력용으로 userInfo 타입 정보를 요약한다
    private nonisolated static func describeUserInfo(_ info: [AnyHashable: Any]?) -> String {
        guard let info else {
            return "userInfo=nil"
        }

        let pairs = info.map { key, value in
            let keyString = String(describing: key)
            let typeName = String(describing: type(of: value))
            return "\(keyString):\(typeName)"
        }
        .sorted()
        .joined(separator: ", ")

        return "userInfo={\(pairs)}"
    }
}

// 알림 옵저버 토큰 래퍼
private struct NotificationObserver: @unchecked Sendable {
    let token: NSObjectProtocol
}

// 숫자형 파싱 유틸 모음
private nonisolated enum Parser {
    // 숫자형 Int 변환 유틸
    static func parseInt(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    // 숫자형 Double 변환 유틸
    static func parseDouble(from value: Any?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let stringValue = value as? String {
            return Double(stringValue)
        }
        return nil
    }
}
