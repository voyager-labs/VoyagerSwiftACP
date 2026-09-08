#if os(macOS)
@testable import ACP
import ACPModel
import XCTest

final class ACPTerminalDelegateTests: XCTestCase {
    // MARK: - Output Limits

    /// A negative peer-supplied `outputByteLimit` must fall back to the default
    /// instead of trapping `String.index` inside `appendOutput`.
    func testNegativeOutputByteLimitDoesNotTrap() async throws {
        let delegate = TerminalDelegate()
        let created = try await delegate.handleTerminalCreate(
            command: "/bin/echo",
            sessionId: "session-limit",
            args: ["bounded-output"],
            cwd: nil,
            env: nil,
            outputByteLimit: -1,
        )
        defer { Task { await delegate.cleanup() } }

        _ = try await delegate.handleTerminalWaitForExit(terminalId: created.terminalId, sessionId: "session-limit")

        var output: TerminalOutputResponse?
        for _ in 0 ..< 40 {
            output = try await delegate.handleTerminalOutput(terminalId: created.terminalId, sessionId: "session-limit")
            if let output, !output.output.isEmpty { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let finalOutput = try XCTUnwrap(output)
        XCTAssertTrue(finalOutput.output.contains("bounded-output"))
        XCTAssertFalse(finalOutput.truncated)
    }

    // MARK: - Output Polling

    /// Polling output from a running, silent terminal must return the buffered
    /// snapshot immediately instead of blocking the actor on a pipe read that
    /// competes with the readability handlers.
    func testTerminalOutputReturnsPromptlyWhileProcessRuns() async throws {
        let delegate = TerminalDelegate()
        let created = try await delegate.handleTerminalCreate(
            command: "/bin/sleep",
            sessionId: "session-poll",
            args: ["5"],
            cwd: nil,
            env: nil,
            outputByteLimit: nil,
        )
        defer { Task { await delegate.cleanup() } }

        let startedAt = Date()
        let output = try await delegate.handleTerminalOutput(terminalId: created.terminalId, sessionId: "session-poll")
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 1.0, "output polling must not block on a silent pipe")
        XCTAssertNil(output.exitStatus, "a running terminal has no exit status yet")
        XCTAssertEqual(output.output, "")
    }

    // MARK: - Bounded Teardown

    /// A process that ignores SIGTERM must still be reaped through the
    /// TERM → bounded wait → KILL → bounded wait escalation.
    func testKillEscalatesPastIgnoredTerm() async throws {
        let delegate = TerminalDelegate()
        // `exec` keeps the ignoring process as the direct child; an ignored
        // SIGTERM disposition survives `exec`.
        let created = try await delegate.handleTerminalCreate(
            command: "/bin/sh",
            sessionId: "session-kill",
            args: ["-c", "trap '' TERM; exec sleep 30"],
            cwd: nil,
            env: nil,
            outputByteLimit: nil,
        )
        defer { Task { await delegate.cleanup() } }

        let startedAt = Date()
        _ = try await delegate.handleTerminalKill(terminalId: created.terminalId, sessionId: "session-kill")
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 8.0, "kill must escalate to SIGKILL instead of blocking forever")
        let stillRunning = await delegate.isRunning(terminalId: created.terminalId)
        XCTAssertFalse(stillRunning)
    }
}
#endif
