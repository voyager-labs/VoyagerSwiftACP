import Foundation

// MARK: - Restart Decision

/// Helper 재시작 결정 결과
public enum RestartDecision: Equatable, Sendable {
    /// 재시작 허용
    case allowed
    /// 쿨다운 중 (재시도 불가)
    case cooldown(activeUntil: Date)
    /// 그레이스 윈도우 내 중복 실행 방지
    case graceWindow(activeUntil: Date)
}

// MARK: - Helper Supervision Policy

/// Helper 재시작 감독 정책
///
/// 60초 윈도우 내 최대 3회 재시작을 허용하고, 초과 시 쿨다운 상태로 전환한다.
/// 그레이스 윈도우(5초) 내 중복 실행을 방지한다.
///
/// ## 정책 상수
/// - `budgetLimit`: 3회 (60초 윈도우 내 허용 재시작 횟수)
/// - `windowDuration`: 60초 (재시작 카운트 윈도우)
/// - `graceWindow`: 5초 (시작 후 중복 실행 방지 윈도우)
/// - `pollInterval`: 2초 (폴링 간격)
///
/// ## 사용 예시
/// ```swift
/// var policy = HelperSupervisionPolicy()
///
/// // 재시작 시도
/// let decision = policy.recordRestartAttempt(at: .now)
/// switch decision {
/// case .allowed:
///     // Helper 시작
/// case .cooldown(let activeUntil):
///     // 쿨다운 대기
/// case .graceWindow:
///     // 이미 시작 중
/// }
/// ```
public struct HelperSupervisionPolicy: Equatable, Sendable {
    // MARK: - Constants

    /// 60초 윈도우 내 허용 재시작 횟수
    public nonisolated(unsafe) static let budgetLimit = 3

    /// 재시작 카운트 윈도우 (초)
    public nonisolated(unsafe) static let windowDuration: TimeInterval = 60

    /// 시작 후 중복 실행 방지 그레이스 윈도우 (초)
    public nonisolated(unsafe) static let graceWindow: TimeInterval = 5

    /// 폴링 간격 (초)
    public nonisolated(unsafe) static let pollInterval: TimeInterval = 2

    // MARK: - Properties

    /// 윈도우 내 재시작 시각 기록
    private var restartAttempts: [Date]

    /// 마지막 시작 시각 (그레이스 윈도우 계산용)
    private var lastStartAt: Date?

    /// 쿨다운 시작 시각
    private var cooldownStartedAt: Date?

    // MARK: - Computed Properties

    /// 현재 윈도우 내 재시작 횟수
    public var restartCountInWindow: Int {
        let now = Date()
        return restartAttempts.count(where: { now.timeIntervalSince($0) <= Self.windowDuration })
    }

    /// 쿨다운 중인지 여부
    public var isInCooldown: Bool {
        guard let cooldownStartedAt else { return false }
        // 쿨다운은 윈도우가 지나면 자동 해제
        return Date().timeIntervalSince(cooldownStartedAt) <= Self.windowDuration
    }

    /// 그레이스 윈도우 중인지 여부
    public var isInGraceWindow: Bool {
        guard let lastStartAt else { return false }
        return Date().timeIntervalSince(lastStartAt) <= Self.graceWindow
    }

    // MARK: - Init

    public nonisolated init(
        restartAttempts: [Date] = [],
        lastStartAt: Date? = nil,
        cooldownStartedAt: Date? = nil,
    ) {
        self.restartAttempts = restartAttempts
        self.lastStartAt = lastStartAt
        self.cooldownStartedAt = cooldownStartedAt
    }

    // MARK: - Methods

    /// 재시작 시도를 기록하고 결정을 반환한다
    ///
    /// - Parameter at: 시도 시각
    /// - Returns: 재시작 결정 (허용/쿨다운/그레이스윈도우)
    public mutating func recordRestartAttempt(at date: Date = Date()) -> RestartDecision {
        // 1. 그레이스 윈도우 체크
        if let lastStartAt,
           date.timeIntervalSince(lastStartAt) <= Self.graceWindow
        {
            return .graceWindow(activeUntil: lastStartAt.addingTimeInterval(Self.graceWindow))
        }

        // 2. 윈도우 정리
        restartAttempts = restartAttempts.filter { date.timeIntervalSince($0) <= Self.windowDuration }

        // 3. 쿨다운 체크
        if isInCooldown {
            let cooldownEnd = cooldownStartedAt?.addingTimeInterval(Self.windowDuration) ?? date
            return .cooldown(activeUntil: cooldownEnd)
        }

        // 4. 예산 체크
        if restartAttempts.count >= Self.budgetLimit {
            // 쿨다운 진입
            cooldownStartedAt = date
            return .cooldown(activeUntil: date.addingTimeInterval(Self.windowDuration))
        }

        // 5. 허용
        restartAttempts.append(date)
        lastStartAt = date

        return .allowed
    }

    /// 쿨다운을 명시적으로 해제한다 (윈도우 경과 후)
    public mutating func clearExpiredCooldown() {
        if let cooldownStartedAt,
           Date().timeIntervalSince(cooldownStartedAt) > Self.windowDuration
        {
            self.cooldownStartedAt = nil
            restartAttempts.removeAll()
        }
    }

    /// 그레이스 윈도우를 명시적으로 해제한다
    public mutating func clearGraceWindow() {
        lastStartAt = nil
    }

    /// 정책을 초기화한다
    public mutating func reset() {
        restartAttempts.removeAll()
        lastStartAt = nil
        cooldownStartedAt = nil
    }
}

// MARK: - Debug Helpers

#if DEBUG
public extension HelperSupervisionPolicy {
    /// 테스트용: 특정 시각 기준으로 결정 조회
    func peekDecision(at date: Date) -> RestartDecision {
        var copy = self
        return copy.recordRestartAttempt(at: date)
    }
}
#endif
