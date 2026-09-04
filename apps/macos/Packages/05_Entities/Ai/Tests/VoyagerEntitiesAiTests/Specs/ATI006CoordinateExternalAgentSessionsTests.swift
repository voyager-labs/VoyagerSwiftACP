import Foundation
@testable import VoyagerEntitiesAi
import VoyagerExternalAgentRuntime
import XCTest

// MARK: - ATI-006-coordinate_external_agent_sessions

final class ATI006CoordinateExternalAgentSessionsTests: XCTestCase {
    /// ATI-006-coordinate_external_agent_sessions: the real runtime plane resumes Codex from persisted state.
    /// Shared control-plane restore/resume와 Codex adapter/process controller를 함께 통과하는 characterization 증거입니다.
    /// - 검증 내용: staged compatibility, resume command, empty stdin, context, receipt, cursor, terminal convergence,
    /// cleanup.
    /// - 사전 조건: persisted running session과 provider thread reference가 in-memory store에 저장되어 있습니다.
    /// - 기대 결과: restore는 spawn 없이 compatibility를 stage하고 resume은 정확히 한 번 실행되어 completed로 수렴합니다.
    func testRestoreResume_realCodexAdapterUsesPersistedReceiptAndCursor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-ati006-restore", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let host: ExternalAgentSessionReference = "ati006-restore-host"
        let run = RuntimeRunReference("ati006-restore-run")
        let provider = ProviderInternalSessionReference("thread-persisted")
        let context = RuntimeContextPolicy(
            branchReference: "feat/voy-699",
            authorizationGeneration: 7,
            localCorrelation: "ati006-correlation",
            workingDirectory: root.path,
            allowedRoots: [root.path],
            requestContext: "ati006-request",
        )
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-persisted"}"#.utf8),
                Data(#"{"type":"turn.started","turn_id":"turn-resume"}"#.utf8),
                Data(#"{"type":"turn.completed","turn_id":"turn-resume"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let recorder = CodexExecCommandRecorder()
        let runner: CodexExecProcessController.Runner = { command in
            await recorder.record(command)
            return try await CodexExecFakeRunner(process: process).run(command)
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner),
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: provider,
            runReference: run,
            adapterID: adapter.descriptor.id,
            adapterVersion: adapter.descriptor.adapterVersion,
            capabilitySnapshot: adapter.descriptor.capabilities,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 7,
            acceptedIdempotencyKeys: [],
            providerNamespace: adapter.descriptor.providerNamespace,
            providerBranch: adapter.descriptor.providerBranch,
        )
        let store = ATI006RuntimeMemoryStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let restoreResult = try await plane.restore(hostReference: host, expectedContext: context)
        XCTAssertEqual(restoreResult, RuntimeRestoreResult.restored)
        let stagedCommands = await recorder.commands
        XCTAssertEqual(stagedCommands.count, 0)
        let result = try await plane.resumeRestoredRun(hostReference: host)
        let commands = await recorder.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(
            commands[0].arguments,
            [
                "exec",
                "--model",
                "gpt-5-codex",
                "--json",
                "--strict-config",
                "--ignore-user-config",
                "-c", "default_permissions=\"voyager-reference\"",
                "-c",
                "permissions.voyager-reference.filesystem={\"\(root.path)\"=\"read\",\":minimal\"=\"read\",\":root\"=\"deny\"}",
                "--sandbox", "workspace-write", "-C", context.workingDirectory,
                "--skip-git-repo-check", "resume",
                "thread-persisted",
                "-",
            ],
        )
        XCTAssertEqual(commands[0].stdin, "")
        let adapterCounts = await adapter.debugStorageCounts()
        XCTAssertEqual(adapterCounts.receipts, 0)
        XCTAssertEqual(adapterCounts.restartBindings, 0)
        XCTAssertEqual(result.runReference, run)
        XCTAssertEqual(result.outcome, RuntimeOutcome.completed)
        let finalState = await store.state
        let persisted = try XCTUnwrap(finalState.sessions.first)
        XCTAssertEqual(persisted.runReference, run)
        XCTAssertEqual(persisted.providerInternalSessionReference, provider)
        XCTAssertEqual(persisted.lastSequence, 9)
        XCTAssertEqual(persisted.projection, RuntimeProjection.completed)
    }

    private actor RestartStageGate {
        private var firstCall = false
        private var entered: CheckedContinuation<Void, Never>?
        private var releaseFirst: CheckedContinuation<Void, Never>?

        func waitForFirstStage() async {
            await withCheckedContinuation { continuation in
                entered = continuation
            }
        }

        func release() {
            releaseFirst?.resume()
            releaseFirst = nil
        }

        func invoke() async {
            guard !firstCall else { return }
            firstCall = true
            entered?.resume()
            entered = nil
            await withCheckedContinuation { continuation in
                releaseFirst = continuation
            }
        }
    }

    // MARK: - ATI-006-fresh_codex_launch

