@testable import Voyager
import XCTest

/// 헬퍼 감독 정책 — 재시도/쿨다운/백오프 및 상태 리셋 의미론을 검증.
@MainActor
final class HelperSupervisionPolicyTests: XCTestCase {
    /// testFirstThreeAttemptsAllowed 테스트 동작을 검증한다.
    func testFirstThreeAttemptsAllowed() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        XCTAssertEqual(policy.recordRestartAttempt(at: now), .allowed)
        XCTAssertEqual(policy.recordRestartAttempt(at: now.addingTimeInterval(1)), .allowed)
        XCTAssertEqual(policy.recordRestartAttempt(at: now.addingTimeInterval(2)), .allowed)
    }

    /// testFourthAttemptTriggersCooldown 테스트 동작을 검증한다.
    func testFourthAttemptTriggersCooldown() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(1))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(2))

        let decision = policy.recordRestartAttempt(at: now.addingTimeInterval(3))
        if case let .cooldown(activeUntil) = decision {
            XCTAssertEqual(activeUntil, now.addingTimeInterval(3 + 60))
        } else {
            XCTFail("Expected cooldown, got \(decision)")
        }
    }

    /// testCooldownExpiresAfterWindow 테스트 동작을 검증한다.
    func testCooldownExpiresAfterWindow() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(1))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(2))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(3))

        XCTAssertTrue(policy.isInCooldown)

        let afterWindow = now.addingTimeInterval(70)
        XCTAssertFalse(policy.isInCooldown)

        let decision = policy.recordRestartAttempt(at: afterWindow)
        XCTAssertEqual(decision, .allowed)
    }

    /// testGraceWindowBlocksImmediateRetry 테스트 동작을 검증한다.
    func testGraceWindowBlocksImmediateRetry() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)

        let decision = policy.recordRestartAttempt(at: now.addingTimeInterval(2))
        if case let .graceWindow(activeUntil) = decision {
            XCTAssertEqual(activeUntil, now.addingTimeInterval(5))
        } else {
            XCTFail("Expected graceWindow, got \(decision)")
        }
    }

    /// testGraceWindowExpires 테스트 동작을 검증한다.
    func testGraceWindowExpires() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        XCTAssertTrue(policy.isInGraceWindow)

        XCTAssertFalse(policy.isInGraceWindow)
    }

    /// testResetClearsAllState 테스트 동작을 검증한다.
    func testResetClearsAllState() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(1))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(2))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(3))

        XCTAssertTrue(policy.isInCooldown)
        XCTAssertEqual(policy.restartCountInWindow, 4)

        policy.reset()

        XCTAssertFalse(policy.isInCooldown)
        XCTAssertEqual(policy.restartCountInWindow, 0)
        XCTAssertFalse(policy.isInGraceWindow)
    }

    /// testWindowPrunesOldAttempts 테스트 동작을 검증한다.
    func testWindowPrunesOldAttempts() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(1))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(2))

        XCTAssertEqual(policy.restartCountInWindow, 3)

        let afterWindow = now.addingTimeInterval(61)

        let decision = policy.peekDecision(at: afterWindow)
        XCTAssertEqual(decision, .allowed)
    }
}
