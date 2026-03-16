@testable import Voyager
import XCTest

final class HelperSupervisionPolicyTests: XCTestCase {
    func testFirstThreeAttemptsAllowed() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        XCTAssertEqual(policy.recordRestartAttempt(at: now), .allowed)
        XCTAssertEqual(policy.recordRestartAttempt(at: now.addingTimeInterval(1)), .allowed)
        XCTAssertEqual(policy.recordRestartAttempt(at: now.addingTimeInterval(2)), .allowed)
    }

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

    func testGraceWindowExpires() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        XCTAssertTrue(policy.isInGraceWindow)

        let afterGrace = now.addingTimeInterval(6)
        XCTAssertFalse(policy.isInGraceWindow)
    }

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

    func testWindowPrunesOldAttempts() {
        var policy = HelperSupervisionPolicy()
        let now = Date()

        _ = policy.recordRestartAttempt(at: now)
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(1))
        _ = policy.recordRestartAttempt(at: now.addingTimeInterval(2))

        XCTAssertEqual(policy.restartCountInWindow, 3)

        let afterWindow = now.addingTimeInterval(61)
        XCTAssertEqual(policy.restartCountInWindow(from: afterWindow), 0)

        let decision = policy.peekDecision(at: afterWindow)
        XCTAssertEqual(decision, .allowed)
    }
}

private extension HelperSupervisionPolicy {
    func restartCountInWindow(from date: Date) -> Int {
        restartAttempts.count { date.timeIntervalSince($0) <= Self.windowDuration }
    }
}