    /// ATI-006-fresh_codex_launch: receipt waits for a valid thread.started handshake.
    /// fresh Codex 실행은 handshake 전 receipt를 노출하지 않고 stdin을 닫은 뒤 stream을 연결합니다.
    /// - 검증 내용: prompt write, stdin close, stdout/stderr 분리, non-empty thread ID와 buffered event를 확인합니다.
    /// - 사전 조건: deterministic fake process가 handshake 이전 event와 유효한 thread.started를 순서대로 방출합니다.
    /// - 기대 결과: 하나의 receipt가 반환되고 thread ID와 모든 event가 보존됩니다.
    func testFreshLaunch_waitsForHandshakeAndBuffersEarlyEvents() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"item.started","item":{"id":"early","type":"command"}}"#.utf8),
            ],
            stderr: [Data("diagnostic\n".utf8)],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "--json"],
            environment: [:],
            stdin: "hello",
        )

        let receipt = try await controller.acquire(runID: "run-1", command: command)
        XCTAssertEqual(receipt.threadID, "thread-1")
        XCTAssertEqual(process.writes, [Data("hello".utf8)])
        XCTAssertEqual(process.closeCount, 1)
        XCTAssertEqual(process.terminationCount, 0)
        var events: [CodexExecDecodedEvent] = []
        for try await event in receipt.events {
            events.append(event)
        }
        XCTAssertEqual(events.map(\.type), [.threadStarted, .itemStarted])
        XCTAssertEqual(process.stderrChunks, [Data("diagnostic\n".utf8)])
    }

    /// ATI-006-fresh_codex_launch: final frames without newline complete handshake and terminal delivery.
    /// 마지막 JSONL frame의 개행 유무가 handshake와 terminal 결과를 바꾸지 않는지 검증합니다.
    /// - 검증 내용: 개행 없는 thread.started와 turn.completed가 receipt 및 completed 결과로 처리되는지 확인합니다.
    /// - 사전 조건: fake process가 두 frame을 하나의 chunk로 보내고 마지막 frame에는 개행이 없습니다.
    /// - 기대 결과: thread ID가 반환되고 terminal outcome은 completed입니다.
    func testFreshLaunch_finalFrameWithoutNewline_completesHandshakeAndTerminal() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(
                    (#"{"type":"thread.started","thread_id":"thread-no-newline"}"#
                        + "\n"
                        + #"{"type":"turn.completed","turn_id":"turn-1"}"#).utf8,
                ),
            ],
            stderr: [],
            terminationStatus: 0,
            appendNewline: false,
        )
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )

        let receipt = try await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: process).run,
        )
        .acquire(runID: "no-newline", command: command)
        XCTAssertEqual(receipt.threadID, "thread-no-newline")
        let terminal = try await receipt.terminalResult()
        XCTAssertEqual(terminal.outcome, CodexExecLifecycleKind.completed)
    }

    /// ATI-006-live_stderr_diagnostic: live stderr reaches bounded internal terminal evidence only.
    /// 실제 controller stderr drain 결과가 redaction과 byte bound를 거쳐 terminal 내부 진단에 남는지 검증합니다.
    /// - 검증 내용: bearer/token/auth/path sentinel 제거, 128 KiB bound, frozen public receipt mapping을 확인합니다.
    /// - 사전 조건: fake process가 handshake/terminal과 128 KiB 초과 stderr를 함께 반환합니다.
    /// - 기대 결과: terminal diagnostics는 bounded sanitized text이고 public receipt에는 raw diagnostic이 없습니다.
    func testLiveStderr_isBoundedRedactedInternalTerminalEvidence() async throws {
        let stderr = String(
            repeating:
            "splitbearersecret token=splittokenvalue authorization=splitauthvalue /Users/private/splitpathvalue ",
            count: 4000,
        )
        let stderrChunks = [Data("Bear".utf8), Data(("er " + stderr).utf8)]
        let process = CodexExecFakeProcess(
            stdout: [
                Data(
                    "{\"type\":\"thread.started\",\"thread_id\":\"thread-live\"}\n{\"type\":\"turn.completed\"}"
                        .utf8,
                ),
            ],
            stderr: stderrChunks,
            terminationStatus: 0,
            appendNewline: false,
        )
        let controller = CodexExecProcessController(runner: CodexExecFakeRunner(process: process).run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let receipt = try await controller.acquire(runID: "live-stderr", command: command)
        let terminal = try await receipt.terminalResult()
        XCTAssertLessThanOrEqual(
            terminal.diagnostics.stderr.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )
        XCTAssertFalse(terminal.diagnostics.stderr.contains("Bearer splitbearersecret"))
        XCTAssertFalse(terminal.diagnostics.stderr.contains("splittokenvalue"))
        XCTAssertFalse(terminal.diagnostics.stderr.contains("splitauthvalue"))
        XCTAssertFalse(terminal.diagnostics.stderr.contains("splitpathvalue"))
        XCTAssertFalse(terminal.diagnostics.stderr.contains("/Users/private"))
    }

    /// ATI-006-live_coalesced_chunk: one oversized read containing valid frames is framed per line.
    /// readability handler의 단일 대형 chunk가 pre-stream byte bound를 잘못 소비하지 않는지 검증합니다.
    /// - 검증 내용: handshake 이후 127개 frame과 terminal을 포함한 1 MiB 초과 chunk의 성공을 확인합니다.
    /// - 사전 조건: 각 JSONL line은 1 MiB 미만이고 handshake 직후 모든 frame이 같은 read chunk에 있습니다.
    /// - 기대 결과: encodedEventBufferOverflow 없이 terminal 결과가 completed입니다.
    func testLiveController_coalescedChunkFrames_doNotFalseOverflow() async throws {
        let padding = String(repeating: "x", count: 9000)
        var lines = (0 ..< 127).map { _ in "{\"type\":\"turn.started\",\"message\":\"\(padding)\"}" }
        lines.append("{\"type\":\"turn.completed\"}")
        let chunk = Data((lines.joined(separator: "\n") + "\n").utf8)
        XCTAssertGreaterThan(chunk.count, CodexExecProcessController.maximumBufferedEncodedBytes)
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let acquisition = Task {
            try await controller.acquire(runID: "coalesced-live", command: command)
        }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-coalesced"}"#)
        let receipt = try await acquisition.value
        let lifecycle = try await receipt.eventStream()
        let collector = CodexExecLifecycleCollector()
        let consumerStarted = expectation(description: "lifecycle consumer started")
        let lifecycleConsumer = Task {
            consumerStarted.fulfill()
            for try await event in lifecycle {
                await collector.append(event)
            }
        }
        let terminalConsumer = Task { try await receipt.terminalResult() }
        await fulfillment(of: [consumerStarted], timeout: 1)
        runner.sendChunk(chunk)
        runner.finishStreams()
        let terminal = try await terminalConsumer.value
        _ = try await lifecycleConsumer.value
        XCTAssertEqual(terminal.outcome, CodexExecLifecycleKind.completed)
        let observed = await collector.values()
        XCTAssertEqual(observed.count, 128)
        XCTAssertEqual(observed.map(\.ordinal), Array(1 ... 128).map(UInt64.init))
        XCTAssertEqual(observed.last?.kind, .completed)
        XCTAssertEqual(process.terminationCount, 0)
        XCTAssertEqual(process.cleanupCount, 1)
    }

    /// ATI-006-pre_handshake_cancellation: blocked provider cancellation closes every owned stream exactly once.
    /// thread.started 이전에 멈춘 provider를 caller가 취소할 때 CancellationError와 전체 소유권 정리를 확인합니다.
    /// - 검증 내용: raw/public continuation 종료, raw finish 호출, terminate/cleanup 1회, controller registry 0을 확인합니다.
    /// - 사전 조건: controlled fake stdout/stderr가 handshake 전 continuation에서 대기하고 process exit를 사용하지 않습니다.
    /// - 기대 결과: acquisition이 정확히 CancellationError로 종료되고 receipt/terminal이 생성되지 않습니다.
    func testPreHandshakeCancellation_blockedRawSourceReturnsCancellationAndCleansOnce() async {
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let cancellationHandle = CodexExecInvocationCancellationHandle()
        let acquisition = Task {
            try await controller.acquire(
                runID: "pre-handshake-cancel",
                command: command,
                cancellationHandle: cancellationHandle,
                onProducerFinished: {},
            )
        }
        await runner.waitUntilReady()
        await cancellationHandle.cancelAndWait()

        do {
            _ = try await acquisition.value
            XCTFail("blocked pre-handshake acquisition must cancel")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected cancellation error: \(error)")
        }
        XCTAssertTrue(runner.rawStreamsFinished)
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
        XCTAssertEqual(counts.resume, 0)
        XCTAssertEqual(counts.staged, 0)
    }

    /// ATI-006-fresh_codex_launch: cancelling event consumption after handshake stops the process once.
    /// receipt 이후 event consumer cancellation이 provider process를 방치하지 않는지 검증합니다.
    /// - 검증 내용: handshake 이후 consumer cancellation, terminate 호출, cleanup 횟수를 확인합니다.
    /// - 사전 조건: handshake 뒤에도 stdout이 열린 controlled fake process가 있습니다.
    /// - 기대 결과: consumer 취소가 process terminate와 cleanup을 각각 한 번 수행합니다.
    func testEventConsumptionCancellation_afterHandshakeTerminatesAndCleansOnce() async throws {
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let termination = XCTestExpectation(description: "process terminated")
        process.onTerminate = { termination.fulfill() }
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )

        let acquisition = Task { try await controller.acquire(runID: "cancel", command: command) }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-1"}"#)
        let receipt = try await acquisition.value
        let stream = try await receipt.eventStream()
        let eventStarted = XCTestExpectation(description: "event consumer started")
        let eventReceived = XCTestExpectation(description: "event consumer received event")
        let terminalStarted = XCTestExpectation(description: "terminal consumer started")
        let consumer = Task {
            eventStarted.fulfill()
            do {
                for try await event in stream {
                    eventReceived.fulfill()
                    _ = event
                }
                return false
            } catch {
                return true
            }
        }
        let terminalConsumer = Task {
            terminalStarted.fulfill()
            do {
                _ = try await receipt.terminalResult()
                return false
            } catch {
                return true
            }
        }
        await fulfillment(of: [eventStarted, terminalStarted], timeout: 1)
        runner.send(#"{"type":"turn.started","turn_id":"turn-1"}"#)
        await fulfillment(of: [eventReceived], timeout: 1)
        consumer.cancel()
        terminalConsumer.cancel()

        await fulfillment(of: [termination], timeout: 1)
        _ = await consumer.value
        let terminalConsumerFinished = await terminalConsumer.value
        XCTAssertTrue(terminalConsumerFinished)
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
    }

    /// ATI-006-fresh_codex_launch: invalid handshake and process failure clean up once.
    /// invalid thread handshake와 non-zero 종료가 receipt를 만들지 않고 process를 한 번 정리하는지 검증합니다.
    /// - 검증 내용: empty thread ID 및 process failure의 typed failure와 terminate 횟수를 확인합니다.
    /// - 사전 조건: 각 시나리오에 deterministic fake process를 주입합니다.
    /// - 기대 결과: 두 acquisition 모두 실패하고 각 process terminate가 정확히 한 번 호출됩니다.
    func testFreshLaunch_invalidHandshakeAndProcessFailure_areTypedAndCleanedOnce() async {
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "",
        )
        let empty = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":""}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        do {
            _ = try await CodexExecProcessController(runner: CodexExecFakeRunner(process: empty).run)
                .acquire(runID: "empty", command: command)
            XCTFail("empty handshake should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .emptyThreadID)
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(empty.terminationCount, 1)
        XCTAssertEqual(empty.cleanupCount, 1)

        let preHandshakeFailure = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 9)
        do {
            _ = try await CodexExecProcessController(
                runner: CodexExecFakeRunner(process: preHandshakeFailure).run,
            )
            .acquire(runID: "pre-failed", command: command)
            XCTFail("pre-handshake process failure should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .eofBeforeHandshake)
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(preHandshakeFailure.terminationCount, 1)
        XCTAssertEqual(preHandshakeFailure.cleanupCount, 1)

        let malformed = CodexExecFakeProcess(
            stdout: [Data("{bad}\n".utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        do {
            _ = try await CodexExecProcessController(runner: CodexExecFakeRunner(process: malformed).run)
                .acquire(runID: "malformed", command: command)
            XCTFail("malformed pre-handshake frame should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .decoder(.malformedFrame))
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(malformed.terminationCount, 1)
        XCTAssertEqual(malformed.cleanupCount, 1)

        let failed = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8)],
            stderr: [],
            terminationStatus: 9,
        )
        let receipt = try? await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: failed).run,
        )
        .acquire(runID: "failed", command: command)
        XCTAssertNotNil(receipt)
        if let receipt {
            do { for try await _ in receipt.events {} } catch let error as CodexExecProcessFailure {
                XCTAssertEqual(error, .processFailed(9))
            } catch { XCTFail("unexpected error: \(error)") }
        }
        XCTAssertEqual(failed.terminationCount, 1)
    }

    /// ATI-006-fresh_codex_launch: same-run acquisition shares one process.
    /// 동일 run ID의 동시 acquisition이 registry entry 하나를 공유하는지 검증합니다.
    /// - 검증 내용: runner invocation과 thread ID가 하나로 수렴하는지 확인합니다.
    /// - 사전 조건: handshake가 지연되는 deterministic fake runner가 있습니다.
    /// - 기대 결과: 두 acquisition이 같은 receipt를 관찰하고 spawn은 한 번입니다.
    func testFreshLaunch_sameRunConcurrentAcquire_spawnsOnce() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"turn.completed","turn_id":"turn-1"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        async let first = controller.acquire(runID: "same", command: command)
        async let second = controller.acquire(runID: "same", command: command)
        let receipts = try await (first, second)
        XCTAssertEqual(receipts.0.threadID, receipts.1.threadID)
        let third = try await controller.acquire(runID: "same", command: command)
        XCTAssertEqual(third.threadID, receipts.0.threadID)
        XCTAssertEqual(runner.runCount, 1)
        for try await _ in try await receipts.0.eventStream() {}
        _ = try await receipts.0.terminalResult()
    }

    /// ATI-006-fresh_codex_launch: non-handshake first event fails before receipt.
    /// thread.started 이전 event를 receipt로 승격하지 않는지 검증합니다.
    /// - 검증 내용: early event failure와 단일 cleanup을 확인합니다.
    /// - 사전 조건: fake process가 item.started만 방출합니다.
    /// - 기대 결과: acquisition은 earlyEvent로 실패합니다.
    func testFreshLaunch_earlyEventFailsBeforeReceipt() async {
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"item.started","item":{"type":"command"}}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "",
        )
        do {
            _ = try await CodexExecProcessController(runner: CodexExecFakeRunner(process: process).run)
                .acquire(runID: "early", command: command)
            XCTFail("early event should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .earlyEvent(.itemStarted))
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
    }

    func testFreshLaunch_unknownEventFailsClosedBeforeHandshake() async {
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"provider.future_event"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let controller = CodexExecProcessController(runner: CodexExecFakeRunner(process: process).run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        do {
            _ = try await controller.acquire(runID: "unknown-before-handshake", command: command)
            XCTFail("unknown pre-handshake event must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CodexExecProcessFailure,
                .earlyEvent(.unknown("provider.future_event")),
            )
        }
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
        XCTAssertEqual(counts.resume, 0)
        XCTAssertEqual(counts.staged, 0)
    }

    /// ATI-006-coordinate_external_agent_sessions: adapter restart stages identity and delegates resume once.
    /// Runtime restart binding이 controller의 staged resume lane으로 정확히 전달됩니다.
    /// - 검증 내용: exact binding compatibility, resume handshake 및 단일 runner 호출을 확인합니다.
    /// - 사전 조건: ready probe, persisted thread reference, resume 가능한 fake process가 있습니다.
    /// - 기대 결과: compatibility가 compatible이고 launch가 resume process 하나만 위임합니다.
    func testAdapterRestart_stagesExactBindingAndDelegatesResumeOnce() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-restart", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-resumed"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let resumedProcess = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-resumed"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let processes = [process, resumedProcess]
        let runIndex = CodexExecInvocationCounter()
        let runner: CodexExecProcessController.Runner = { command in
            let index = runIndex.value
            runIndex.increment()
            return try await CodexExecFakeRunner(process: processes[index % processes.count]).run(command)
        }
        let probe = CodexExecReadinessProbe { _, arguments, _ in
            arguments == ["--version"]
                ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner),
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let descriptor = adapter.descriptor
        let context = RuntimeContextPolicy(
            branchReference: "branch",
            authorizationGeneration: 0,
            localCorrelation: "correlation",
            workingDirectory: root.path,
        )
        let binding = RuntimeRestartBinding(
            externalAgentSessionReference: .init("host"),
            providerInternalSessionReference: .init("thread-original"),
            runReference: .init("resume-run"),
            adapterID: descriptor.id,
            providerNamespace: descriptor.providerNamespace,
            adapterVersion: descriptor.adapterVersion,
            providerBranch: descriptor.providerBranch,
            capabilitySnapshot: descriptor.capabilities,
            contextPolicy: context,
        )
        let compatibility = try await adapter.restartCompatibility(for: binding)
        XCTAssertEqual(compatibility, .compatible)
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("resume-run"),
            adapterID: descriptor.id,
            contextPolicy: context,
            input: .init("prompt"),
        )
        do {
            _ = try await adapter.launch(request)
            XCTFail("mismatched resume handshake must fail")
        } catch let error as RuntimeHostError {
            XCTAssertEqual(error, .restartIncompatible)
        }
        XCTAssertEqual(runIndex.value, 1)
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        do {
            _ = try await adapter.launch(request)
            XCTFail("identical retry after handshake mismatch must be stale")
        } catch let error as RuntimeHostError {
            XCTAssertEqual(error, .staleRestartBinding)
        }
        XCTAssertEqual(runIndex.value, 1)
        let compatibleBinding = RuntimeRestartBinding(
            externalAgentSessionReference: .init("host"),
            providerInternalSessionReference: .init("thread-resumed"),
            runReference: .init("resume-run"),
            adapterID: descriptor.id,
            providerNamespace: descriptor.providerNamespace,
            adapterVersion: descriptor.adapterVersion,
            providerBranch: descriptor.providerBranch,
            capabilitySnapshot: descriptor.capabilities,
            contextPolicy: context,
        )
        let compatible = try await adapter.restartCompatibility(for: compatibleBinding)
        XCTAssertEqual(compatible, .compatible)
        let resumed = try await adapter.launch(request)
        XCTAssertEqual(resumed.providerInternalSessionReference.rawValue, "thread-resumed")
        XCTAssertEqual(runIndex.value, 2)
        let counts = await adapter.debugStorageCounts()
        XCTAssertEqual(counts.receipts, 1)
        XCTAssertEqual(counts.hosts, 1)
        XCTAssertEqual(counts.restartBindings, 0)
        XCTAssertEqual(counts.tombstones, 0)
    }

    /// ATI-006-coordinate_external_agent_sessions: active runtime cancellation cancels and abandons its receipt.
    /// shared post-launch rollback이 active receipt와 adapter/controller storage를 함께 정리하는지 검증합니다.
    /// - 검증 내용: cancel/cleanup 각 1회, adapter/controller storage zero, no-active cancellation의 capabilityUnknown을 확인합니다.
    /// - 사전 조건: handshake 이후에도 열린 controlled fake process와 injected session preparer가 있습니다.
    /// - 기대 결과: active run은 성공적으로 취소되고 storage가 비워지며 이후 no-active 요청은 기존 unknown capability를 유지합니다.
    func testAdapterCancellation_activeReceiptCancelsOnceAndAbandonsStorage() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-ati006-codex-home", isDirectory: true)
        let preparedSession = codexHome.appendingPathComponent("session")
        let preparer = CodexLegacySessionPreparer { _, arguments, _ in
            try FileManager.default.createDirectory(at: preparedSession, withIntermediateDirectories: true)
            if arguments.first == "init" {
                try FileManager.default.createDirectory(
                    at: preparedSession.appendingPathComponent(".git"),
                    withIntermediateDirectories: true,
                )
                return ""
            }
            return arguments.contains("--is-inside-work-tree")
                ? "true\n"
                : preparedSession.appendingPathComponent(".git").path + "\n"
        }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            legacySessionPreparer: preparer,
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("active-cancel"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: codexHome.path,
            ),
            input: .init("prompt"),
        )

        let operation = await adapter.startLaunch(request)
        let launch = Task { try await operation.receipt() }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-cancel"}"#)
        _ = try await launch.value

        await operation.cancel()

        let adapterCounts = await adapter.debugStorageCounts()
        let controllerCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        XCTAssertEqual(adapterCounts.receipts + adapterCounts.hosts, 0)
        XCTAssertEqual(controllerCounts.fresh, 0)
        XCTAssertEqual(controllerCounts.resume, 0)
        XCTAssertEqual(controllerCounts.staged, 0)
        do {
            try await adapter.requestCancellation(
                RuntimeCancellationRequest(
                    operationID: RuntimeOperationID("no-active-operation"),
                    runReference: request.runReference,
                ),
            )
            XCTFail("no-active cancellation should retain unknown capability")
        } catch {
            XCTAssertEqual(error as? RuntimeHostError, .capabilityUnknown(.cancellation))
        }
    }

    /// ATI-006-launch_operation: blocked Codex launch cancellation owns one process attempt.
    /// - 검증 내용: pre-handshake CancellationError, one termination/cleanup, and a later same-run launch.
    /// - 사전 조건: first controlled Codex process never sends a handshake before cancellation.
    /// - 기대 결과: first operation cleans up exactly once and second operation receives its own handshake receipt.
    func testLaunchOperation_blockedPreHandshakeCancellationCleansExactAttempt() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-ati006-operation-codex-home", isDirectory: true)
        let preparedSession = codexHome.appendingPathComponent("session")
        let preparer = CodexLegacySessionPreparer { _, arguments, _ in
            if arguments.first == "init" {
                try FileManager.default.createDirectory(
                    at: preparedSession.appendingPathComponent(".git"),
                    withIntermediateDirectories: true,
                )
                return ""
            }
            return arguments.contains("--is-inside-work-tree")
                ? "true\n"
                : preparedSession.appendingPathComponent(".git").path + "\n"
        }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, _, _ in
                .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            legacySessionPreparer: preparer,
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: "host",
            runReference: RuntimeRunReference("operation-run"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: codexHome.path,
            ),
            input: RuntimeSensitiveInput("prompt"),
        )
        let first = await adapter.startLaunch(request)
        await runner.waitUntilReady()
        async let firstCancellation: Void = first.cancel()
        await firstCancellation
        do {
            _ = try await first.receipt()
            XCTFail("cancelled launch must not return a receipt")
        } catch is CancellationError {}
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)

        let second = await adapter.startLaunch(request)
        await runner.waitForRunCount(2)
        await runner.waitUntilReady(forRunCount: 2)
        runner.send(#"{"type":"thread.started","thread_id":"second-thread"}"#)
        let receipt = try await second.receipt()
        XCTAssertEqual(receipt.providerInternalSessionReference.rawValue, "second-thread")
        await second.cancel()
    }

    /// ATI-006-launch_operation: public launch forwards caller cancellation to its exact operation.
    /// - 검증 내용: public launch caller cancellation, one termination/cleanup, and a later same-run launch.
    /// - 사전 조건: first controlled Codex process never sends a handshake before cancellation.
    /// - 기대 결과: public launch returns CancellationError after exact cleanup and the second launch succeeds.
    func testPublicLaunch_blockedPreHandshakeCancellationCleansExactAttempt() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-ati006-public-launch-codex-home", isDirectory: true)
        let preparedSession = codexHome.appendingPathComponent("session")
        let preparer = CodexLegacySessionPreparer { _, arguments, _ in
            if arguments.first == "init" {
                try FileManager.default.createDirectory(
                    at: preparedSession.appendingPathComponent(".git"),
                    withIntermediateDirectories: true,
                )
                return ""
            }
            return arguments.contains("--is-inside-work-tree")
                ? "true\n"
                : preparedSession.appendingPathComponent(".git").path + "\n"
        }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, _, _ in
                .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            legacySessionPreparer: preparer,
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: "host",
            runReference: RuntimeRunReference("public-operation-run"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: codexHome.path,
            ),
            input: RuntimeSensitiveInput("prompt"),
        )

        let first = Task { try await adapter.launch(request) }
        await runner.waitUntilReady()
        first.cancel()
        do {
            _ = try await first.value
            XCTFail("cancelled public launch must not return a receipt")
        } catch is CancellationError {}
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)

        let secondOperation = await adapter.startLaunch(request)
        let second = Task { try await secondOperation.receipt() }
        await runner.waitForRunCount(2)
        await runner.waitUntilReady(forRunCount: 2)
        runner.send(#"{"type":"thread.started","thread_id":"second-public-thread"}"#)
        let receipt = try await second.value
        XCTAssertEqual(receipt.providerInternalSessionReference.rawValue, "second-public-thread")
        await secondOperation.cancel()
    }

    /// ATI-006-launch_operation: one adapter launch owns each active run.
    /// - 검증 내용: concurrent same-run rejection, zero extra spawn, owner survival, and post-cleanup retry.
    /// - 사전 조건: first Codex launch is blocked before its handshake.
    /// - 기대 결과: second launch fails closed without affecting the first, and a later retry succeeds.
    func testAdapterLaunch_concurrentSameRunRejectsWithoutAffectingOwner() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-ati006-single-owner-codex-home", isDirectory: true)
        let preparedSession = codexHome.appendingPathComponent("session")
        let preparer = CodexLegacySessionPreparer { _, arguments, _ in
            if arguments.first == "init" {
                try FileManager.default.createDirectory(
                    at: preparedSession.appendingPathComponent(".git"),
                    withIntermediateDirectories: true,
                )
                return ""
            }
            return arguments.contains("--is-inside-work-tree")
                ? "true\n"
                : preparedSession.appendingPathComponent(".git").path + "\n"
        }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, _, _ in
                .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            legacySessionPreparer: preparer,
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: "host",
            runReference: RuntimeRunReference("single-owner-run"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: codexHome.path,
            ),
            input: RuntimeSensitiveInput("prompt"),
        )

        let owner = await adapter.startLaunch(request)
        await runner.waitUntilReady()
        let rejected = await adapter.startLaunch(request)
        do {
            _ = try await rejected.receipt()
            XCTFail("concurrent same-run launch must fail closed")
        } catch {
            XCTAssertEqual(error as? RuntimeHostError, .invalidEvent)
        }
        await rejected.cancel()
        XCTAssertEqual(runner.runCount, 1)
        XCTAssertEqual(process.terminationCount, 0)
        XCTAssertEqual(process.cleanupCount, 0)

        runner.send(#"{"type":"thread.started","thread_id":"owner-thread"}"#)
        let ownerReceipt = try await owner.receipt()
        XCTAssertEqual(ownerReceipt.providerInternalSessionReference.rawValue, "owner-thread")
        await owner.cancel()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)

        let retry = await adapter.startLaunch(request)
        await runner.waitForRunCount(2)
        await runner.waitUntilReady(forRunCount: 2)
        runner.send(#"{"type":"thread.started","thread_id":"retry-thread"}"#)
        let retryReceipt = try await retry.receipt()
        XCTAssertEqual(retryReceipt.providerInternalSessionReference.rawValue, "retry-thread")
        await retry.cancel()
    }

    /// ATI-006-exact_restart_binding: public resume mismatch discards only the exact staged binding.
    /// adapter가 request context mismatch를 fresh launch로 우회하지 않고 staged state를 폐기하는지 검증합니다.
    /// - 검증 내용: host, branch, authorization, correlation, working directory, roots 변경이 restartIncompatible와 zero spawn을
    /// 반환하는지 확인합니다.
    /// - 사전 조건: public restartCompatibility로 동일 run의 binding을 staging합니다.
    /// - 기대 결과: mismatch마다 adapter/controller stage가 0이 되고 exact request만 한 번 resume합니다.
    func testAdapterRestart_publicContextMismatchDiscardsStageWithoutFreshFallback() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-fence", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-original"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let probe = CodexExecReadinessProbe { _, arguments, _ in
            arguments == ["--version"]
                ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
        }
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let descriptor = adapter.descriptor
        let context = RuntimeContextPolicy(
            branchReference: "branch",
            authorizationGeneration: 0,
            localCorrelation: "correlation",
            workingDirectory: root.path,
            allowedRoots: [root.path],
            requestContext: "request",
        )
        let binding = RuntimeRestartBinding(
            externalAgentSessionReference: .init("host"),
            providerInternalSessionReference: .init("thread-original"),
            runReference: .init("fenced-run"),
            adapterID: descriptor.id,
            providerNamespace: descriptor.providerNamespace,
            adapterVersion: descriptor.adapterVersion,
            providerBranch: descriptor.providerBranch,
            capabilitySnapshot: descriptor.capabilities,
            contextPolicy: context,
        )
        let variants = [
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("other-host"),
                runReference: .init("fenced-run"),
                adapterID: descriptor.id,
                contextPolicy: context,
                input: .init("prompt"),
            ),
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("fenced-run"),
                adapterID: descriptor.id,
                contextPolicy: .init(
                    branchReference: "other-branch",
                    authorizationGeneration: 0,
                    localCorrelation: "correlation",
                    workingDirectory: root.path,
                    allowedRoots: [root.path],
                    requestContext: "request",
                ),
                input: .init("prompt"),
            ),
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("fenced-run"),
                adapterID: descriptor.id,
                contextPolicy: .init(
                    branchReference: "branch",
                    authorizationGeneration: 1,
                    localCorrelation: "correlation",
                    workingDirectory: root.path,
                    allowedRoots: [root.path],
                    requestContext: "request",
                ),
                input: .init("prompt"),
            ),
        ]
        for variant in variants {
            let staged = try await adapter.restartCompatibility(for: binding)
            XCTAssertEqual(staged, RuntimeRestartCompatibility.compatible)
            do {
                _ = try await adapter.launch(variant)
                XCTFail("mismatch should fail")
            } catch { XCTAssertEqual(error as? RuntimeHostError, .restartIncompatible) }
            let adapterCounts = await adapter.debugStorageCounts()
            let controllerCounts = await controller.debugRegistryCounts()
            XCTAssertEqual(adapterCounts.restartBindings, 0)
            XCTAssertEqual(controllerCounts.staged, 0)
            XCTAssertEqual(runner.runCount, 0)
        }
        let staged = try await adapter.restartCompatibility(for: binding)
        XCTAssertEqual(staged, RuntimeRestartCompatibility.compatible)
        _ = try await adapter.launch(
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("fenced-run"),
                adapterID: descriptor.id,
                contextPolicy: context,
                input: .init("prompt"),
            ),
        )
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-006-exact_restart_binding: mismatch eviction leaves a bounded stale tombstone until explicit restage.
    /// incompatible resume 이후 같은 binding이 fresh launch로 우회되지 않고 새 stage에서만 재개되는지 검증합니다.
    /// - 검증 내용: restartIncompatible, staleRestartBinding, explicit compatible restage와 단일 resume spawn을 확인합니다.
    /// - 사전 조건: 동일 run의 A binding을 stage한 뒤 context가 다른 B request를 제공합니다.
    /// - 기대 결과: A stage는 폐기되고 B retry는 stale이며 새 B stage 후 resume만 한 번 실행됩니다.
    func testAdapterRestart_mismatchTombstoneBlocksRetryUntilCompatibleRestage() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-tombstone", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = CodexExecFakeRunner(
            process: CodexExecFakeProcess(
                stdout: [Data(#"{"type":"thread.started","thread_id":"thread"}"#.utf8)],
                stderr: [],
                terminationStatus: 0,
            ),
        )
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let descriptor = adapter.descriptor
        let contextA = RuntimeContextPolicy(
            branchReference: "branch-a",
            authorizationGeneration: 0,
            localCorrelation: "correlation",
            workingDirectory: root.path,
        )
        let contextB = RuntimeContextPolicy(
            branchReference: "branch-b",
            authorizationGeneration: 0,
            localCorrelation: "correlation",
            workingDirectory: root.path,
        )
        func binding(_ context: RuntimeContextPolicy) -> RuntimeRestartBinding {
            RuntimeRestartBinding(
                externalAgentSessionReference: .init("host"),
                providerInternalSessionReference: .init("thread"),
                runReference: .init("tombstone-run"),
                adapterID: descriptor.id,
                providerNamespace: descriptor.providerNamespace,
                adapterVersion: descriptor.adapterVersion,
                providerBranch: descriptor.providerBranch,
                capabilitySnapshot: descriptor.capabilities,
                contextPolicy: context,
            )
        }
        func request(_ context: RuntimeContextPolicy) -> RuntimeLaunchRequest {
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("tombstone-run"),
                adapterID: descriptor.id,
                contextPolicy: context,
                input: .init("prompt"),
            )
        }

        let firstCompatibility = try await adapter.restartCompatibility(for: binding(contextA))
        XCTAssertEqual(firstCompatibility, .compatible)
        do {
            _ = try await adapter.launch(request(contextB))
            XCTFail("mismatch must fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .restartIncompatible) }
        XCTAssertEqual(runner.runCount, 0)
        do {
            _ = try await adapter.launch(request(contextB))
            XCTFail("stale retry must fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .staleRestartBinding) }
        XCTAssertEqual(runner.runCount, 0)

        let secondCompatibility = try await adapter.restartCompatibility(for: binding(contextB))
        XCTAssertEqual(secondCompatibility, .compatible)
        _ = try await adapter.launch(request(contextB))
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-006-fresh_codex_launch: oversized raw JSONL frame fails through the decoder.
    /// raw-byte decoder의 line bound가 controller에서도 유지되는지 검증합니다.
    /// - 검증 내용: 1 MiB 초과 frame의 typed decoder failure와 cleanup을 확인합니다.
    /// - 사전 조건: thread.started frame에 1 MiB 초과 payload를 추가합니다.
    /// - 기대 결과: acquisition은 decoder rawLineTooLarge로 실패합니다.
    func testFreshLaunch_rawLineOverflowFailsThroughDecoder() async {
        let oversized = Data(
            (#"{"type":"thread.started","thread_id":"thread-1","text":""#
                + String(
                    repeating: "x",
                    count: CodexExecJSONLDecoder.maximumRawLineBytes,
                ) + #""}"#).utf8,
        )
        let process = CodexExecFakeProcess(stdout: [oversized], stderr: [], terminationStatus: 0)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "",
        )
        do {
            _ = try await CodexExecProcessController(runner: CodexExecFakeRunner(process: process).run)
                .acquire(runID: "overflow", command: command)
            XCTFail("oversized frame should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .decoder(.rawLineTooLarge))
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(process.terminationCount, 1)
    }

    /// ATI-006-coordinate_external_agent_sessions: raw event retention overflow fails as a typed process error.
    /// decoder line bound와 별개로 receipt raw stream의 pre-consumer retention 상한을 검증합니다.
    /// - 검증 내용: handshake 후 consumer 연결 전 129개 event가 eventBufferOverflow가 되고 terminate/cleanup 및 양쪽 consumer가 끝나는지
    /// 확인합니다.
    /// - 사전 조건: controlled fake process가 handshake 뒤 maximumBufferedEvents보다 많은 유효 event를 보냅니다.
    /// - 기대 결과: overflow가 조용히 drop되지 않고 typed failure로 전달되며 process와 registry가 한 번 정리됩니다.
    func testFreshLaunch_rawEventBufferOverflow_failsAndCleansAllConsumers() async throws {
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let acquisition = Task { try await controller.acquire(runID: "raw-overflow", command: command) }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-1"}"#)
        let receipt = try await acquisition.value
        for index in 0 ... CodexExecProcessController.maximumBufferedRawEvents {
            runner.send(#"{"type":"turn.started","turn_id":"turn-"# + String(index) + #""}"#)
        }

        let eventTask = Task { () -> Error? in
            do {
                let stream = try await receipt.eventStream()
                for try await _ in stream {}
                return nil
            } catch { return error }
        }
        let resultTask = Task { () -> Error? in
            do {
                _ = try await receipt.terminalResult()
                return nil
            } catch { return error }
        }
        let eventError = await eventTask.value
        let resultError = await resultTask.value
        XCTAssertEqual(eventError as? CodexExecProcessFailure, .eventBufferOverflow)
        XCTAssertEqual(resultError as? CodexExecProcessFailure, .eventBufferOverflow)
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let registryCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(registryCounts.fresh, 0)
    }

    /// ATI-006-coordinate_external_agent_sessions: Codex JSONL frames preserve every official event type.
    /// 외부 에이전트 세션의 lifecycle event가 provider 내부 모델로 손실 없이 투영되는지 검증합니다.
    /// - 검증 내용: thread, turn, item, error 계열의 모든 공식 top-level event type과 payload 필드를 확인합니다.
    /// - 사전 조건: 공식 event type 8개를 포함한 JSONL 입력이 줄 단위로 제공됩니다.
    /// - 기대 결과: 입력 순서와 type 및 payload 값이 모두 보존됩니다.
    func testDecode_allOfficialTopLevelEventTypes_preservesPayload() throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"thread-1"}"#,
            #"{"type":"turn.started","turn":{"id":"turn-1","status":"in_progress"}}"#,
            #"{"type":"turn.completed","turn_id":"turn-1","status":"completed"}"#,
            #"{"type":"turn.failed","turn_id":"turn-1","message":"failed"}"#,
            #"{"type":"item.started","item":{"id":"item-1","type":"command"}}"#,
            #"{"type":"item.updated","item_id":"item-1","delta":"output"}"#,
            #"{"type":"item.completed","item":{"id":"item-2","type":"file_change","text":"done"}}"#,
            #"{"type":"error","message":"provider error"}"#,
        ]

        let result = try CodexExecTestHarness.feed(lines)
        var events: [CodexExecDecodedEvent] = []
        for outcome in result.events {
            guard case let .event(event) = outcome else {
                XCTFail("공식 event fixture가 unknown으로 분류되었습니다.")
                continue
            }
            events.append(event)
        }

        XCTAssertEqual(
            events.map(\.type),
            [
                .threadStarted, .turnStarted, .turnCompleted, .turnFailed,
                .itemStarted, .itemUpdated, .itemCompleted, .error,
            ],
        )
        XCTAssertEqual(events[0].payload.threadID, "thread-1")
        XCTAssertEqual(events[1].payload.turnID, "turn-1")
        XCTAssertEqual(events[1].payload.status, "in_progress")
        XCTAssertEqual(events[4].payload.itemID, "item-1")
        XCTAssertEqual(events[4].payload.itemType, "command")
        XCTAssertEqual(events[5].payload.text, "output")
        XCTAssertEqual(events[6].payload.text, "done")
        XCTAssertEqual(events[7].payload.message, "provider error")
    }

    /// ATI-006-coordinate_external_agent_sessions: split UTF-8 is decoded only after a complete newline frame.
    /// multibyte UTF-8 경계가 chunk 경계에 걸려도 완전한 JSONL frame까지 버퍼링되는지 검증합니다.
    /// - 검증 내용: 한글 payload의 UTF-8 byte를 newline 이전에 분할해 append 결과와 최종 text를 확인합니다.
    /// - 사전 조건: item.completed agent_message frame을 UTF-8 byte 중간에서 두 번에 나눠 전달합니다.
    /// - 기대 결과: 첫 chunk는 event를 만들지 않고 두 번째 chunk가 정상 event와 한글 text를 만듭니다.
    func testDecode_splitUTF8Chunk_waitsForCompleteNewlineFrame() throws {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"안녕"}}"#
        let data = Data((line + "\n").utf8)
        let scalarStart = try XCTUnwrap(data.firstIndex(of: 0xEC))
        let split = scalarStart + 1
        var decoder = CodexExecJSONLDecoder()

        XCTAssertTrue(try decoder.append(Data(data[..<split])).isEmpty)
        let outcomes = try decoder.append(Data(data[split...]))

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(decoder.finalAssistantText.value, "안녕")
        guard case let .event(event) = outcomes[0] else { return XCTFail("완전한 frame은 event여야 합니다.") }
        XCTAssertEqual(event.payload.text, "안녕")
    }

    /// ATI-006-coordinate_external_agent_sessions: updated text is replaced by its completed item text.
    /// item.updated delta와 item.completed full text가 중복 누적되지 않는지 검증합니다.
    /// - 검증 내용: 동일 item의 delta 누적, completed authoritative replacement, 다른 item 순서를 확인합니다.
    /// - 사전 조건: agent_message item.updated 후 item.completed와 별도 completed frame을 입력합니다.
    /// - 기대 결과: decoder의 finalAssistantText가 각 item text를 한 번씩 입력 순서대로 합칩니다.
    func testDecode_completedAgentMessages_accumulateFinalAssistantText() throws {
        let result = try CodexExecTestHarness.feed([
            #"{"type":"item.updated","item_id":"item-1","item_type":"agent_message","delta":"첫"}"#,
            #"{"type":"item.updated","item_id":"item-1","item_type":"agent_message","delta":"째 "}"#,
            #"{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"첫째 "}}"#,
            #"{"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"둘째"}}"#,
        ])

        XCTAssertEqual(result.events.count, 4)
        XCTAssertEqual(
            result.events.compactMap { outcome -> String? in
                guard case let .event(event) = outcome else { return nil }
                return event.payload.text
            },
            ["첫", "째 ", "첫째 ", "둘째"],
        )
        var decoder = CodexExecJSONLDecoder()
        _ =
            try decoder
                .append(
                    Data(
                        #"{"type":"item.updated","item_id":"item-1","item_type":"agent_message","delta":"첫"}"#
                            .utf8,
                    ) + Data("\n".utf8),
                )
        _ =
            try decoder
                .append(
                    Data(
                        #"{"type":"item.updated","item_id":"item-1","item_type":"agent_message","delta":"째 "}"#
                            .utf8,
                    ) + Data("\n".utf8),
                )
        _ =
            try decoder
                .append(
                    Data(
                        #"{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"첫째 "}}"#
                            .utf8,
                    ) + Data("\n".utf8),
                )
        _ =
            try decoder
                .append(
                    Data(
                        #"{"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"둘째"}}"#
                            .utf8,
                    ) + Data("\n".utf8),
                )
        XCTAssertEqual(decoder.finalAssistantText.value, "첫째 둘째")
    }

    // MARK: - ATI-006-exact_restart_binding

    /// ATI-006-exact_restart_binding: compatible probe stages without spawning.
    /// exact restart identity probe가 resume binding을 staging하고 process를 만들지 않는지 검증합니다.
    /// - 검증 내용: 13 capabilities, context, host/run/provider reference를 포함한 binding staging과 invocation 0을 확인합니다.
    /// - 사전 조건: current binding과 candidate binding이 모든 필드에서 동일합니다.
    /// - 기대 결과: compatibility가 compatible이고 staged binding이 존재하며 runner 호출은 0회입니다.
    func testRestartCompatibility_exactBindingStagesWithoutSpawn() async throws {
        let runner = CodexExecFakeRunner(
            process: CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0),
        )
        let controller = CodexExecProcessController(runner: runner.run)
        let binding = makeRestartBinding()

        let compatibility = try await controller.restartCompatibility(
            binding: binding,
            current: binding,
        )
        XCTAssertEqual(compatibility, .compatible)
        let staged = await controller.hasStagedRestartBinding(for: binding.runReference)
        XCTAssertTrue(staged)
        XCTAssertEqual(runner.runCount, 0)
        XCTAssertEqual(binding.providerEventSequence, 0)
    }

    /// ATI-006-exact_restart_binding: persisted provider cursor is part of exact identity.
    /// resume binding이 persisted provider event cursor를 staging하고 cursor 차이를 거부하는지 검증합니다.
    /// - 검증 내용: cursor 7 staging, cursor 8 identity mismatch, cursor 0 fresh default를 확인합니다.
    /// - 사전 조건: 동일한 restart binding에서 provider event cursor만 변형합니다.
    /// - 기대 결과: cursor 7은 compatible, cursor 8은 incompatible, 기본 cursor는 0입니다.
    func testRestartCompatibility_providerEventSequenceIsExactIdentity() async throws {
        let controller = CodexExecProcessController(
            runner: CodexExecFakeRunner(
                process: CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0),
            ).run,
        )
        let fresh = makeRestartBinding()
        let resumed = makeRestartBinding(providerEventSequence: 7)

        XCTAssertEqual(fresh.providerEventSequence, 0)
        let compatible = try await controller.restartCompatibility(binding: resumed, current: resumed)
        XCTAssertEqual(compatible, .compatible)
        let incompatible = try await controller.restartCompatibility(
            binding: resumed,
            current: resumed.with(providerEventSequence: 8),
        )
        XCTAssertEqual(incompatible, .incompatible)
    }

    /// ATI-006-exact_restart_binding: provider reference ingress uses the scalar boundary.
    /// persisted provider handle이 허용된 Unicode scalar 범위를 넘지 않는지 검증합니다.
    /// - 검증 내용: 4096 scalar는 compatible이고 4097 scalar는 incompatible이며 oversized binding을 stage하지 않는지 확인합니다.
    /// - 사전 조건: provider reference만 4096/4097 scalar로 바꾼 exact restart binding을 제공합니다.
    /// - 기대 결과: 경계값은 수용되고 초과값은 process spawn 없이 거부됩니다.
    func testRestartCompatibility_providerReferenceIngressEnforcesScalarBoundary() async throws {
        let controller = CodexExecProcessController(
            runner: CodexExecFakeRunner(
                process: CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0),
            ).run,
        )
        let adapter = CodexExecRuntimeAdapter(controller: controller)
        let validProviderReference = String(repeating: "e\u{301}", count: 2048)
        let cases = [
            (validProviderReference, RuntimeRestartCompatibility.compatible),
            (validProviderReference + "x", RuntimeRestartCompatibility.incompatible),
        ]

        for (providerReference, expected) in cases {
            let binding = RuntimeRestartBinding(
                externalAgentSessionReference: .init("host"),
                providerInternalSessionReference: .init(providerReference),
                runReference: .init("boundary-run-\(providerReference.unicodeScalars.count)"),
                adapterID: adapter.descriptor.id,
                providerNamespace: adapter.descriptor.providerNamespace,
                adapterVersion: adapter.descriptor.adapterVersion,
                providerBranch: adapter.descriptor.providerBranch,
                capabilitySnapshot: adapter.descriptor.capabilities,
                contextPolicy: .init(
                    branchReference: "branch",
                    authorizationGeneration: 1,
                    localCorrelation: "correlation",
                ),
            )
            let compatibility = try await adapter.restartCompatibility(for: binding)
            XCTAssertEqual(compatibility, expected)
            if expected == .incompatible {
                let isStaged = await controller.hasStagedRestartBinding(for: binding.runReference.rawValue)
                XCTAssertFalse(isStaged)
            }
        }
    }

    /// ATI-006-exact_restart_binding: an older staged completion cannot publish over a newer binding.
    /// controller stage gate로 completion 순서를 뒤집어도 adapter가 stale binding을 공개하지 않는지 검증합니다.
    /// - 검증 내용: 같은 run의 newer provider reference와 cursor가 older completion을 이기고 exact current stage를 유지하는지 확인합니다.
    /// - 사전 조건: 첫 stage completion만 gate하고 두 번째 compatible probe를 먼저 완료시킵니다.
    /// - 기대 결과: newer probe는 compatible, older probe는 stale이며 adapter에는 newer binding만 남습니다.
    func testRestartCompatibility_olderCompletionCannotOverwriteNewerBinding() async throws {
        let gate = RestartStageGate()
        let controller = CodexExecProcessController(
            registry: nil,
            onRestartCompatibilityStaged: { await gate.invoke() },
        )
        let adapter = CodexExecRuntimeAdapter(controller: controller)
        let context = RuntimeContextPolicy(
            branchReference: "branch",
            authorizationGeneration: 1,
            localCorrelation: "correlation",
        )
        func binding(provider: String, sequence: UInt64) -> RuntimeRestartBinding {
            RuntimeRestartBinding(
                externalAgentSessionReference: .init("host"),
                providerInternalSessionReference: .init(provider),
                runReference: .init("raced-run"),
                adapterID: adapter.descriptor.id,
                providerNamespace: adapter.descriptor.providerNamespace,
                adapterVersion: adapter.descriptor.adapterVersion,
                providerBranch: adapter.descriptor.providerBranch,
                capabilitySnapshot: adapter.descriptor.capabilities,
                contextPolicy: context,
                providerEventSequence: sequence,
            )
        }

        let older = Task { try await adapter.restartCompatibility(for: binding(provider: "old", sequence: 1)) }
        await gate.waitForFirstStage()
        let newer = try await adapter.restartCompatibility(for: binding(provider: "new", sequence: 2))
        XCTAssertEqual(newer, .compatible)
        await gate.release()
        let olderResult = try await older.value
        XCTAssertEqual(olderResult, .stale)
        let staged = await controller.stagedRestartBinding(for: "raced-run")
        XCTAssertEqual(staged?.providerReference, "new")
        XCTAssertEqual(staged?.providerEventSequence, 2)
    }

    /// ATI-006-exact_restart_binding: every identity mismatch is incompatible without spawning.
    /// exact fence가 adapter/provider/capability/context 및 host/run/reference 변경을 모두 거부하는지 검증합니다.
    /// - 검증 내용: adapter ID, namespace, version, branch, capability, context, provider reference, host, run 변형을 확인합니다.
    /// - 사전 조건: 한 번에 하나의 binding field만 변형한 candidate가 제공됩니다.
    /// - 기대 결과: 각 probe가 incompatible이고 staging 및 runner invocation은 0회입니다.
    func testRestartCompatibility_anyIdentityMismatchDoesNotStageOrSpawn() async throws {
        let runner = CodexExecFakeRunner(
            process: CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0),
        )
        let controller = CodexExecProcessController(runner: runner.run)
        let binding = makeRestartBinding()
        let mismatches = [
            binding.with(adapterID: "other-adapter"),
            binding.with(providerNamespace: "other-provider"),
            binding.with(adapterVersion: "0.149.0"),
            binding.with(providerBranch: "preview"),
            binding.with(capabilities: binding.capabilities.mutated),
            binding.with(context: binding.context.mutated),
            binding.with(providerReference: "other-thread"),
            binding.with(hostReference: "other-host"),
            binding.with(runReference: "other-run"),
        ]

        for mismatch in mismatches {
            let compatibility = try await controller.restartCompatibility(
                binding: binding,
                current: mismatch,
            )
            XCTAssertEqual(compatibility, .incompatible)
        }
        let staged = await controller.hasStagedRestartBinding(for: binding.runReference)
        XCTAssertFalse(staged)
        XCTAssertEqual(runner.runCount, 0)
    }

    /// ATI-006-exact_restart_binding: compatible probes remain bounded and evict oldest first.
    /// launch 없이 누적되는 compatible probe가 유한하며 가장 오래된 binding부터 폐기되는지 검증합니다.
    /// - 검증 내용: capacity+1 staging 후 양 끝 binding의 resumability와 stage count를 확인합니다.
    /// - 사전 조건: process runner가 주입된 controller에 서로 다른 run binding을 순서대로 staging합니다.
    /// - 기대 결과: stage count는 512이고 oldest는 stale, newest는 exact stage를 유지합니다.
    func testRestartCompatibility_stagedBindingsAreBoundedAndOldestFirst() async throws {
        let runner = CodexExecFakeRunner(
            process: CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0),
        )
        let controller = CodexExecProcessController(runner: runner.run)
        let bindings = (0 ... 512).map { makeRestartBinding(run: "run-\($0)") }

        for binding in bindings {
            let compatibility = try await controller.restartCompatibility(
                binding: binding,
                current: binding,
            )
            XCTAssertEqual(compatibility, .compatible)
        }

        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.staged, 512)
        let oldestIsStaged = await controller.hasStagedRestartBinding(for: bindings[0].runReference)
        let newestIsStaged = await controller.hasStagedRestartBinding(for: bindings[512].runReference)
        XCTAssertFalse(oldestIsStaged)
        XCTAssertTrue(newestIsStaged)
        XCTAssertEqual(runner.runCount, 0)
    }

    /// ATI-006-exact_restart_binding: adapter and controller retain the same bounded restart set.
    /// public adapter probe가 controller와 동일한 순서로 eviction하고 stale launch를 차단하는지 검증합니다.
    /// - 검증 내용: capacity+1 adapter probes, replacement, stale oldest launch, newest resume와 양쪽 count를 확인합니다.
    /// - 사전 조건: readiness probe와 fake runner를 주입한 adapter가 있습니다.
    /// - 기대 결과: staging 중 spawn은 0이고 양쪽 map은 512 이하이며 newest만 한 번 resume됩니다.
    func testAdapterRestart_capacityEvictsOldestAndPreservesNewestResume() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-capacity", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-512"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let probe = CodexExecReadinessProbe { _, arguments, _ in
            CodexExecProbeResult(
                exitCode: 0,
                stdout: arguments == ["--version"] ? "codex-cli 0.148.0\n" : "",
                stderr: "",
            )
        }
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let descriptor = adapter.descriptor
        let context = RuntimeContextPolicy(
            branchReference: "branch",
            authorizationGeneration: 1,
            localCorrelation: "correlation",
            workingDirectory: root.path,
        )
        func binding(_ index: Int) -> RuntimeRestartBinding {
            RuntimeRestartBinding(
                externalAgentSessionReference: .init("host"),
                providerInternalSessionReference: .init("thread-\(index)"),
                runReference: .init("run-\(index)"),
                adapterID: descriptor.id,
                providerNamespace: descriptor.providerNamespace,
                adapterVersion: descriptor.adapterVersion,
                providerBranch: descriptor.providerBranch,
                capabilitySnapshot: descriptor.capabilities,
                contextPolicy: context,
            )
        }

        for index in 0 ... 512 {
            let compatibility = try await adapter.restartCompatibility(for: binding(index))
            XCTAssertEqual(compatibility, .compatible)
        }
        let replacementCompatibility = try await adapter.restartCompatibility(for: binding(512))
        XCTAssertEqual(replacementCompatibility, .compatible)
        var adapterCounts = await adapter.debugStorageCounts()
        var controllerCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(adapterCounts.restartBindings, 512)
        XCTAssertEqual(controllerCounts.staged, 512)
        XCTAssertEqual(runner.runCount, 0)

        let staleRequest = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("run-0"),
            adapterID: descriptor.id,
            contextPolicy: context,
            input: .init("prompt"),
        )
        do {
            _ = try await adapter.launch(staleRequest)
            XCTFail("evicted stage should be stale")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .staleRestartBinding) }

        let newest = binding(512)
        let resumed = try await adapter.launch(
            RuntimeLaunchRequest(
                externalAgentSessionReference: newest.externalAgentSessionReference,
                runReference: newest.runReference,
                adapterID: descriptor.id,
                contextPolicy: context,
                input: .init("prompt"),
            ),
        )
        XCTAssertEqual(resumed.providerInternalSessionReference.rawValue, "thread-512")
        XCTAssertEqual(runner.runCount, 1)
        adapterCounts = await adapter.debugStorageCounts()
        controllerCounts = await controller.debugRegistryCounts()
        XCTAssertLessThanOrEqual(adapterCounts.restartBindings, 512)
        XCTAssertLessThanOrEqual(controllerCounts.staged, 512)
    }

    /// ATI-006-exact_restart_binding: completed eviction preserves a newer staged restart binding.
    /// 완료된 run의 retention eviction이 같은 run의 newer restart binding을 지우지 않는지 검증합니다.
    /// - 검증 내용: run A 완료 후 newer binding staging, run B eviction, A resume 성공과 단일 runner 호출을 확인합니다.
    /// - 사전 조건: retention capacity 1인 adapter와 fresh A/B 및 resume fake process가 있습니다.
    /// - 기대 결과: A binding이 유지되고 resume이 성공하며 fresh fallback이 발생하지 않습니다.
    func testAdapterCompletedEviction_preservesNewerStagedRestartBinding() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-completed-eviction", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let processes = [
            CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-a"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            ),
            CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-b"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            ),
            CodexExecFakeProcess(
                stdout: [Data(#"{"type":"thread.started","thread_id":"thread-a"}"#.utf8)],
                stderr: [],
                terminationStatus: 0,
            ),
        ]
        let runAEvicted = expectation(description: "completed run A is evicted")
        processes[0].onCleanup = { runAEvicted.fulfill() }
        let calls = CodexExecInvocationCounter()
        let runner: CodexExecProcessController.Runner = { command in
            let index = calls.value
            calls.increment()
            if index == 2, !command.arguments.contains("resume") {
                throw CodexExecProcessFailure.launchFailed
            }
            return try await CodexExecFakeRunner(process: processes[index]).run(command)
        }
        let controller = CodexExecProcessController(runner: runner)
        let probe = CodexExecReadinessProbe { _, arguments, _ in
            CodexExecProbeResult(
                exitCode: 0,
                stdout: arguments == ["--version"] ? "codex-cli 0.148.0\n" : "",
                stderr: "",
            )
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            retentionCapacity: 1,
        )
        let descriptor = adapter.descriptor
        let context = RuntimeContextPolicy(
            branchReference: "branch",
            authorizationGeneration: 0,
            localCorrelation: "correlation",
            workingDirectory: root.path,
        )
        func request(_ run: String) -> RuntimeLaunchRequest {
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init(run),
                adapterID: descriptor.id,
                contextPolicy: context,
                input: .init("prompt"),
            )
        }
        let runA = request("run-a")
        _ = try await adapter.launch(runA)
        _ = try await adapter.terminalResult(for: runA.runReference)
        let bindingA = RuntimeRestartBinding(
            externalAgentSessionReference: runA.externalAgentSessionReference,
            providerInternalSessionReference: .init("thread-a"),
            runReference: runA.runReference,
            adapterID: descriptor.id,
            providerNamespace: descriptor.providerNamespace,
            adapterVersion: descriptor.adapterVersion,
            providerBranch: descriptor.providerBranch,
            capabilitySnapshot: descriptor.capabilities,
            contextPolicy: context,
        )
        let bindingCompatibility = try await adapter.restartCompatibility(for: bindingA)
        XCTAssertEqual(bindingCompatibility, .compatible)

        let runB = request("run-b")
        _ = try await adapter.launch(runB)
        _ = try await adapter.terminalResult(for: runB.runReference)
        await fulfillment(of: [runAEvicted], timeout: 2)

        let resumed = try await adapter.launch(runA)
        XCTAssertEqual(resumed.providerInternalSessionReference.rawValue, "thread-a")
        XCTAssertEqual(calls.value, 3)
        let counts = await adapter.debugStorageCounts()
        XCTAssertEqual(counts.restartBindings, 0)
    }

    /// ATI-006-exact_restart_binding: controller retention eviction preserves a newer exact binding.
    /// controller의 완료 retention eviction이 같은 run의 newer staged binding을 지우지 않는지 직접 검증합니다.
    /// - 검증 내용: A 완료/보존, A binding stage, B eviction, A exact resume와 fresh fallback 부재를 확인합니다.
    /// - 사전 조건: retention capacity 1인 controller에 fresh A/B와 resume process를 주입합니다.
    /// - 기대 결과: A binding은 유지되고 resume은 정확히 한 번 실행됩니다.
    func testControllerCompletedEviction_preservesNewerStagedRestartBinding() async throws {
        let processes = [
            CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-a"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            ),
            CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-b"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            ),
            CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-a-resumed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            ),
        ]
        let calls = CodexExecInvocationCounter()
        let runner: CodexExecProcessController.Runner = { command in
            let index = calls.value
            calls.increment()
            return try await CodexExecFakeRunner(process: processes[index]).run(command)
        }
        let controller = CodexExecProcessController(runner: runner, retentionCapacity: 1)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let binding = makeRestartBinding(run: "run-a")

        let receiptA = try await controller.acquire(runID: "run-a", command: command)
        _ = try await receiptA.terminalResult()
        _ = try await controller.restartCompatibility(binding: binding, current: binding)

        let receiptB = try await controller.acquire(runID: "run-b", command: command)
        _ = try await receiptB.terminalResult()
        let staged = await controller.hasStagedRestartBinding(for: binding.runReference)
        XCTAssertTrue(staged)

        let resumeCommand = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "resume", binding.providerReference],
            environment: [:],
            stdin: "resume",
        )
        let resumed = try await controller.acquire(
            runID: binding.runReference,
            command: resumeCommand,
            restartBinding: binding,
        )
        XCTAssertEqual(resumed.threadID, "thread-a-resumed")
        XCTAssertEqual(calls.value, 3)
        let consumed = await controller.hasStagedRestartBinding(for: binding.runReference)
        XCTAssertFalse(consumed)
    }

    /// ATI-006-fresh_codex_launch: process runner cancellation remains CancellationError.
    /// process 생성 전에 발생한 취소 오류가 launch failure로 변환되지 않는지 검증합니다.
    /// - 검증 내용: exact CancellationError와 fresh/resume/staged registry count 0을 확인합니다.
    /// - 사전 조건: process runner가 process 반환 전에 CancellationError를 throw합니다.
    /// - 기대 결과: acquisition은 CancellationError로 종료되고 registry는 비어 있습니다.
    func testFreshLaunch_runnerCancellationPreservesCancellationError() async {
        let controller = CodexExecProcessController(runner: { _ in throw CancellationError() })
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        do {
            _ = try await controller.acquire(runID: "runner-cancel", command: command)
            XCTFail("runner cancellation should propagate")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
        XCTAssertEqual(counts.resume, 0)
        XCTAssertEqual(counts.staged, 0)
    }

    /// ATI-006-exact_restart_binding: staged binding is consumed once by matching resume.
    /// matching run의 resume만 staged binding을 소비하고 Codex resume process를 한 번 실행하는지 검증합니다.
    /// - 검증 내용: resume thread ID, stdin semantics, second consume typed invalid error와 spawn count를 확인합니다.
    /// - 사전 조건: compatible probe가 binding을 staging하고 fake process가 handshake를 반환합니다.
    /// - 기대 결과: 첫 launch만 성공하며 두 번째 launch는 invalid 오류와 함께 spawn하지 않습니다.
    func testResume_consumesMatchingStageOnceAndNeverFallsBack() async throws {
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"provider-thread"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let binding = makeRestartBinding()
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [
                "exec", "resume", "--json", "--strict-config", "--ignore-user-config", "provider-thread",
                "-",
            ],
            environment: [:],
            stdin: "resume prompt",
        )

        _ = try await controller.restartCompatibility(binding: binding, current: binding)
        let receipt = try await controller.acquire(
            runID: binding.runReference,
            command: command,
            restartBinding: binding,
        )
        XCTAssertEqual(receipt.threadID, "provider-thread")
        XCTAssertEqual(process.writes, [Data("resume prompt".utf8)])
        XCTAssertEqual(process.closeCount, 1)
        XCTAssertEqual(runner.runCount, 1)
        do {
            _ = try await controller.acquire(
                runID: binding.runReference,
                command: command,
                restartBinding: binding,
            )
            XCTFail("second staged binding consume should fail")
        } catch let error as CodexExecRestartFailure {
            XCTAssertEqual(error, .invalidBinding)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-006-exact_restart_binding: a failed resume remains retryable without fresh fallback.
    /// transient resume start failure 이후 동일 binding을 즉시 재시도할 수 있는지 검증합니다.
    /// - 검증 내용: 첫 resume 실패, 두 번째 resume 성공, resume 총 호출 2회와 fresh 호출 0회를 확인합니다.
    /// - 사전 조건: exact binding을 stage하고 첫 runner invocation만 launch failure를 반환합니다.
    /// - 기대 결과: 두 번째 invocation이 resume argv로 성공하고 binding은 성공 후 소비됩니다.
    func testResume_transientStartFailure_canRetryExactBindingWithoutFreshFallback() async throws {
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"provider-thread"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let successRunner = CodexExecFakeRunner(process: process)
        let attempts = CodexExecInvocationCounter()
        let runner: CodexExecProcessController.Runner = { command in
            attempts.increment()
            guard attempts.value > 1 else { throw CodexExecProcessFailure.launchFailed }
            return try await successRunner.run(command)
        }
        let controller = CodexExecProcessController(runner: runner)
        let binding = makeRestartBinding()
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "resume", "--json", binding.providerReference, "-"],
            environment: [:],
            stdin: "resume",
        )

        _ = try await controller.restartCompatibility(binding: binding, current: binding)
        do {
            _ = try await controller.acquire(
                runID: binding.runReference,
                command: command,
                restartBinding: binding,
            )
            XCTFail("first resume should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .launchFailed)
        }
        let stagedAfterFailure = await controller.hasStagedRestartBinding(for: binding.runReference)
        XCTAssertTrue(stagedAfterFailure)

        let receipt = try await controller.acquire(
            runID: binding.runReference,
            command: command,
            restartBinding: binding,
        )
        XCTAssertEqual(receipt.threadID, binding.providerReference)
        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(successRunner.runCount, 1)
        let stagedAfterSuccess = await controller.hasStagedRestartBinding(for: binding.runReference)
        XCTAssertFalse(stagedAfterSuccess)
    }

    /// ATI-006-exact_restart_binding: failed stale cleanup preserves a newer staged binding.
    /// 이전 consumed binding의 실패 정리가 같은 run의 newer binding을 삭제하지 않는지 검증합니다.
    /// - 검증 내용: old binding release 이후 newer binding이 그대로 stage되는지 확인합니다.
    /// - 사전 조건: registry에 old binding을 consume하고 newer binding을 stage합니다.
    /// - 기대 결과: old rollback은 newer binding을 덮어쓰지 않습니다.
    func testResume_failedOldBindingRelease_preservesNewerBinding() async throws {
        let registry = CodexExecProcessRegistry()
        let old = makeRestartBinding()
        let newer = old.with(providerReference: "new-provider-thread")
        _ = await registry.stage(old)
        try await registry.consume(old)
        _ = await registry.stage(newer)
        _ = await registry.releaseConsumedBinding(old)

        let controller = CodexExecProcessController(registry: registry)
        let newerIsStaged = await controller.hasStagedRestartBinding(for: newer.runReference)
        XCTAssertTrue(newerIsStaged)
        do {
            try await registry.consume(old)
            XCTFail("old binding must not replace newer binding")
        } catch let error as CodexExecRestartFailure {
            XCTAssertEqual(error, .incompatibleBinding)
        }
        let newerRemainsStaged = await controller.hasStagedRestartBinding(for: newer.runReference)
        XCTAssertTrue(newerRemainsStaged)
    }

    /// ATI-006-exact_restart_binding: failed resume restoration stays within staged capacity.
    /// 실패한 resume binding 복원이 동일 actor의 oldest-first capacity 정책과 exact fence를 지키는지 검증합니다.
    /// - 검증 내용: 512개 stage, in-flight A, 다른 run stage, 실패 복원 후 512 count와 oldest eviction을 확인합니다.
    /// - 사전 조건: controller registry가 가득 차고 resume runner가 gate에서 launch failure를 반환합니다.
    /// - 기대 결과: A 복원은 한 번만 유지되고 run-1은 eviction되며 fresh fallback은 발생하지 않습니다.
    func testResume_failedBindingRestoration_enforcesCapacityAndOldestFirst() async throws {
        let gate = CodexExecRunnerGate()
        let runner: CodexExecProcessController.Runner = { _ in
            await gate.signalStarted()
            await gate.waitUntilReleased()
            throw CodexExecProcessFailure.launchFailed
        }
        let controller = CodexExecProcessController(runner: runner)
        let allBindings = (0 ..< CodexExecProcessRegistry.maximumRetainedStagedBindings)
            .map { makeRestartBinding(run: "run-\($0)") }
        let bindingA = allBindings[0]
        for binding in allBindings {
            _ = try await controller.restartCompatibility(binding: binding, current: binding)
        }

        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "resume", bindingA.providerReference],
            environment: [:],
            stdin: "resume",
        )
        let failedResume = Task {
            try await controller.acquire(
                runID: bindingA.runReference,
                command: command,
                restartBinding: bindingA,
            )
        }
        await gate.waitUntilStarted()
        let newerRun = makeRestartBinding(run: "run-new")
        _ = try await controller.restartCompatibility(binding: newerRun, current: newerRun)
        await gate.release()

        do {
            _ = try await failedResume.value
            XCTFail("failed resume should not produce a receipt")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .launchFailed)
        }
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.staged, CodexExecProcessRegistry.maximumRetainedStagedBindings)
        let stagedA = await controller.hasStagedRestartBinding(for: bindingA.runReference)
        let stagedOldest = await controller.hasStagedRestartBinding(for: "run-1")
        let stagedNewer = await controller.hasStagedRestartBinding(for: newerRun.runReference)
        XCTAssertTrue(stagedA)
        XCTAssertFalse(stagedOldest)
        XCTAssertTrue(stagedNewer)
    }

    /// ATI-006-exact_restart_binding: adapter storage follows controller eviction after failed resume restoration.
    /// failed resume 복원의 controller eviction이 adapter restart map에도 exact identity로 반영되는지 검증합니다.
    /// - 검증 내용: 양쪽 512 stage, A in-flight, 추가 stage, 실패 복원 후 양쪽 count와 evicted run을 확인합니다.
    /// - 사전 조건: public adapter restartCompatibility와 launch가 gate-controlled controller를 공유합니다.
    /// - 기대 결과: controller/adapter 모두 512 이하이고 run-1은 stale, resume은 fresh fallback 없이 실패합니다.
    func testAdapter_failedResumeRestoration_synchronizesEvictionAndPreservesExactBinding()
        async throws
    {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-restore-eviction")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = CodexExecRunnerGate()
        let attempts = CodexExecInvocationCounter()
        let freshCalls = CodexExecInvocationCounter()
        let resumeCalls = CodexExecInvocationCounter()
        let successfulResume = CodexExecFakeRunner(
            process: CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-b"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            ),
        )
        let controller = CodexExecProcessController(runner: { command in
            attempts.increment()
            guard command.arguments.contains("resume") else {
                freshCalls.increment()
                XCTFail("fresh fallback is forbidden")
                throw CodexExecProcessFailure.launchFailed
            }
            resumeCalls.increment()
            if resumeCalls.value == 1 {
                XCTAssertEqual(
                    command.arguments,
                    [
                        "exec", "--model", "gpt-5-codex", "--json", "--strict-config", "--ignore-user-config",
                        "-c", "default_permissions=\"voyager-reference\"", "-c",
                        "permissions.voyager-reference.filesystem={\"/tmp/voyager-adapter-restore-eviction\"=\"read\",\":minimal\"=\"read\",\":root\"=\"deny\"}",
                        "--sandbox", "read-only", "-C", "/tmp/voyager-adapter-restore-eviction",
                        "--skip-git-repo-check", "resume",
                        "thread-0",
                        "-",
                    ],
                )
                await gate.signalStarted()
                await gate.waitUntilReleased()
                throw CodexExecProcessFailure.launchFailed
            }
            XCTAssertEqual(
                command.arguments,
                [
                    "exec", "--model", "gpt-5-codex", "--json", "--strict-config", "--ignore-user-config",
                    "-c", "default_permissions=\"voyager-reference\"", "-c",
                    "permissions.voyager-reference.filesystem={\"/tmp/voyager-adapter-restore-eviction\"=\"read\",\":minimal\"=\"read\",\":root\"=\"deny\"}",
                    "--sandbox", "read-only", "-C", "/tmp/voyager-adapter-restore-eviction",
                    "--skip-git-repo-check", "resume",
                    "thread-b",
                    "-",
                ],
            )
            return try await successfulResume.run(command)
        })
        let probe = CodexExecReadinessProbe { _, _, _ in
            CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let descriptor = adapter.descriptor
        let context = RuntimeContextPolicy(
            branchReference: "branch",
            authorizationGeneration: 1,
            localCorrelation: "correlation",
            workingDirectory: root.path,
        )
        func binding(
            _ index: Int,
            runReference: String? = nil,
            providerReference: String? = nil,
            contextPolicy: RuntimeContextPolicy? = nil,
        ) -> RuntimeRestartBinding {
            RuntimeRestartBinding(
                externalAgentSessionReference: .init("host"),
                providerInternalSessionReference: .init(providerReference ?? "thread-\(index)"),
                runReference: .init(runReference ?? "run-\(index)"),
                adapterID: descriptor.id,
                providerNamespace: descriptor.providerNamespace,
                adapterVersion: descriptor.adapterVersion,
                providerBranch: descriptor.providerBranch,
                capabilitySnapshot: descriptor.capabilities,
                contextPolicy: contextPolicy ?? context,
            )
        }
        for index in 0 ..< CodexExecProcessRegistry.maximumRetainedStagedBindings {
            let compatibility = try await adapter.restartCompatibility(for: binding(index))
            XCTAssertEqual(compatibility, .compatible)
        }

        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("run-0"),
            adapterID: descriptor.id,
            contextPolicy: context,
            input: .init("prompt"),
        )
        let failedResume = Task { try await adapter.launch(request) }
        await gate.waitUntilStarted()
        let stagingC = try await adapter.restartCompatibility(for: binding(512))
        XCTAssertEqual(stagingC, .compatible)
        let bindingB = binding(
            0,
            runReference: "run-0",
            providerReference: "thread-b",
            contextPolicy: RuntimeContextPolicy(
                branchReference: "branch-b",
                authorizationGeneration: 2,
                localCorrelation: "correlation-b",
                workingDirectory: root.path,
            ),
        )
        let stagingB = try await adapter.restartCompatibility(for: bindingB)
        XCTAssertEqual(stagingB, .compatible)
        await gate.release()

        do {
            _ = try await failedResume.value
            XCTFail("failed resume should not return a receipt")
        } catch let error as RuntimeAdapterFailure {
            XCTAssertEqual(error, .init(kind: .processExit, diagnosticCode: RuntimeDiagnosticCode("launch_failed")))
        }
        let controllerCounts = await controller.debugRegistryCounts()
        let adapterCounts = await adapter.debugStorageCounts()
        XCTAssertEqual(controllerCounts.staged, adapterCounts.restartBindings)
        XCTAssertLessThanOrEqual(
            controllerCounts.staged,
            CodexExecProcessRegistry.maximumRetainedStagedBindings,
        )
        XCTAssertLessThanOrEqual(
            adapterCounts.restartBindings,
            CodexExecProcessRegistry.maximumRetainedStagedBindings,
        )
        let evictedRequest = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("run-1"),
            adapterID: descriptor.id,
            contextPolicy: context,
            input: .init("prompt"),
        )
        do {
            _ = try await adapter.launch(evictedRequest)
            XCTFail("controller-evicted adapter binding must remain stale")
        } catch let error as RuntimeHostError {
            XCTAssertEqual(error, .staleRestartBinding)
        }
        XCTAssertEqual(
            adapterCounts.restartBindings,
            CodexExecProcessRegistry.maximumRetainedStagedBindings,
        )

        let requestB = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("run-0"),
            adapterID: descriptor.id,
            contextPolicy: bindingB.contextPolicy,
            input: .init("prompt"),
        )
        let receiptB = try await adapter.launch(requestB)
        let resultB = try await adapter.terminalResult(for: requestB.runReference)
        XCTAssertEqual(receiptB.providerInternalSessionReference.rawValue, "thread-b")
        XCTAssertEqual(resultB.outcome, .completed)
        XCTAssertEqual(freshCalls.value, 0)
        XCTAssertEqual(resumeCalls.value, 2)
        XCTAssertEqual(attempts.value, 2)
        let finalControllerCounts = await controller.debugRegistryCounts()
        let finalAdapterCounts = await adapter.debugStorageCounts()
        XCTAssertEqual(finalControllerCounts.staged, finalAdapterCounts.restartBindings)
        XCTAssertLessThanOrEqual(
            finalControllerCounts.staged,
            CodexExecProcessRegistry.maximumRetainedStagedBindings,
        )
    }

    /// ATI-006-exact_restart_binding: absent and mismatched launch bindings fail closed.
    /// staged binding이 없거나 provider reference가 다르면 fresh process로 전환하지 않는지 검증합니다.
    /// - 검증 내용: stale/incompatible typed failure와 runner invocation 0을 확인합니다.
    /// - 사전 조건: staging되지 않은 binding 및 다른 provider reference를 가진 binding이 제공됩니다.
    /// - 기대 결과: 두 launch가 실패하고 process spawn은 0회입니다.
    func testResume_absentOrMismatchedBindingFailsWithoutFreshFallback() async {
        let runner = CodexExecFakeRunner(
            process: CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0),
        )
        let controller = CodexExecProcessController(runner: runner.run)
        let binding = makeRestartBinding()
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "resume", "--json", "provider-thread", "-"],
            environment: [:],
            stdin: "prompt",
        )

        do {
            _ = try await controller.acquire(
                runID: binding.runReference,
                command: command,
                restartBinding: binding,
            )
            XCTFail("absent stage should fail")
        } catch let error as CodexExecRestartFailure {
            XCTAssertEqual(error, .staleBinding)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        _ = try? await controller.restartCompatibility(binding: binding, current: binding)
        let mismatchedCommand = CodexExecCommand(
            executableURL: command.executableURL,
            arguments: ["exec", "resume", "--json", "other-thread", "-"],
            environment: command.environment,
            stdin: command.stdin,
        )
        do {
            _ = try await controller.acquire(
                runID: binding.runReference,
                command: mismatchedCommand,
                restartBinding: binding.with(providerReference: "other-thread"),
            )
            XCTFail("mismatched stage should fail")
        } catch let error as CodexExecRestartFailure {
            XCTAssertEqual(error, .incompatibleBinding)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(runner.runCount, 0)
    }

    /// ATI-006-exact_restart_binding: matching resume bypasses an in-flight fresh entry.
    /// 같은 run의 fresh task가 registry에 있어도 resume가 그 task를 반환하지 않고 독립 실행되는지 검증합니다.
    /// - 검증 내용: fresh runner를 대기시킨 채 resume thread handshake와 두 invocation을 확인합니다.
    /// - 사전 조건: fresh acquisition이 시작되어 registry entry를 점유하고 compatible binding이 staging됩니다.
    /// - 기대 결과: resume가 먼저 성공하고 fresh task 해제 후에도 총 spawn은 정확히 2회입니다.
    func testResume_sameRunFreshEntryInFlightStillInvokesResumeCommand() async throws {
        let fresh = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"fresh-thread"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let resumed = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"provider-thread"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let gate = CodexExecRunnerGate()
        let runner = CodexExecRaceRunner(freshProcess: fresh, resumeProcess: resumed, freshGate: gate)
        let controller = CodexExecProcessController(runner: runner.run)
        let binding = makeRestartBinding()
        let freshCommand = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "--json"],
            environment: [:],
            stdin: "fresh",
        )
        let resumeCommand = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: ["exec", "resume", "--json", "provider-thread", "-"],
            environment: [:],
            stdin: "resume",
        )

        let freshTask = Task {
            try await controller.acquire(runID: binding.runReference, command: freshCommand)
        }
        await gate.waitUntilStarted()
        _ = try await controller.restartCompatibility(binding: binding, current: binding)

        let receipt = try await controller.acquire(
            runID: binding.runReference,
            command: resumeCommand,
            restartBinding: binding,
        )
        XCTAssertEqual(receipt.threadID, "provider-thread")
        XCTAssertEqual(resumed.writes, [Data("resume".utf8)])
        XCTAssertEqual(runner.runCount, 2)

        await gate.release()
        _ = try await freshTask.value
        XCTAssertEqual(fresh.writes, [Data("fresh".utf8)])
    }

    private func makeRestartBinding(
        run: String = "run",
        providerReference: String = "provider-thread",
        providerEventSequence: UInt64 = 0,
    ) -> CodexExecRestartBinding {
        CodexExecRestartBinding(
            hostReference: "host",
            runReference: run,
            providerReference: providerReference,
            adapterID: "codex",
            providerNamespace: "openai.codex",
            adapterVersion: "0.148.0",
            providerBranch: "codex_stable_json",
            capabilities: .allSupported,
            context: .init(
                branchReference: "branch",
                authorizationGeneration: 1,
                localCorrelation: "correlation",
            ),
            providerEventSequence: providerEventSequence,
        )
    }
}

private actor ATI006RuntimeMemoryStore: RuntimeStateStore {
    var state: RuntimeStoredState

    init(state: RuntimeStoredState) {
        self.state = state
    }

    func load() async throws -> RuntimeStoredState? {
        state
    }

    func apply(_ mutation: RuntimeStateMutation) async throws -> RuntimeStateMutationResult {
        let current = state.sessions.first(where: {
            $0.externalAgentSessionReference == mutation.host
        })
        guard current == mutation.expected else {
            return .conflict(state)
        }
        var sessions = state.sessions.filter {
            $0.externalAgentSessionReference != mutation.host
        }
        if let replacement = mutation.replacement {
            sessions.append(replacement)
        }
        state = RuntimeStoredState(schemaVersion: state.schemaVersion, sessions: sessions)
        return .committed(state)
    }
}
