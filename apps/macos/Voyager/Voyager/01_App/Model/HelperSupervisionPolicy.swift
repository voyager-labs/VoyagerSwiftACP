import Foundation

/// Helper 재시작 결정 결과
public enum RestartDecision: Equatable, Sendable {
    /// 재시작 허용
    case allowed
    /// 쿨다운 중 (재시도 불가)
    case cooldown(activeUntil: Date)
    /// 그레이스 윈도우 내 중복 실행 방지
    case graceWindow(activeUntil: Date)
}

/// Helper 재시작 감독 정책
///
/// 60초 윈도우 내 최대 3회 재시작을 허용하고, 초과 시 쿨다운 상태로 전환한다.
/// 그레이스 윈도우(5초) 내 중복 실행을 방지한다.
public struct HelperSupervisionPolicy: Equatable, Sendable {
    /// 60초 윈도우 내 허용 재시작 횟수
    nonisolated(unsafe) public static let budgetLimit = 3

    /// 재시작 카운트 윈도우 (초)
    nonisolated(unsafe) public static let windowDuration: TimeInterval = 60

    /// 시작 후 중복 실행 방지 그레이스 윈도우 (초)
    nonisolated(unsafe) public static let graceWindow: TimeInterval = 5

    /// 윈도우 내 재시작 시각 기록
    public private(set) var restartAttempts: [Date] = []

    /// 마지막 시작 시각 (그레이스 윈도우 계산용)
    private var lastStartAt: Date?

    /// 쿨다운 시작 시각
    private var cooldownStartedAt: Date?

    /// 현재 윈도우 내 재시작 횟수
    nonisolated public var restartCountInWindow: Int {
        let now = Date()
        return restartAttempts.count(where: { now.timeIntervalSince($0) <= Self.windowDuration })
    }

    /// 쿨다운 중인지 여부
    nonisolated public var isInCooldown: Bool {
        guard let cooldownStartedAt else { return false }
        return Date().timeIntervalSince(cooldownStartedAt) <= Self.windowDuration
    }

    /// 그레이스 윈도우 중인지 여부
    nonisolated public var isInGraceWindow: Bool {
        guard let lastStartAt else { return false }
        return Date().timeIntervalSince(lastStartAt) <= Self.graceWindow
    }

    nonisolated public init(
        restartAttempts: [Date] = [],
        lastStartAt: Date? = nil,
        cooldownStartedAt: Date? = nil,
    ) {
        self.restartAttempts = restartAttempts
        self.lastStartAt = lastStartAt
        self.cooldownStartedAt = cooldownStartedAt
    }

    /// 재시작 시도를 기록하고 결정을 반환한다
    nonisolated public mutating func recordRestartAttempt(at date: Date = Date()) -> RestartDecision {
        if let lastStartAt,
           date.timeIntervalSince(lastStartAt) <= Self.graceWindow
        {
            return .graceWindow(activeUntil: lastStartAt.addingTimeInterval(Self.graceWindow))
        }

        restartAttempts = restartAttempts.filter { date.timeIntervalSince($0) <= Self.windowDuration }

        if isInCooldown {
            let cooldownEnd = cooldownStartedAt?.addingTimeInterval(Self.windowDuration) ?? date
            return .cooldown(activeUntil: cooldownEnd)
        }

        if restartAttempts.count >= Self.budgetLimit {
            cooldownStartedAt = date
            return .cooldown(activeUntil: date.addingTimeInterval(Self.windowDuration))
        }

        restartAttempts.append(date)
        lastStartAt = date

        return .allowed
    }

    nonisolated public mutating func reset() {
        restartAttempts.removeAll()
        lastStartAt = nil
        cooldownStartedAt = nil
    }
}

#if DEBUG
public extension HelperSupervisionPolicy {
    /// 테스트용: 특정 시각 기준으로 결정 조회
    func peekDecision(at date: Date) -> RestartDecision {
        var copy = self
        return copy.recordRestartAttempt(at: date)
    }
}
#endif
