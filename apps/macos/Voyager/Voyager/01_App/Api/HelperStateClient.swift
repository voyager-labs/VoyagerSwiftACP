import ComposableArchitecture
import Foundation
import Logging

public struct HelperState: Sendable, Equatable {
    public let helperReady: Bool
    public let helperBundleVersion: String?
}

public struct HelperStateClient: Sendable {
    public var resolve: @Sendable () async -> HelperState?
    public var observe: @Sendable () -> AsyncStream<HelperState>

    public nonisolated init(
        resolve: @escaping @Sendable () async -> HelperState?,
        observe: @escaping @Sendable () -> AsyncStream<HelperState>,
    ) {
        self.resolve = resolve
        self.observe = observe
    }
}

extension HelperStateClient: DependencyKey {
    public nonisolated static var liveValue: HelperStateClient {
        let resolver = HelperStateResolver()
        return HelperStateClient(
            resolve: {
                await resolver.resolveState()
            },
            observe: {
                AsyncStream { continuation in
                    Task { await resolver.addObserver(continuation) }
                }
            },
        )
    }

    public nonisolated static var testValue: HelperStateClient {
        HelperStateClient(resolve: { nil }, observe: { AsyncStream { $0.finish() } })
    }

    public nonisolated static var previewValue: HelperStateClient {
        HelperStateClient(resolve: { nil }, observe: { AsyncStream { $0.finish() } })
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
    private var stateContinuations: [UUID: AsyncStream<HelperState>.Continuation] = [:]
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

    func addObserver(_ continuation: AsyncStream<HelperState>.Continuation) async {
        let id = UUID()
        stateContinuations[id] = continuation

        if let cachedState {
            continuation.yield(cachedState)
        }

        await ensureObserver()

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
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
        stateContinuations.values.forEach { $0.yield(state) }

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

    private func removeContinuation(id: UUID) {
        stateContinuations[id] = nil
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
           schemaVersion != 3
        {
            return nil
        }

        guard let helperReady = info[HelperStateUserInfoKey.helperReady] as? Bool else {
            return nil
        }

        let helperBundleVersion = info[HelperStateUserInfoKey.helperBundleVersion] as? String
        return HelperState(helperReady: helperReady, helperBundleVersion: helperBundleVersion)
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
}
