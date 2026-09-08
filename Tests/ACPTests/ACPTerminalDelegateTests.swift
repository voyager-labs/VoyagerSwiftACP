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

    // MARK: - Launch Failure Rollback

    /// `Process.run()` throwing after the state was staged must roll the
    /// terminal back so repeated failures cannot leak handles or memory.
    func testFailedCreateRollsBackTerminalState() async throws {
        let delegate = TerminalDelegate()

        // /dev/null exists but is not executable, so `run()` throws at spawn.
        do {
            _ = try await delegate.handleTerminalCreate(
                command: "/dev/null",
                sessionId: "session-rollback",
                args: nil,
                cwd: nil,
                env: nil,
                outputByteLimit: nil,
            )
            XCTFail("expected a launch failure for a non-executable path")
        } catch {
            // expected
        }

        let count = await delegate.activeTerminalCount
        XCTAssertEqual(count, 0, "a failed launch must not retain terminal state")
        await delegate.cleanup()
    }
}

/// Multi-byte UTF-8 output split across pipe chunks must decode as one
/// character instead of being dropped with a failed whole-chunk decode.
final class UTF8AssemblerTests: XCTestCase {
    func testSplitMultibyteCharacterSurvivesChunkBoundary() {
        let assembler = UTF8Assembler()
        let character = "한" // 3-byte UTF-8 sequence
        let bytes = Array(character.utf8)
        XCTAssertGreaterThanOrEqual(bytes.count, 3)

        XCTAssertNil(assembler.decoded(byAppending: Data(bytes.prefix(1))), "an incomplete sequence yields nothing yet")
        let output = assembler.decoded(byAppending: Data(bytes.suffix(from: 1)))
        XCTAssertEqual(output, character)
    }

    func testTrailingIncompleteSequenceIsCarriedAndFlushed() {
        let assembler = UTF8Assembler()
        let bytes = Array("a한b".utf8) // [a, ED 85 9C, b]

        // The multi-byte character is split across two chunks: only the
        // complete prefix decodes, the carried bytes complete it next chunk.
        XCTAssertEqual(assembler.decoded(byAppending: Data(bytes.prefix(3))), "a")
        XCTAssertEqual(assembler.decoded(byAppending: Data([bytes[3]])), "한")
        XCTAssertEqual(assembler.decoded(byAppending: Data([bytes[4]])), "b")
        XCTAssertNil(assembler.flushRemaining())
    }

    func testInvalidBytesDecodeAsReplacementCharactersInline() {
        let assembler = UTF8Assembler()
        XCTAssertEqual(assembler.decoded(byAppending: Data([0x61, 0xFF])), "a\u{FFFD}")
        XCTAssertNil(assembler.flushRemaining())
    }
}
#endif
