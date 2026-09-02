import Foundation
@testable import VoyagerEntitiesAi
import VoyagerExternalAgentRuntime
import XCTest

// MARK: - ATI-008-observe_external_agent_results

final class ATI008ObserveExternalAgentResultsTests: XCTestCase {
    private struct ProcessExitCase {
        let name: String
        let terminal: String
        let status: Int32
        let failure: CodexExecProcessFailure
        let diagnostic: String?
    }

    /// ATI-008-observe_external_agent_results: completed one-sided sessions evict oldest at capacity.
    /// 한쪽 public consumer만 완료된 session retention이 oldest-first로 제한되는지 검증합니다.
    /// - 검증 내용: exact capacity, capacity+1 eviction, active entry preservation, single cleanup을 확인합니다.
    /// - 사전 조건: retention capacity 2인 controller에 terminal-first completed session 3개와 active session 1개를 제공합니다.
    /// - 기대 결과: oldest만 terminate/cleanup되고 newest 2개와 active entry가 registry에 남습니다.
    func testRetention_capacityPlusOneEvictsOldestCompletedEntryOnly() async throws {
        let registry = CodexExecProcessRegistry(retentionCapacity: 2)
        let controller = CodexExecProcessController(registry: registry)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let processes = (0 ..< 3).map { _ in
            CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            )
        }
        for (index, process) in processes.enumerated() {
            let receipt = try await CodexExecProcessController(
                runner: CodexExecFakeRunner(process: process).run,
                registry: registry,
                retentionCapacity: 2,
            ).acquire(runID: "run-\(index)", command: command)
            _ = try await receipt.terminalResult()
        }

        let activeProcess = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let activeRunner = CodexExecControlledRunner(process: activeProcess)
        activeRunner.initialLines = [#"{"type":"thread.started","thread_id":"active-thread"}"#]
        let activeAcquisition = Task {
            try await CodexExecProcessController(
                runner: activeRunner.run,
                registry: registry,
                retentionCapacity: 2,
            ).acquire(runID: "active", command: command)
        }
        await activeRunner.waitUntilReady()
        let activeReceipt = try await activeAcquisition.value

        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 3)
        XCTAssertEqual(processes[0].terminationCount, 1)
        XCTAssertEqual(processes[0].cleanupCount, 1)
        XCTAssertEqual(processes[1].cleanupCount, 0)
        XCTAssertEqual(processes[2].cleanupCount, 0)
        await activeReceipt.cancel()
    }

    /// ATI-008-observe_external_agent_results: post-handshake producer failures retain zero-consumer runs within
    /// capacity.
    /// public consumer가 없는 post-handshake 실패도 bounded retention과 oldest eviction을 수행하는지 검증합니다.
    /// - 검증 내용: retention capacity 1, decoder/process failure 두 run, 첫 process의 단일 terminate/cleanup과 fresh count 1을
    /// 확인합니다.
    /// - 사전 조건: 두 fake process가 handshake 후 각각 decoder failure와 non-zero process failure를 발생시킵니다.
    /// - 기대 결과: 첫 run은 eviction되고 두 번째 run만 retained 됩니다.
    func testRetention_postHandshakeProducerFailuresEvictOldestWithoutConsumers() async throws {
        let registry = CodexExecProcessRegistry(retentionCapacity: 1)
        let first = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-first"}"#.utf8),
                Data("{bad}".utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let firstEvicted = XCTestExpectation(description: "first producer evicted")
        first.onCleanup = { firstEvicted.fulfill() }
        let second = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-second"}"#.utf8)],
            stderr: [],
            terminationStatus: 9,
        )
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let firstController = CodexExecProcessController(
            runner: CodexExecFakeRunner(process: first).run,
            registry: registry,
            retentionCapacity: 1,
        )
        let secondController = CodexExecProcessController(
            runner: CodexExecFakeRunner(process: second).run,
            registry: registry,
            retentionCapacity: 1,
        )
        let firstFinished = XCTestExpectation(description: "first producer finished")
        _ = try await firstController.acquire(
            runID: "first",
            command: command,
            onProducerFinished: {
                firstFinished.fulfill()
            },
        )
        await fulfillment(of: [firstFinished], timeout: 1)
        _ = try await secondController.acquire(runID: "second", command: command)
        await fulfillment(of: [firstEvicted], timeout: 1)
        let counts = await firstController.debugRegistryCounts()
        XCTAssertEqual(first.terminationCount, 1)
        XCTAssertEqual(first.cleanupCount, 1)
        XCTAssertEqual(counts.fresh, 1)
    }

    /// ATI-008-observe_external_agent_results: malformed and incomplete frames fail distinctly.
    /// 외부 에이전트 결과 관찰 중 malformed frame과 stream 종료 incomplete frame을 구분하는지 검증합니다.
    /// - 검증 내용: newline frame의 malformed 오류와 남은 partial frame의 incomplete 오류를 확인합니다.
    /// - 사전 조건: malformed JSONL 한 줄과 newline 없는 partial JSONL을 각각 제공합니다.
    /// - 기대 결과: 첫 입력은 malformedFrame, 종료 시 partial 입력은 incompleteFrame입니다.
    func testDecode_malformedAndIncompleteFrames_haveDistinctErrors() throws {
        var malformed = CodexExecJSONLDecoder()
        XCTAssertThrowsError(try malformed.append(Data("{not-json}\n".utf8))) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .malformedFrame)
        }

        var malformedKnown = CodexExecJSONLDecoder()
        XCTAssertThrowsError(
            try malformedKnown
                .append(Data("{\"type\":\"thread.started\",\"thread_id\":17}\n".utf8)),
        ) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .malformedFrame)
        }

        var incomplete = CodexExecJSONLDecoder()
        _ = try incomplete.append(Data("{\"type\":\"thread.started\"".utf8))
        XCTAssertThrowsError(try incomplete.finish()) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .incompleteFrame)
        }
    }

    /// ATI-008-observe_external_agent_results: EOF preserves semantic malformed frames.
    /// JSON이 닫혔지만 known event payload 계약을 위반한 frame은 truncation으로 완화하지 않는지 검증합니다.
    /// - 검증 내용: semantic malformed frame은 finish에서도 malformedFrame으로 유지되는지 확인합니다.
    /// - 사전 조건: 닫힌 JSON object에 known event의 잘못된 scalar payload가 newline 없이 제공됩니다.
    /// - 기대 결과: EOF 결과가 incompleteFrame이 아닌 malformedFrame입니다.
    func testDecode_eofSemanticMalformedFrame_remainsMalformed() throws {
        var decoder = CodexExecJSONLDecoder()
        _ = try decoder.append(Data(#"{"type":"thread.started","thread_id":17}"#.utf8))

        XCTAssertThrowsError(try decoder.finish()) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .malformedFrame)
        }
    }

    /// ATI-008-observe_external_agent_results: conflicting item type projections are malformed.
    /// known event의 top-level과 nested item type이 충돌할 때 임의의 한 값을 선택하지 않는지 검증합니다.
    /// - 검증 내용: 충돌 거부, matching duplicate 수용, unknown arbitrary payload 보존을 확인합니다.
    /// - 사전 조건: item.started known event와 future unknown event에 top-level/nested item type을 섞어 제공합니다.
    /// - 기대 결과: known 충돌만 malformedFrame이고 matching duplicate와 unknown payload는 기존 의미를 유지합니다.
    func testDecode_itemTypeProjection_conflictIsMalformedMatchingIsAcceptedUnknownIsUntouched() throws {
        var conflicting = CodexExecJSONLDecoder()
        XCTAssertThrowsError(
            try conflicting.append(
                Data(
                    (#"{"type":"item.started","item_type":"command","item":{"type":"file_change"}}"# + "\n").utf8,
                ),
            ),
        ) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .malformedFrame)
        }

        var matching = CodexExecJSONLDecoder()
        let matchingOutcomes = try matching.append(
            Data(
                (#"{"type":"item.started","item_type":"command","item":{"type":"command"}}"# + "\n").utf8,
            ),
        )
        guard let matchingOutcome = matchingOutcomes.first,
              case let .event(event) = matchingOutcome
        else {
            return XCTFail("matching duplicate item type should decode as an event")
        }
        XCTAssertEqual(event.payload.itemType, "command")

        var unknown = CodexExecJSONLDecoder()
        let unknownOutcomes = try unknown.append(
            Data(
                (#"{"type":"future/event","item_type":"command","item":{"type":17,"arbitrary":[true]}}"# + "\n").utf8,
            ),
        )
        guard let unknownOutcome = unknownOutcomes.first,
              case .unknown(type: "future/event") = unknownOutcome
        else {
            return XCTFail("unknown arbitrary payload should remain unknown")
        }
    }

    // MARK: - ATI-008-malformed_nested_scalars

    /// ATI-008-malformed_nested_scalars: malformed known nested scalar fields fail decoding.
    /// 알려진 event의 nested scalar type이 잘못되면 성공 event로 투영하지 않는지 검증합니다.
    /// - 검증 내용: turn id/status와 item id/type/text/status의 invalid scalar type을 malformedFrame으로 거부하는지 확인합니다.
    /// - 사전 조건: known event의 nested object에 숫자 또는 boolean scalar를 제공합니다.
    /// - 기대 결과: 각 frame이 malformedFrame으로 거부됩니다.
    func testDecode_knownNestedScalarTypeMismatch_isMalformed() throws {
        let cases = [
            #"{"type":"turn.completed","turn":{"id":123,"status":false}}"#,
            #"{"type":"item.completed","item":{"id":123,"type":false,"text":17}}"#,
        ]

        for line in cases {
            var decoder = CodexExecJSONLDecoder()
            XCTAssertThrowsError(try decoder.append(Data((line + "\n").utf8))) { error in
                XCTAssertEqual(error as? CodexExecDecodeError, .malformedFrame, line)
            }
        }
    }

    /// ATI-008-observe_external_agent_results: unknown evidence is bounded by unique types and total count.
    /// 알 수 없는 provider event가 diagnostics를 무한히 성장시키지 않는지 검증합니다.
    /// - 검증 내용: unique type cap 32와 total count cap 128을 동시에 확인합니다.
    /// - 사전 조건: 40개 unique unknown event와 추가 반복 event를 JSONL로 제공합니다.
    /// - 기대 결과: 처음 32개 type만 보존되고 총 unknown count는 128에서 멈춥니다.
    func testDecode_unknownEvents_boundUniqueTypesAndTotalCount() throws {
        let unique = (0 ..< 40).map { #"{"type":"unknown-"# + String($0) + #""}"# }
        let repeated = Array(repeating: #"{"type":"unknown-0"}"#, count: 100)
        let result = try CodexExecTestHarness.feed(unique + repeated)

        XCTAssertEqual(
            result.diagnostics.unknown.types.count,
            CodexExecDiagnosticsBuilder.maximumUnknownTypes,
        )
        XCTAssertEqual(
            result.diagnostics.unknown.totalCount,
            CodexExecDiagnosticsBuilder.maximumUnknownCount,
        )
        XCTAssertEqual(result.diagnostics.unknown.types, (0 ..< 32).map { "unknown-\($0)" })
    }

    /// ATI-008-observe_external_agent_results: future event payload shapes remain unknown evidence.
    /// 미래 JSONL event의 임의 payload가 malformed가 아닌 bounded unknown evidence로 보존되는지 검증합니다.
    /// - 검증 내용: handshake 뒤 배열 payload를 unknown으로 분류하고 type/count evidence를 확인합니다.
    /// - 사전 조건: 유효한 thread.started handshake와 배열 item payload를 제공합니다.
    /// - 기대 결과: future/event가 unknown으로 반환되고 type/count evidence가 1씩 증가합니다.
    func testDecode_futureEventWithArbitraryPayload_isUnknownWithBoundedEvidence() throws {
        var decoder = CodexExecJSONLDecoder()
        let outcomes = try decoder.append(
            Data(
                ("{\"type\":\"thread.started\",\"thread_id\":\"thread-future\"}\n"
                    + "{\"type\":\"future/event\",\"item\":[]}\n").utf8,
            ),
        )

        XCTAssertEqual(outcomes.count, 2)
        guard case .unknown(type: "future/event") = outcomes[1] else {
            return XCTFail("future event should be classified as unknown")
        }
        XCTAssertEqual(decoder.diagnostics.unknown.types, ["future/event"])
        XCTAssertEqual(decoder.diagnostics.unknown.totalCount, 1)
    }

    /// ATI-008-observe_external_agent_results: raw line bounds are byte-based and exact maximum is accepted.
    /// JSONL raw line 제한이 Unicode scalar가 아닌 UTF-8 byte 수로 적용되는지 검증합니다.
    /// - 검증 내용: 정확히 1 MiB인 valid frame의 수용과 1 byte 초과 frame의 거부를 확인합니다.
    /// - 사전 조건: ASCII text payload로 raw line byte 길이를 정확히 조정합니다.
    /// - 기대 결과: maximumRawLineBytes frame은 decode되고 초과 frame은 rawLineTooLarge입니다.
    func testDecode_rawLineLimit_isMeasuredInBytes() throws {
        let prefix = "{\"type\":\"thread.started\",\"text\":\""
        let suffix = "\"}"
        let payload = String(
            repeating: "x",
            count: CodexExecJSONLDecoder.maximumRawLineBytes - prefix.utf8.count - suffix.utf8.count,
        )
        let exactLine = prefix + payload + suffix
        XCTAssertEqual(Data(exactLine.utf8).count, CodexExecJSONLDecoder.maximumRawLineBytes)
        XCTAssertEqual(try CodexExecTestHarness.feed([exactLine]).events.count, 1)

        var oversized = CodexExecJSONLDecoder()
        XCTAssertThrowsError(
            try oversized.append(
                Data(
                    repeating: 0x78,
                    count: CodexExecJSONLDecoder.maximumRawLineBytes + 1,
                ),
            ),
        ) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .rawLineTooLarge)
        }
    }

    /// ATI-008-observe_external_agent_results: a large read chunk may contain many small valid lines.
    /// availableData chunk 크기가 raw line 제한을 우회적으로 적용하지 않는지 검증합니다.
    /// - 검증 내용: 1 MiB보다 큰 하나의 chunk 안의 유효한 JSONL frame들이 순서대로 수용되는지 확인합니다.
    /// - 사전 조건: 각 frame은 제한보다 작고 전체 chunk만 1 MiB를 초과합니다.
    /// - 기대 결과: 모든 frame이 입력 순서대로 decode되고 chunk 크기 오류가 발생하지 않습니다.
    func testDecode_largeChunkOfSmallFrames_isAcceptedInOrder() throws {
        let lines = (0 ..< 50000).map { index in
            "{\"type\":\"unknown-\(index)\"}"
        }
        let input = Data((lines.joined(separator: "\n") + "\n").utf8)
        XCTAssertGreaterThan(input.count, CodexExecJSONLDecoder.maximumRawLineBytes)

        var decoder = CodexExecJSONLDecoder()
        let outcomes = try decoder.append(input)
        XCTAssertEqual(outcomes.count, lines.count)
        XCTAssertEqual(
            decoder.diagnostics.unknown.totalCount,
            CodexExecDiagnosticsBuilder.maximumUnknownCount,
        )
    }

    /// ATI-008-observe_external_agent_results: final assistant text is deduplicated and bounded.
    /// item.updated delta와 item.completed full text가 중복되지 않고 retained text cap을 지키는지 검증합니다.
    /// - 검증 내용: 동일 item의 update 후 completion replacement와 UTF-8 byte bound를 확인합니다.
    /// - 사전 조건: 동일 agent_message item에 128 KiB delta와 짧은 completion text를 제공합니다.
    /// - 기대 결과: finalAssistantText는 completion을 한 번만 보존하고 최대 byte 제한을 넘지 않습니다.
    func testDecode_updatedThenCompletedText_isReplacedAndBounded() throws {
        let oversizedText = String(
            repeating: "x",
            count: CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
        var decoder = CodexExecJSONLDecoder()
        _ = try decoder.append(
            Data(
                "{\"type\":\"item.updated\",\"item_id\":\"message-1\",\"item_type\":\"agent_message\",\"delta\":\"\(oversizedText)\"}\n"
                    .utf8,
            ),
        )
        _ = try decoder.append(
            Data(
                (#"{"type":"item.completed","item":{"id":"message-1","type":"agent_message","text":"final"}}"#
                    + "\n").utf8,
            ),
        )
        XCTAssertEqual(decoder.finalAssistantText.value, "final")
        XCTAssertEqual(decoder.retainedFinalTextByteCount, 5)

        let reusableText = String(
            repeating: "y",
            count: CodexExecJSONLDecoder.maximumFinalAssistantTextBytes - 5,
        )
        _ = try decoder.append(
            Data(
                "{\"type\":\"item.completed\",\"item\":{\"id\":\"message-2\",\"type\":\"agent_message\",\"text\":\"\(reusableText)\"}}\n"
                    .utf8,
            ),
        )
        XCTAssertEqual(
            decoder.retainedFinalTextByteCount,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
        XCTAssertTrue(decoder.finalAssistantText.value.hasPrefix("final"))
        XCTAssertEqual(
            Data(decoder.finalAssistantText.value.utf8).count,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
    }

    /// ATI-008-observe_external_agent_results: camelCase agent messages retain completed text like snake_case messages.
    /// 두 wire item type 표기가 동일한 keyed delta/completion replacement 규칙을 사용하는지 검증합니다.
    /// - 검증 내용: camelCase update와 completion이 bounded authoritative finalAssistantText를 보존하는지 확인합니다.
    /// - 사전 조건: 같은 item ID에 camelCase delta와 completed text를 순서대로 제공합니다.
    /// - 기대 결과: delta가 completed text로 정확히 교체되고 retained byte accounting이 일치합니다.
    func testDecode_camelCaseUpdatedThenCompletedText_isReplacedAndBounded() throws {
        var decoder = CodexExecJSONLDecoder()
        _ = try decoder.append(
            Data(
                (#"{"type":"item.updated","item_id":"message-camel","item_type":"agentMessage","delta":"draft"}"#
                    + "\n")
                    .utf8,
            ),
        )
        _ = try decoder.append(
            Data(
                (#"{"type":"item.completed","item":{"id":"message-camel","type":"agentMessage","text":"authoritative"}}"#
                    + "\n").utf8,
            ),
        )

        XCTAssertEqual(decoder.finalAssistantText.value, "authoritative")
        XCTAssertEqual(decoder.retainedFinalTextByteCount, "authoritative".utf8.count)
    }

    /// ATI-008-observe_external_agent_results: text retention backs off to the longest valid UTF-8 prefix.
    /// 128 KiB byte cut이 multibyte scalar 중간에 걸려도 유효한 prefix를 보존하는지 검증합니다.
    /// - 검증 내용: ASCII max-1 byte prefix의 non-empty exact length와 replacement character 부재를 확인합니다.
    /// - 사전 조건: max-1 ASCII bytes 뒤에 UTF-8 3-byte scalar 한을 배치합니다.
    /// - 기대 결과: retained text는 ASCII prefix 전체이고 byte 수는 max-1입니다.
    func testDecode_finalAssistantText_truncatesToLongestValidUTF8Prefix() throws {
        let ascii = String(
            repeating: "a",
            count: CodexExecJSONLDecoder.maximumFinalAssistantTextBytes - 1,
        )
        let text = ascii + "한"
        var decoder = CodexExecJSONLDecoder()
        _ = try decoder.append(
            Data(
                (#"{"type":"item.completed","item":{"type":"agent_message","text":""# + text + #""}}"#
                    + "\n").utf8,
            ),
        )

        XCTAssertFalse(decoder.finalAssistantText.value.isEmpty)
        XCTAssertEqual(decoder.finalAssistantText.value, ascii)
        XCTAssertEqual(decoder.finalAssistantText.value.utf8.count, ascii.utf8.count)
        XCTAssertFalse(decoder.finalAssistantText.value.contains("�"))
    }

    /// ATI-008-observe_external_agent_results: stderr bounding keeps the longest valid UTF-8 prefix.
    /// stderr byte bound가 multibyte scalar 중간에서 잘려도 replacement scalar 없이 보존되는지 검증합니다.
    /// - 검증 내용: maximumStderrBytes - 1 ASCII prefix의 non-empty exact byte count와 redaction semantics를 확인합니다.
    /// - 사전 조건: ASCII prefix 뒤에 3-byte scalar 한을 배치하고 bearer secret을 포함합니다.
    /// - 기대 결과: ASCII prefix만 반환되고 replacement scalar와 raw secret은 없습니다.
    func testDiagnostics_stderrBoundTruncatesToLongestValidUTF8Prefix() {
        let ascii = String(repeating: "a", count: CodexExecDiagnosticsBuilder.maximumStderrBytes - 1)
        let input = ascii + "한 bearer secret"
        let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(input)

        XCTAssertFalse(output.isEmpty)
        XCTAssertEqual(output.utf8.count, ascii.utf8.count)
        XCTAssertEqual(output, ascii)
        XCTAssertFalse(output.contains("�"))
        XCTAssertFalse(output.contains("secret"))
    }

    /// ATI-008-observe_external_agent_results: lifecycle count overflow fails before event-stream claim.
    /// handshake 후 eventStream claim 전 lifecycle event 개수가 정확히 128개로 제한되는지 검증합니다.
    /// - 검증 내용: 129번째 decoded lifecycle event의 typed overflow, 단일 terminate/cleanup, registry 정리를 확인합니다.
    /// - 사전 조건: controlled fake process가 handshake 뒤 129개 turn.started를 방출하고 eventStream은 claim하지 않습니다.
    /// - 기대 결과: terminal result가 eventBufferOverflow로 실패하고 process와 registry가 한 번 정리됩니다.
    func testController_preEventStreamLifecycleCountOverflow_isTypedAndCleansOnce() async throws {
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
            try await controller.acquire(runID: "count-overflow", command: command)
        }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-count"}"#)
        let receipt = try await acquisition.value
        for _ in 0 ..< 129 {
            runner.send(#"{"type":"turn.started"}"#)
        }

        do {
            _ = try await receipt.terminalResult()
            XCTFail("129 pre-event-stream lifecycle events should overflow")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .eventBufferOverflow)
        }
        await receipt.cancel()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: lifecycle byte overflow fails before event-stream claim.
    /// handshake 후 eventStream claim 전 encoded lifecycle bytes가 정확히 1 MiB로 제한되는지 검증합니다.
    /// - 검증 내용: count limit 전에 aggregate framed bytes를 초과하는 typed failure와 단일 cleanup을 확인합니다.
    /// - 사전 조건: 128개 미만의 individually valid sub-limit turn.started frame이 aggregate 1 MiB를 초과합니다.
    /// - 기대 결과: terminal result가 encodedEventBufferOverflow로 실패하고 process가 한 번 정리됩니다.
    func testController_preEventStreamLifecycleByteOverflow_isTypedAndCleansOnce() async throws {
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
            try await controller.acquire(runID: "byte-overflow", command: command)
        }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-byte"}"#)
        let receipt = try await acquisition.value
        let padding = String(repeating: "x", count: 9000)
        for _ in 0 ..< 128 {
            runner.send("{\"type\":\"turn.started\",\"message\":\"\(padding)\"}")
        }

        do {
            _ = try await receipt.terminalResult()
            XCTFail("pre-event-stream lifecycle bytes should overflow")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .encodedEventBufferOverflow)
        }
        await receipt.cancel()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: live stderr split at the raw byte bound stays valid and redacted.
    /// 실제 controller stderr collector가 4-byte scalar의 경계 분할에서도 replacement 없이 진단을 보존하는지 검증합니다.
    /// - 검증 내용: provider-internal stderr의 strict UTF-8, non-empty bound, secret redaction과 public outcome을 확인합니다.
    /// - 사전 조건: fake process stderr가 maximumStderrBytes 경계에서 scalar를 3 bytes만 포함하도록 방출합니다.
    /// - 기대 결과: diagnostics는 valid prefix와 redaction marker를 유지하고 terminal outcome은 completed입니다.
    func testController_liveStderrSplitAtBound_preservesStrictUTF8AndRedaction() async throws {
        let scalar = "𐍈"
        let prefix =
            "Bearer split-secret "
                + String(repeating: "a", count: CodexExecDiagnosticsBuilder.maximumStderrBytes - 3 - 20)
        XCTAssertEqual(
            prefix.utf8.count + scalar.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes + 1,
        )
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-stderr"}"#.utf8),
                Data(#"{"type":"turn.completed"}"#.utf8),
            ],
            stderr: [Data(prefix.utf8), Data(scalar.utf8)],
            terminationStatus: 0,
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
        .acquire(runID: "stderr-split", command: command)
        let terminal = try await receipt.terminalResult()
        XCTAssertEqual(terminal.outcome, .completed)
        XCTAssertFalse(terminal.diagnostics.stderr.isEmpty)
        XCTAssertLessThanOrEqual(
            terminal.diagnostics.stderr.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )
        XCTAssertFalse(terminal.diagnostics.stderr.contains("�"))
        XCTAssertFalse(terminal.diagnostics.stderr.contains("split-secret"))
        XCTAssertTrue(terminal.diagnostics.stderr.contains("[REDACTED]"))
    }

    /// ATI-008-observe_external_agent_results: unique item text retention is bounded.
    /// provider가 unique agent item을 무한히 보내도 decoder 내부 item state가 제한되는지 검증합니다.
    /// - 검증 내용: maximumFinalAssistantItems를 초과하는 unique item update의 typed failure를 확인합니다.
    /// - 사전 조건: 제한보다 하나 많은 unique agent_message item.updated frame을 제공합니다.
    /// - 기대 결과: decoder가 finalAssistantItemLimit으로 중단되고 hidden state를 추가 보유하지 않습니다.
    func testDecode_uniqueItemTextRetention_isBounded() throws {
        let lines = (0 ... CodexExecJSONLDecoder.maximumFinalAssistantItems).map { index in
            "{\"type\":\"item.updated\",\"item_id\":\"message-\(index)\",\"item_type\":\"agent_message\",\"delta\":\"x\"}"
        }
        var decoder = CodexExecJSONLDecoder()
        XCTAssertThrowsError(try decoder.append(Data((lines.joined(separator: "\n") + "\n").utf8))) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .finalAssistantItemLimit)
        }
        XCTAssertLessThanOrEqual(
            decoder.finalAssistantText.value.utf8.count,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
    }

    /// ATI-008-observe_external_agent_results: unkeyed assistant text is retained.
    /// item ID가 없는 assistant text도 keyed text와 같은 final text 계약에 포함되는지 검증합니다.
    /// - 검증 내용: unkeyed-only, keyed 전후 unkeyed, 다중 unkeyed 순서와 byte accounting을 확인합니다.
    /// - 사전 조건: agent_message item.completed frame에 item ID 유무를 섞어 제공합니다.
    /// - 기대 결과: 도착 순서대로 모든 text가 finalAssistantText와 retained byte count에 반영됩니다.
    func testDecode_unkeyedAssistantText_isRetainedInArrivalOrder() throws {
        var decoder = CodexExecJSONLDecoder()
        let lines = [
            #"{"type":"item.completed","item_type":"agent_message","text":"unkeyed"}"#,
            #"{"type":"item.completed","item":{"id":"keyed","type":"agent_message","text":"keyed"}}"#,
            #"{"type":"item.completed","item_type":"agent_message","text":" tail"}"#,
        ]
        _ = try decoder.append(Data((lines.joined(separator: "\n") + "\n").utf8))

        XCTAssertEqual(decoder.finalAssistantText.value, "unkeyedkeyed tail")
        XCTAssertEqual(decoder.retainedFinalTextByteCount, "unkeyedkeyed tail".utf8.count)
    }

    /// ATI-008-observe_external_agent_results: multiple unkeyed fragments preserve order.
    /// item ID가 없는 여러 fragment를 replacement가 아닌 arrival-order append semantics로 보존하는지 검증합니다.
    /// - 검증 내용: 세 unkeyed fragment의 순서와 aggregate byte count를 확인합니다.
    /// - 사전 조건: 서로 다른 text를 가진 unkeyed agent_message frame 세 개를 제공합니다.
    /// - 기대 결과: fragment가 입력 순서대로 연결되고 각 fragment byte가 모두 retained 됩니다.
    func testDecode_multipleUnkeyedAssistantFragments_preserveOrder() throws {
        var decoder = CodexExecJSONLDecoder()
        let lines = ["one", "two", "three"].map {
            #"{"type":"item.updated","item_type":"agent_message","delta":""# + $0 + #""}"#
        }
        let input = lines.joined(separator: "\n") + "\n"
        _ = try decoder.append(Data(input.utf8))

        XCTAssertEqual(decoder.finalAssistantText.value, "onetwothree")
        XCTAssertEqual(decoder.retainedFinalTextByteCount, 11)
    }

    /// ATI-008-observe_external_agent_results: mixed text uses one exact UTF-8 bound.
    /// keyed와 unkeyed contribution이 하나의 128 KiB budget을 공유하는지 검증합니다.
    /// - 검증 내용: bound 직전까지 보존하고 초과 text는 정확히 잘리는지 확인합니다.
    /// - 사전 조건: keyed text와 unkeyed text의 합이 cap을 1 byte 초과합니다.
    /// - 기대 결과: typed error 없이 cap만큼 보존되고 retained byte count가 정확히 cap입니다.
    func testDecode_mixedAssistantText_usesExactAggregateBound() throws {
        let first = String(
            repeating: "a",
            count: CodexExecJSONLDecoder.maximumFinalAssistantTextBytes - 2,
        )
        let second = "xyz"
        var decoder = CodexExecJSONLDecoder()
        _ = try decoder.append(
            Data(
                ([
                    #"{"type":"item.completed","item":{"id":"keyed","type":"agent_message","text":""# + first
                        + #""}}"#,
                    #"{"type":"item.completed","item_type":"agent_message","text":""# + second + #""}"#,
                ].joined(separator: "\n") + "\n").utf8,
            ),
        )

        XCTAssertEqual(
            decoder.retainedFinalTextByteCount,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
        XCTAssertEqual(
            decoder.finalAssistantText.value.utf8.count,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
        XCTAssertEqual(decoder.finalAssistantText.value, first + "xy")
    }

    /// ATI-008-observe_external_agent_results: replacing keyed text releases bytes for unkeyed text.
    /// keyed delta가 authoritative completion으로 교체될 때 반환된 budget을 unkeyed text가 재사용하는지 검증합니다.
    /// - 검증 내용: delta byte 해제, completion replacement, unkeyed 재사용과 최종 합계를 확인합니다.
    /// - 사전 조건: cap을 채우는 keyed delta 후 짧은 completion과 unkeyed text를 제공합니다.
    /// - 기대 결과: completion replacement 뒤 unkeyed text가 들어가고 retained byte count는 cap입니다.
    func testDecode_keyedCompletion_releasesBytesForUnkeyedText() throws {
        let delta = String(repeating: "d", count: CodexExecJSONLDecoder.maximumFinalAssistantTextBytes)
        var decoder = CodexExecJSONLDecoder()
        _ = try decoder.append(
            Data(
                ([
                    #"{"type":"item.updated","item_id":"keyed","item_type":"agent_message","delta":""# + delta
                        + #""}"#,
                    #"{"type":"item.completed","item":{"id":"keyed","type":"agent_message","text":"done"}}"#,
                    #"{"type":"item.completed","item_type":"agent_message","text":""#
                        + String(
                            repeating: "u",
                            count: CodexExecJSONLDecoder.maximumFinalAssistantTextBytes - 4,
                        )
                        + #""}"#,
                ].joined(separator: "\n") + "\n").utf8,
            ),
        )

        XCTAssertEqual(decoder.finalAssistantText.value.prefix(4), "done")
        XCTAssertEqual(
            decoder.retainedFinalTextByteCount,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
        XCTAssertEqual(
            decoder.finalAssistantText.value.utf8.count,
            CodexExecJSONLDecoder.maximumFinalAssistantTextBytes,
        )
    }

    /// ATI-008-observe_external_agent_results: unkeyed fragment count is bounded.
    /// unkeyed frame 수가 기존 assistant item bound를 우회해 내부 state를 무한히 늘리지 않는지 검증합니다.
    /// - 검증 내용: maximumFinalAssistantItems를 초과하는 unkeyed fragment가 typed error를 내는지 확인합니다.
    /// - 사전 조건: cap보다 하나 많은 unkeyed agent_message frame을 제공합니다.
    /// - 기대 결과: finalAssistantItemLimit으로 중단됩니다.
    func testDecode_unkeyedAssistantFragments_areBounded() throws {
        let lines = (0 ... CodexExecJSONLDecoder.maximumFinalAssistantItems).map { index in
            #"{"type":"item.completed","item_type":"agent_message","text":""# + String(index) + #""}"#
        }
        var decoder = CodexExecJSONLDecoder()

        XCTAssertThrowsError(try decoder.append(Data((lines.joined(separator: "\n") + "\n").utf8))) { error in
            XCTAssertEqual(error as? CodexExecDecodeError, .finalAssistantItemLimit)
        }
    }

    /// ATI-008-observe_external_agent_results: stderr is redacted and bounded in UTF-8 bytes.
    /// provider stderr diagnostics가 secret과 local path를 노출하지 않고 byte 제한을 지키는지 검증합니다.
    /// - 검증 내용: bearer/token/path redaction과 128 KiB byte bound를 확인합니다.
    /// - 사전 조건: secret, private path, 그리고 제한을 넘는 ASCII stderr가 입력됩니다.
    /// - 기대 결과: 원문 secret/path는 없고 redaction marker가 있으며 결과 byte 수는 제한 이하입니다.
    func testDiagnostics_stderr_isRedactedAndBoundedByBytes() {
        var decoder = CodexExecJSONLDecoder()
        decoder.retainStderr("Bearer super-secret access_token=also-secret /Users/private/file.txt ")
        decoder.retainStderr(
            String(repeating: "x", count: CodexExecDiagnosticsBuilder.maximumStderrBytes),
        )

        XCTAssertFalse(decoder.diagnostics.stderr.contains("super-secret"))
        XCTAssertFalse(decoder.diagnostics.stderr.contains("also-secret"))
        XCTAssertFalse(decoder.diagnostics.stderr.contains("/Users/private"))
        XCTAssertTrue(decoder.diagnostics.stderr.contains("[REDACTED]"))
        XCTAssertTrue(decoder.diagnostics.stderr.contains("[PATH REDACTED]"))
        XCTAssertLessThanOrEqual(
            Data(decoder.diagnostics.stderr.utf8).count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )

        decoder.reset()
        let redactedBearer = "Bearer [REDACTED]"
        let bearerPrefix = String(
            repeating: "x",
            count: CodexExecDiagnosticsBuilder.maximumStderrBytes - redactedBearer.utf8.count,
        )
        decoder.retainStderr(bearerPrefix + "Bearer beyond-bound-secret")
        XCTAssertTrue(decoder.diagnostics.stderr.hasSuffix(redactedBearer))
        XCTAssertFalse(decoder.diagnostics.stderr.contains("beyond-bound-secret"))

        decoder.reset()
        let redactedPath = "[PATH REDACTED]"
        let pathPrefix = String(
            repeating: "x",
            count: CodexExecDiagnosticsBuilder.maximumStderrBytes - redactedPath.utf8.count,
        )
        decoder.retainStderr(pathPrefix + "/Users/private/beyond-bound.txt")
        XCTAssertTrue(decoder.diagnostics.stderr.hasSuffix(redactedPath))
        XCTAssertFalse(decoder.diagnostics.stderr.contains("beyond-bound.txt"))
    }

    /// ATI-008-observe_external_agent_results: common secret and mounted paths redact before the byte bound.
    /// diagnostics가 common environment secret과 mounted path를 경계 이전에 제거하는지 검증합니다.
    /// - 검증 내용: API key 변형, secret/password/CODEX_HOME, Volumes/Network 경로와 boundary marker를 확인합니다.
    /// - 사전 조건: separators가 다른 synthetic secret과 경계 근처 및 경계를 넘는 민감한 값을 제공합니다.
    /// - 기대 결과: raw 값은 없고 marker가 남으며 결과는 valid UTF-8이고 maximumStderrBytes 이하입니다.
    func testDiagnostics_commonSecretsAndMountedPaths_areRedactedBeforeBound() {
        let examples = [
            "OPENAI_API_KEY=sk-live",
            "ANTHROPIC_API_KEY: anthropic-placeholder",
            "api_key=lowercase-placeholder",
            "secret: secret-placeholder",
            "password=password-placeholder",
            "CODEX_HOME=/Users/private/codex-placeholder",
            "/Volumes/Secret/project",
            "/Network/Secret/project",
            "normal text remains intact",
        ]
        let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(examples.joined(separator: " | "))

        for sensitive in [
            "sk-live", "anthropic-placeholder", "lowercase-placeholder", "secret-placeholder",
            "password-placeholder", "/Users/private/codex-placeholder", "/Volumes/Secret/project",
            "/Network/Secret/project",
        ] {
            XCTAssertFalse(output.contains(sensitive), output)
        }
        XCTAssertTrue(output.contains("normal text remains intact"), output)
        XCTAssertTrue(output.contains("[REDACTED]"), output)
        XCTAssertTrue(output.contains("[PATH REDACTED]"), output)

        let marker = "OPENAI_API_KEY=[REDACTED]"
        let boundaryInput =
            String(
                repeating: "x",
                count: CodexExecDiagnosticsBuilder.maximumStderrBytes - marker.utf8.count - 1,
            )
            + " " + marker.replacingOccurrences(of: "[REDACTED]", with: "sk-live")
        let boundaryOutput = CodexExecDiagnosticsBuilder.redactAndBoundStderr(boundaryInput)
        XCTAssertFalse(boundaryOutput.contains("sk-live"), boundaryOutput)
        XCTAssertTrue(boundaryOutput.hasSuffix("OPENAI_API_KEY=[REDACTED]"), boundaryOutput)
        XCTAssertNotNil(String(data: Data(boundaryOutput.utf8), encoding: .utf8))
        XCTAssertLessThanOrEqual(
            boundaryOutput.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )

        let pathMarker = "[PATH REDACTED]"
        let pathInput =
            String(
                repeating: "x",
                count: CodexExecDiagnosticsBuilder.maximumStderrBytes - pathMarker.utf8.count,
            )
            + "/Volumes/Secret/project"
        let pathOutput = CodexExecDiagnosticsBuilder.redactAndBoundStderr(pathInput)
        XCTAssertFalse(pathOutput.contains("/Volumes/Secret/project"), pathOutput)
        XCTAssertTrue(pathOutput.hasSuffix(pathMarker), pathOutput)
        XCTAssertLessThanOrEqual(pathOutput.utf8.count, CodexExecDiagnosticsBuilder.maximumStderrBytes)
    }

    /// ATI-008-observe_external_agent_results: mounted paths with spaces redact only through explicit boundaries.
    /// quoted 및 boundary-delimited mounted 경로 전체를 숨기고 뒤의 정상 진단 suffix를 보존하는지 검증합니다.
    /// - 검증 내용: Volumes/Network 경로의 quote, pipe, comma, semicolon, newline 경계를 확인합니다.
    /// - 사전 조건: 공백이 포함된 mounted path와 각 경계 뒤의 정상 suffix가 제공됩니다.
    /// - 기대 결과: 전체 민감 경로는 marker로 치환되고 suffix는 그대로 남습니다.
    func testDiagnostics_mountedPathsWithSpaces_requireExplicitBoundaryAndPreserveSuffix() {
        let cases = [
            #"quoted "/Volumes/Secret Folder/project.txt" suffix"#,
            #"quoted '/Network/Secret Folder/project.txt' suffix"#,
            "/Volumes/Secret Folder/project.txt|suffix",
            "/Network/Secret Folder/project.txt,suffix",
            "/Volumes/Secret Folder/project.txt;suffix",
            "/Network/Secret Folder/project.txt\nsuffix",
            "/Volumes/Secret Folder/project.txt\r\nnormal",
            "/Network/Secret Folder/project.txt\r\nnormal",
        ]

        for input in cases {
            let suffix = input.contains("normal") ? "normal" : "suffix"
            let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(input + suffix)
            XCTAssertFalse(output.contains("/Volumes/Secret Folder/project.txt"), output)
            XCTAssertFalse(output.contains("/Network/Secret Folder/project.txt"), output)
            XCTAssertFalse(output.contains("Secret Folder"), output)
            XCTAssertFalse(output.contains("project.txt"), output)
            XCTAssertTrue(output.contains(suffix), output)
        }
    }

    /// ATI-008-observe_external_agent_results: sensitive root paths and bearer tokens redact across explicit
    /// boundaries.
    /// 공백 경로와 alphabetic-only bearer credential이 경계 뒤 suffix를 보존하며 완전히 제거되는지 검증합니다.
    /// - 검증 내용: Users/private/var/tmp의 quote, pipe, comma, semicolon, CRLF/newline 경계를 확인합니다.
    /// - 사전 조건: 각 민감 경로와 Authorization Bearer ABCDEFGHI 입력을 제공합니다.
    /// - 기대 결과: 경로와 credential 원문은 없고 suffix와 redaction marker는 남습니다.
    func testDiagnostics_sensitivePathsAndBearerTokens_areFullyRedactedAtBoundaries() {
        let cases = [
            #"/Users/alice/private project/secret.txt|suffix"#,
            #"quoted "/private/private project/secret.txt" suffix"#,
            "/var/private project/secret.txt,suffix",
            "/tmp/private project/secret.txt;normal",
            "/Users/alice/private project/secret.txt\r\nnormal",
            "/private/private project/secret.txt\nnormal",
            "/var/private project/secret.txt\r\nnormal",
            "/tmp/private project/secret.txt\nnormal",
        ]

        for input in cases {
            let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(input)
            XCTAssertFalse(output.contains("private project/secret.txt"), output)
            XCTAssertTrue(output.contains(input.contains("normal") ? "normal" : "suffix"), output)
        }

        let bearer = CodexExecDiagnosticsBuilder.redactAndBoundStderr(
            "Authorization: Bearer ABCDEFGHI|suffix",
        )
        XCTAssertFalse(bearer.contains("ABCDEFGHI"), bearer)
        XCTAssertTrue(bearer.contains("suffix"), bearer)
    }

    /// ATI-008-observe_external_agent_results: direct alphabetic bearer credentials are redacted.
    /// bearer 뒤 token shape와 casing에 관계없이 credential이 진단에 남지 않는지 검증합니다.
    /// - 검증 내용: direct Bearer ABCDEFGHI와 mixed-case bearer 토큰의 raw 값 부재 및 prefix/marker 보존을 확인합니다.
    /// - 사전 조건: delimiter나 token/secret/key 접미사가 없는 alphabetic-only bearer credentials를 제공합니다.
    /// - 기대 결과: 각 credential 원문은 없고 Bearer prefix 또는 redaction marker는 남습니다.
    func testDiagnostics_directAlphabeticBearerCredentials_areRedactedRegardlessOfCase() throws {
        for input in ["Bearer ABCDEFGHI", "bearer AbCdEfGhI"] {
            let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(input)

            XCTAssertFalse(try output.contains(XCTUnwrap(input.split(separator: " ").last)), output)
            XCTAssertTrue(
                output.contains("Bearer") || output.contains("bearer") || output.contains("[REDACTED]"),
                output,
            )
        }
    }

    /// ATI-008-observe_external_agent_results: delimiter-based credential keys redact values without prose loss.
    /// client secret와 x-api-key 변형의 equals/colon credential 값만 제거하고 일반 문장을 보존하는지 검증합니다.
    /// - 검증 내용: client_secret, client-secret, x-api-key, x_api_key의 key-value redaction과 prose preservation을 확인합니다.
    /// - 사전 조건: 각 key의 equals/colon 형식과 credential 용어를 포함한 일반 문장을 제공합니다.
    /// - 기대 결과: 모든 credential 값은 제거되고 일반 문장은 원문으로 남습니다.
    func testDiagnostics_delimiterCredentialKeys_redactValuesWithoutOverRedactingProse() {
        let prose = "client secret rotation and x-api-key documentation remain readable"
        let input =
            prose + " client_secret=secret-one client_secret: secret-two"
                + " client-secret=secret-three client-secret: secret-four"
                + " x-api-key=key-five x-api-key: key-six x_api_key=key-seven x_api_key: key-eight"
        let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(input)

        XCTAssertTrue(output.contains(prose), output)
        for value in [
            "secret-one", "secret-two", "secret-three", "secret-four",
            "key-five", "key-six", "key-seven", "key-eight",
        ] {
            XCTAssertFalse(output.contains(value), output)
        }
        XCTAssertEqual(output.components(separatedBy: "[REDACTED]").count - 1, 8, output)
    }

    /// ATI-008-observe_external_agent_results: live stderr redacts before final bounding and preserves suffix
    /// diagnostics.
    /// real controller collector가 raw cap 이후의 normal diagnostic suffix를 redaction 후 보존하는지 검증합니다.
    /// - 검증 내용: long synthetic secret, redaction marker, suffix, strict UTF-8과 final byte bound를 확인합니다.
    /// - 사전 조건: raw retention 경계를 넘는 한 줄 secret과 opaque bearer 및 정상 suffix를 제공합니다.
    /// - 기대 결과: secret은 없고 marker와 suffix가 남으며 diagnostics는 유효한 UTF-8입니다.
    func testController_liveStderrRedactsBeforeBoundAndPreservesSuffix() async throws {
        let suffix = "normal diagnostic suffix retained after raw bound"
        let stderr =
            "OPENAI_API_KEY="
                + String(repeating: "s", count: CodexExecDiagnosticsBuilder.maximumStderrBytes * 3)
                + "\nAuthorization: Bearer AbCdEf123456\n"
                + suffix
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-redact-before-bound"}"#.utf8),
                Data(#"{"type":"turn.completed"}"#.utf8),
            ],
            stderr: [Data(stderr.utf8)],
            terminationStatus: 0,
        )
        let receipt = try await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: process).run,
        )
        .acquire(
            runID: "redact-before-bound",
            command: CodexExecCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
                arguments: [],
                environment: [:],
                stdin: "prompt",
            ),
        )

        let terminal = try await receipt.terminalResult()
        XCTAssertFalse(terminal.diagnostics.stderr.contains("AbCdEf123456"))
        XCTAssertFalse(terminal.diagnostics.stderr.contains(String(repeating: "s", count: 64)))
        XCTAssertTrue(terminal.diagnostics.stderr.contains("[REDACTED]"))
        XCTAssertTrue(terminal.diagnostics.stderr.contains("[TRUNCATED]"))
        XCTAssertTrue(terminal.diagnostics.stderr.contains(suffix))
        XCTAssertNotNil(String(data: Data(terminal.diagnostics.stderr.utf8), encoding: .utf8))
        XCTAssertLessThanOrEqual(
            terminal.diagnostics.stderr.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )
    }

    /// ATI-008-observe_external_agent_results: prose is not redacted without a key-value delimiter.
    /// 일반 diagnostic prose와 delimiter가 있는 sensitive values를 구분하는지 검증합니다.
    /// - 검증 내용: secret/password/bearer prose 보존과 sensitive key-value redaction을 확인합니다.
    /// - 사전 조건: 일반 문장과 equals/colon sensitive forms를 하나의 diagnostics 입력으로 제공합니다.
    /// - 기대 결과: 일반 문장은 원문이고 sensitive values만 marker로 치환됩니다.
    func testDiagnostics_sensitiveKeyValuesRedactWithoutOverRedactingProse() {
        let prose = "secret scanning enabled | password policy loaded | diagnostics documented"
        let sensitive =
            "secret=secret-placeholder secret: secret-placeholder password=password-placeholder "
                + "password: password-placeholder Bearer bearer-placeholder Bearer AbCdEf123456 "
                + "Authorization: Bearer ZyXwVu987654 GENERIC_API_KEY=key-placeholder "
                + "api_key=api-placeholder CODEX_HOME=/Volumes/Secret/project /Network/Secret/project"
        let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr(prose + " | " + sensitive)

        XCTAssertTrue(output.contains(prose), output)
        for raw in [
            "secret-placeholder", "password-placeholder", "bearer-placeholder", "AbCdEf123456",
            "ZyXwVu987654", "key-placeholder", "api-placeholder", "/Volumes/Secret/project",
            "/Network/Secret/project",
        ] {
            XCTAssertFalse(output.contains(raw), output)
        }
        XCTAssertTrue(output.contains("[REDACTED]"), output)
        XCTAssertTrue(output.contains("[PATH REDACTED]"), output)
    }

    /// ATI-008-observe_external_agent_results: short valid UTF-8 stderr is unchanged.
    /// byte limit보다 짧고 완전한 multibyte stderr가 불필요하게 잘리지 않는지 검증합니다.
    /// - 검증 내용: 한의 원문과 UTF-8 byte count가 그대로 보존되는지 확인합니다.
    /// - 사전 조건: redaction 대상이 아닌 짧은 multibyte stderr를 제공합니다.
    /// - 기대 결과: 반환 문자열이 입력과 정확히 같습니다.
    func testDiagnostics_shortMultibyteStderr_remainsUnchanged() {
        let output = CodexExecDiagnosticsBuilder.redactAndBoundStderr("한")

        XCTAssertEqual(output, "한")
        XCTAssertEqual(output.utf8.count, "한".utf8.count)
    }

    /// ATI-008-observe_external_agent_results: reset clears buffered data, diagnostics, and accumulated text.
    /// decoder 재사용 시 이전 결과가 다음 외부 에이전트 세션으로 누출되지 않는지 검증합니다.
    /// - 검증 내용: partial buffer, stderr, unknown evidence, final assistant text의 reset을 확인합니다.
    /// - 사전 조건: decoder에 partial frame과 diagnostics 및 agent text가 누적되어 있습니다.
    /// - 기대 결과: reset 이후 모든 상태가 초기값이고 새 frame을 독립적으로 decode합니다.
    func testDecoder_reset_clearsAllState() throws {
        var decoder = CodexExecJSONLDecoder()
        _ =
            try decoder
                .append(
                    Data(#"{"type":"item.completed","item":{"type":"agent_message","text":"old"}}"#.utf8)
                        + Data("\n".utf8),
                )
        _ = try decoder.append(Data(#"{"type":"old-unknown"}"#.utf8) + Data("\n".utf8))
        decoder.retainStderr("Bearer old-secret")
        _ = try decoder.append(Data("{\"type\":\"thread.started\"".utf8))

        decoder.reset()

        XCTAssertEqual(decoder.finalAssistantText.value, "")
        XCTAssertEqual(decoder.retainedFinalTextByteCount, 0)
        XCTAssertEqual(
            decoder.diagnostics,
            CodexExecDiagnostics(stderr: "", unknown: .init(types: [], totalCount: 0)),
        )
        XCTAssertEqual(try decoder.finish(), [])
        XCTAssertEqual(try decoder.append(Data("{\"type\":\"thread.started\"}\n".utf8)).count, 1)
    }

    /// ATI-008-observe_external_agent_results: terminal result can be consumed before the lifecycle stream.
    /// terminal cache가 stream보다 먼저 소비되어도 동일 run의 결과와 순서를 보존하는지 검증합니다.
    /// - 검증 내용: final text, lifecycle-only projection, ordinal 및 normalized IDs를 확인합니다.
    /// - 사전 조건: handshake, progress, agent message, turn.completed를 포함한 fake process가 있습니다.
    /// - 기대 결과: terminal과 stream은 각각 한 번 소비되고 progress 뒤 completed가 관찰됩니다.
    func testObserve_terminalBeforeStream_preservesCachedResultAndOrderedIDs() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"turn.started","turn_id":"turn-1"}"#.utf8),
                Data(#"{"type":"item.completed","item":{"type":"agent_message","text":"answer"}}"#.utf8),
                Data(#"{"type":"turn.completed","turn_id":"turn-1"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let receipt = try await CodexExecProcessController(runner: runner.run)
            .acquire(runID: "run-1", command: command)

        let result = try await receipt.terminalResult()
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.finalAssistantText.value, "answer")
        XCTAssertEqual(process.cleanupCount, 0)
        var events: [CodexExecLifecycleEvent] = []
        for try await event in try await receipt.eventStream() {
            events.append(event)
        }
        XCTAssertEqual(events.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(events.map(\.rawType), ["turn.started", "item.completed", "turn.completed"])
        XCTAssertEqual(events[0].providerEventID, "codex.exec/thread-1/turn.started/1")
        XCTAssertEqual(events[2].idempotencyKey, "codex.exec/run-1/3")
        XCTAssertEqual(process.cleanupCount, 1)
    }

    /// ATI-008-observe_external_agent_results: process exit precedence preserves explicit provider failure.
    /// completed terminal 뒤 non-zero process exit만 process failure로 대체하고 explicit failed terminal은 보존하는지 검증합니다.
    /// - 검증 내용: completed/non-zero는 exact processFailed status를 내고, failed/non-zero는 terminalError와 provider
    /// diagnostics를 유지하는지 확인합니다.
    /// - 사전 조건: 각 fake process가 thread.started 뒤 하나의 terminal JSONL을 방출하고 서로 다른 non-zero status로 종료합니다.
    /// - 기대 결과: 두 결과 모두 failed이며 각 process가 terminate와 cleanup을 한 번씩 수행합니다.
    func testObserve_processExitPrecedence_matrix() async throws {
        let cases = [
            ProcessExitCase(
                name: "completed terminal",
                terminal: #"{"type":"turn.completed","turn_id":"turn-completed"}"#,
                status: 17,
                failure: .processFailed(17),
                diagnostic: nil,
            ),
            ProcessExitCase(
                name: "explicit failed terminal",
                terminal: #"{"type":"turn.failed","turn_id":"turn-failed","message":"provider failure"}"#,
                status: 29,
                failure: .terminalError,
                diagnostic: "provider failure",
            ),
        ]

        for (index, testCase) in cases.enumerated() {
            try await assertProcessExitCase(testCase, index: index)
        }
    }

    private func assertProcessExitCase(_ testCase: ProcessExitCase, index: Int) async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data("{\"type\":\"thread.started\",\"thread_id\":\"thread-\(index)\"}".utf8),
                Data(testCase.terminal.utf8),
            ],
            stderr: [],
            terminationStatus: testCase.status,
        )
        let receipt = try await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: process).run,
        ).acquire(
            runID: "run-\(index)",
            command: makeCommand(),
        )

        let result = try await receipt.terminalResult()
        XCTAssertEqual(result.outcome, CodexExecLifecycleKind.failed, testCase.name)
        XCTAssertEqual(result.failure, testCase.failure, testCase.name)
        if let diagnostic = testCase.diagnostic {
            XCTAssertTrue(result.diagnostics.stderr.contains(diagnostic), testCase.name)
        }

        await receipt.cancel()
        XCTAssertEqual(process.terminationCount, 1, testCase.name)
        XCTAssertEqual(process.cleanupCount, 1, testCase.name)
    }

    private func makeCommand() -> CodexExecCommand {
        CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
    }

    /// ATI-008-observe_external_agent_results: completed process failure keeps lifecycle and result outcomes aligned.
    /// completed event가 process.wait 전에 노출되지 않아 non-zero 결과와 lifecycle이 divergence하지 않는지 검증합니다.
    /// - 검증 내용: completed/non-zero process의 terminal result가 processFailed이고 lifecycle에 completed event가 없는지 확인합니다.
    /// - 사전 조건: fake process가 thread.started와 turn.completed를 보낸 뒤 status 17로 종료합니다.
    /// - 기대 결과: lifecycle 소비는 processFailed로 종료되고 이벤트는 비어 있으며 result도 동일한 processFailed를 가집니다.
    func testObserve_completedNonzeroExit_doesNotDivergeLifecycleAndResult() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-deferred-completion"}"#.utf8),
                Data(#"{"type":"turn.completed","turn_id":"turn-deferred-completion"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 17,
        )
        let receipt = try await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: process).run,
        ).acquire(runID: "run-deferred-completion", command: makeCommand())
        let lifecycleStream = try await receipt.eventStream()

        let result = try await receipt.terminalResult()
        XCTAssertEqual(result.outcome, CodexExecLifecycleKind.failed)
        XCTAssertEqual(result.failure, .processFailed(17))

        var lifecycleEvents: [CodexExecLifecycleEvent] = []
        do {
            for try await event in lifecycleStream {
                lifecycleEvents.append(event)
            }
            XCTFail("non-zero completed process should fail lifecycle stream")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .processFailed(17))
        }
        XCTAssertTrue(lifecycleEvents.isEmpty, "completed lifecycle must wait for process status")
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
    }

    /// ATI-008-observe_external_agent_results: first failed terminal owns the run permanently.
    /// 첫 terminal 이후 후속 terminal이 raw/lifecycle projection과 cached result를 덮어쓰지 않는지 검증합니다.
    /// - 검증 내용: error 후 turn.completed 순서에서 단일 failed lifecycle/result, duplicate-terminal failure, 단일 cleanup을 확인합니다.
    /// - 사전 조건: actor-backed fake process가 thread.started, error, turn.completed를 순서대로 제공합니다.
    /// - 기대 결과: 첫 terminalError 결과가 보존되고 후속 terminal은 duplicateTerminal으로 거부됩니다.
    func testObserve_firstFailedTerminal_rejectsLaterCompletionWithoutOverwrite() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-duplicate-failure"}"#.utf8),
                Data(#"{"type":"error","turn_id":"turn-1","message":"Unauthorized: Bearer ati008-secret-sentinel"}"#
                    .utf8),
                Data(#"{"type":"turn.completed","turn_id":"turn-1"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let registry = CodexExecProcessRegistry()
        let controller = CodexExecProcessController(registry: registry)
        let receipt = try await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: process).run,
            registry: registry,
        ).acquire(
            runID: "run-duplicate-failure",
            command: CodexExecCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
                arguments: [],
                environment: [:],
                stdin: "prompt",
            ),
        )

        var lifecycle: [CodexExecLifecycleEvent] = []
        do {
            for try await event in try await receipt.eventStream() {
                lifecycle.append(event)
            }
            XCTFail("duplicate terminal should fail lifecycle stream")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .duplicateTerminal)
        }
        var rawTypes: [String] = []
        do {
            for try await event in receipt.events {
                rawTypes.append(event.type.rawValue)
            }
            XCTFail("duplicate terminal should fail raw stream")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .duplicateTerminal)
        }
        let result = try await receipt.terminalResult()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.failure, .terminalError)
        XCTAssertTrue(result.diagnostics.stderr.contains("Unauthorized"))
        XCTAssertFalse(result.diagnostics.stderr.contains("ati008-secret-sentinel"))
        XCTAssertNotNil(String(data: Data(result.diagnostics.stderr.utf8), encoding: .utf8))
        XCTAssertLessThanOrEqual(
            result.diagnostics.stderr.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )
        XCTAssertEqual(lifecycle.map(\.kind), [.failed])
        XCTAssertEqual(rawTypes, ["thread.started", "error"])
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: first completed terminal owns the run permanently.
    /// 첫 completed 결과가 후속 error로 실패 결과로 변이되지 않는지 검증합니다.
    /// - 검증 내용: turn.completed 후 error 순서에서 단일 completed lifecycle/result와 duplicate-terminal failure를 확인합니다.
    /// - 사전 조건: actor-backed fake process가 thread.started, turn.completed, error를 순서대로 제공합니다.
    /// - 기대 결과: 첫 completed 결과의 failure가 nil이고 후속 error는 duplicateTerminal으로 거부됩니다.
    func testObserve_firstCompletedTerminal_rejectsLaterFailureWithoutOverwrite() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-duplicate-completion"}"#.utf8),
                Data(#"{"type":"turn.completed","turn_id":"turn-1"}"#.utf8),
                Data(#"{"type":"error","turn_id":"turn-1","message":"late failure"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let cleanup = XCTestExpectation(description: "duplicate completion cleanup")
        process.onCleanup = { cleanup.fulfill() }
        let registry = CodexExecProcessRegistry()
        let controller = CodexExecProcessController(registry: registry)
        let receipt = try await CodexExecProcessController(
            runner: CodexExecFakeRunner(process: process).run,
            registry: registry,
        ).acquire(
            runID: "run-duplicate-completion",
            command: CodexExecCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
                arguments: [],
                environment: [:],
                stdin: "prompt",
            ),
        )

        var lifecycle: [CodexExecLifecycleEvent] = []
        do {
            for try await event in try await receipt.eventStream() {
                lifecycle.append(event)
            }
            XCTFail("duplicate terminal should fail lifecycle stream")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .duplicateTerminal)
        }
        var rawTypes: [String] = []
        do {
            for try await event in receipt.events {
                rawTypes.append(event.type.rawValue)
            }
            XCTFail("duplicate terminal should fail raw stream")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .duplicateTerminal)
        }
        let result = try await receipt.terminalResult()
        await fulfillment(of: [cleanup], timeout: 1)
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertNil(result.failure)
        XCTAssertEqual(lifecycle.map(\.kind), [.completed])
        XCTAssertEqual(rawTypes, ["thread.started", "turn.completed"])
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: repeated consumption fails with typed errors and no duplicate effects.
    /// event stream과 terminal result를 두 번 요청할 때 typed failure를 반환하고 process spawn을 늘리지 않는지 검증합니다.
    /// - 검증 내용: stream-first ordering, duplicate event/result claims, single runner invocation을 확인합니다.
    /// - 사전 조건: 정상 completed run과 deterministic fake process가 있습니다.
    /// - 기대 결과: 첫 소비만 성공하고 두 번째 소비는 각 전용 오류로 실패합니다.
    func testObserve_streamBeforeTerminal_rejectsDuplicateConsumption() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"turn.completed"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let receipt = try await CodexExecProcessController(runner: runner.run).acquire(
            runID: "run-2",
            command: command,
        )
        let stream = try await receipt.eventStream()
        for try await _ in stream {}
        do {
            _ = try await receipt.eventStream()
            XCTFail("duplicate event stream should fail")
        } catch let error as CodexExecConsumptionFailure {
            XCTAssertEqual(error, .eventStreamAlreadyConsumed)
        }
        let result = try await receipt.terminalResult()
        XCTAssertEqual(result.outcome, .completed)
        do {
            _ = try await receipt.terminalResult()
            XCTFail("duplicate terminal should fail")
        } catch let error as CodexExecConsumptionFailure {
            XCTAssertEqual(error, .terminalResultAlreadyConsumed)
        }
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-008-observe_external_agent_results: EOF without terminal does not synthesize completion.
    /// terminal event가 없는 EOF가 completed lifecycle event를 만들어내지 않는지 검증합니다.
    /// - 검증 내용: 관찰된 lifecycle event와 terminal failure를 확인합니다.
    /// - 사전 조건: handshake와 progress만 방출하는 fake process가 있습니다.
    /// - 기대 결과: completed event 없이 eofBeforeTerminal 오류가 반환됩니다.
    func testObserve_eofBeforeTerminal_doesNotSynthesizeCompletion() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"turn.started"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
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
        .acquire(runID: "run-eof", command: command)
        var events: [CodexExecLifecycleEvent] = []
        do {
            for try await event in try await receipt.eventStream() {
                events.append(event)
            }
            XCTFail("missing terminal should fail")
        } catch let error as CodexExecProcessFailure {
            XCTAssertEqual(error, .eofBeforeTerminal)
        }
        XCTAssertFalse(events.contains { $0.kind == .completed })
        do {
            _ = try await receipt.terminalResult()
            XCTFail("missing terminal should fail")
        } catch let error as CodexExecProcessFailure { XCTAssertEqual(error, .eofBeforeTerminal) }
    }

    /// ATI-008-observe_external_agent_results: cleanup runs once after both consumption sides finish.
    /// event stream과 terminal result가 모두 소비된 뒤 process cleanup이 한 번만 실행되는지 검증합니다.
    /// - 검증 내용: 양쪽 소비 완료와 cleanup 횟수를 확인합니다.
    /// - 사전 조건: 정상 completed run과 cleanup을 기록하는 fake process가 있습니다.
    /// - 기대 결과: cleanupCount가 정확히 1이고 runner는 한 번 호출됩니다.
    func testObserve_bothConsumersFinish_cleanupRunsExactlyOnce() async throws {
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"turn.completed"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let command = CodexExecCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/codex"),
            arguments: [],
            environment: [:],
            stdin: "prompt",
        )
        let receipt = try await CodexExecProcessController(runner: runner.run).acquire(
            runID: "run-clean",
            command: command,
        )
        for try await _ in try await receipt.eventStream() {}
        XCTAssertEqual(process.cleanupCount, 0)
        _ = try await receipt.terminalResult()
        XCTAssertEqual(process.cleanupCount, 1)
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-008-observe_external_agent_results: adapter terminal projection omits unverified artifacts.
    /// adapter 경계가 내부 final text를 공개 RuntimeResult에 노출하지 않고 outcome만 투영합니다.
    /// - 검증 내용: adapter launch와 terminalResult의 outcome, run reference, 빈 artifact 배열을 확인합니다.
    /// - 사전 조건: readiness를 통과하고 completed JSONL을 반환하는 fake process가 있습니다.
    /// - 기대 결과: completed 결과와 빈 artifact projection이 반환되고 provider spawn은 1회입니다.
    func testAdapterTerminalResult_projectsPublicOutcomeWithoutArtifacts() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-result", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(
            stdout: [
                Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                Data(#"{"type":"turn.completed"}"#.utf8),
            ],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let probe = CodexExecReadinessProbe { _, arguments, _ in
            arguments == ["--version"]
                ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        _ = try await adapter.launch(
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("result-run"),
                adapterID: .init("codex_exec"),
                contextPolicy: RuntimeContextPolicy(
                    branchReference: "branch",
                    authorizationGeneration: 0,
                    localCorrelation: "correlation",
                    workingDirectory: root.path,
                ),
                input: .init("prompt"),
            ),
        )
        let result = try await adapter.terminalResult(for: .init("result-run"))
        XCTAssertEqual(result.runReference.rawValue, "result-run")
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertTrue(result.artifactReferences.isEmpty)
        XCTAssertNil(result.failure)
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-008-observe_external_agent_results: resumed lifecycle events continue the persisted public cursor.
    /// resume adapter가 persisted cursor 이후의 public sequence와 idempotency key를 생성하는지 검증합니다.
    /// - 검증 내용: cursor 7 이후 sequence 8, 9와 run-scoped idempotency key 및 provider event ID를 확인합니다.
    /// - 사전 조건: cursor 7의 compatible binding과 handshake 후 두 lifecycle event를 방출하는 fake process가 있습니다.
    /// - 기대 결과: resumed event envelope가 8, 9이며 idempotency key가 codex.exec/run/8, /9입니다.
    func testAdapterResume_continuesProviderEventSequenceAndRegeneratesIdempotency() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-resume-sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        runner.initialLines = [#"{"type":"thread.started","thread_id":"resume-thread"}"#]
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("resume-run"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: .init("prompt"),
        )
        let binding = RuntimeRestartBinding(
            externalAgentSessionReference: request.externalAgentSessionReference,
            providerInternalSessionReference: .init("resume-thread"),
            runReference: request.runReference,
            adapterID: request.adapterID,
            providerNamespace: adapter.descriptor.providerNamespace,
            adapterVersion: adapter.descriptor.adapterVersion,
            providerBranch: adapter.descriptor.providerBranch,
            capabilitySnapshot: adapter.descriptor.capabilities,
            contextPolicy: request.contextPolicy,
            providerEventSequence: 7,
        )
        let compatibility = try await adapter.restartCompatibility(for: binding)
        XCTAssertEqual(compatibility, .compatible)
        _ = try await adapter.launch(request)
        let stream = try await adapter.eventStream(for: request.runReference)
        let consumer = Task { () throws -> [RuntimeEventEnvelope] in
            var events: [RuntimeEventEnvelope] = []
            for try await event in stream {
                events.append(event)
            }
            return events
        }
        runner.send(#"{"type":"turn.started","turn_id":"turn-8"}"#)
        runner.send(#"{"type":"turn.completed"}"#)
        runner.finishStreams()
        let events = try await consumer.value
        _ = try await adapter.terminalResult(for: request.runReference)
        XCTAssertEqual(events.map(\.sequence), [8, 9])
        XCTAssertTrue(events.allSatisfy { $0.idempotencyKey.rawValue.hasPrefix("codex.ik.") })
        XCTAssertEqual(Set(events.map(\.idempotencyKey)).count, 2)
        XCTAssertEqual(
            events.map(\.providerEventID).count,
            Set(events.map(\.providerEventID)).count,
        )
        XCTAssertTrue(events.allSatisfy { $0.providerEventID.rawValue.hasPrefix("codex.pe.") })
        let counts = await adapter.debugStorageCounts()
        XCTAssertEqual(counts.sequenceBases, 0)
    }

    /// ATI-008-observe_external_agent_results: mapped identifiers stay deterministic and bounded.
    /// provider handle과 run reference가 최대 길이여도 public identifier가 안전한 고정 형식인지 검증합니다.
    /// - 검증 내용: 여러 sequence의 결정성, sequence별 유일성, lowercase ASCII, 256 scalar 이하를 확인합니다.
    /// - 사전 조건: 4096 scalar provider handle과 256 scalar run reference를 가진 lifecycle event를 매핑합니다.
    /// - 기대 결과: ProviderEventID와 RuntimeIdempotencyKey가 반복 매핑에서 동일하고 bounded digest 형식입니다.
    func testAdapterMappedIdentifiers_maximumInputsAreDeterministicLowercaseASCIIAndBounded() {
        let providerHandle = String(repeating: "e\u{301}", count: 2048)
        let runReference = String(repeating: "r", count: 256)
        let host = ExternalAgentSessionReference(String(repeating: "h", count: 256))
        let sequences: [UInt64] = [1, 2, 3, 4]
        let events = sequences.map { sequence in
            CodexExecRuntimeAdapter.map(
                CodexExecLifecycleEvent(
                    providerEventID: providerHandle,
                    idempotencyKey: "ignored",
                    ordinal: sequence,
                    rawType: "turn.started",
                    kind: .progress,
                ),
                host: host,
                runReference: RuntimeRunReference(runReference),
                sequence: sequence,
            )
        }
        let repeated = sequences.map { sequence in
            CodexExecRuntimeAdapter.map(
                CodexExecLifecycleEvent(
                    providerEventID: providerHandle,
                    idempotencyKey: "ignored",
                    ordinal: sequence,
                    rawType: "turn.started",
                    kind: .progress,
                ),
                host: host,
                runReference: RuntimeRunReference(runReference),
                sequence: sequence,
            )
        }

        XCTAssertEqual(events.map(\.providerEventID), repeated.map(\.providerEventID))
        XCTAssertEqual(events.map(\.idempotencyKey), repeated.map(\.idempotencyKey))
        XCTAssertEqual(Set(events.map(\.providerEventID)).count, sequences.count)
        XCTAssertEqual(Set(events.map(\.idempotencyKey)).count, sequences.count)
        for identifier in events.flatMap({ [$0.providerEventID.rawValue, $0.idempotencyKey.rawValue] }) {
            XCTAssertLessThanOrEqual(identifier.unicodeScalars.count, 256)
            XCTAssertTrue(identifier.unicodeScalars.allSatisfy { $0.value < 128 })
            XCTAssertEqual(identifier, identifier.lowercased())
            let digest = identifier.split(separator: ".").dropFirst(2).joined()
            XCTAssertTrue(digest.allSatisfy(\.isHexDigit))
        }
    }

    /// ATI-008-observe_external_agent_results: resumed sequence overflow fails closed before emission.
    /// persisted cursor가 UInt64.max 직전일 때 max emission과 wrap을 방지하는지 검증합니다.
    /// - 검증 내용: max-2 cursor에서 max-1 한 건만 전달되고 다음 event가 event_sequence_overflow로 종료되는지 확인합니다.
    /// - 사전 조건: cursor UInt64.max-2의 compatible binding과 lifecycle event 두 건을 방출하는 fake process가 있습니다.
    /// - 기대 결과: UInt64.max-1만 노출되고 UInt64.max는 노출되지 않으며 adapter state가 정리됩니다.
    func testAdapterResume_sequenceOverflowFailsClosedBeforeMaxEmission() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-resume-overflow", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        runner.initialLines = [#"{"type":"thread.started","thread_id":"overflow-thread"}"#]
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("overflow-run"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: .init("prompt"),
        )
        let binding = RuntimeRestartBinding(
            externalAgentSessionReference: request.externalAgentSessionReference,
            providerInternalSessionReference: .init("overflow-thread"),
            runReference: request.runReference,
            adapterID: request.adapterID,
            providerNamespace: adapter.descriptor.providerNamespace,
            adapterVersion: adapter.descriptor.adapterVersion,
            providerBranch: adapter.descriptor.providerBranch,
            capabilitySnapshot: adapter.descriptor.capabilities,
            contextPolicy: request.contextPolicy,
            providerEventSequence: UInt64.max - 2,
        )
        let compatibility = try await adapter.restartCompatibility(for: binding)
        XCTAssertEqual(compatibility, .compatible)
        _ = try await adapter.launch(request)
        let stream = try await adapter.eventStream(for: request.runReference)
        let consumer = Task { () -> ([RuntimeEventEnvelope], RuntimeHostError?) in
            var events: [RuntimeEventEnvelope] = []
            do {
                for try await event in stream {
                    events.append(event)
                }
            } catch let error as RuntimeHostError {
                return (events, error)
            } catch {
                return (events, nil)
            }
            return (events, nil)
        }
        runner.send(#"{"type":"turn.started","turn_id":"turn-1"}"#)
        runner.send(#"{"type":"turn.started","turn_id":"turn-2"}"#)
        let (events, error) = await consumer.value
        XCTAssertEqual(error, .adapterFailure(.processExit, .init("event_sequence_overflow")))
        XCTAssertEqual(events.map(\.sequence), [UInt64.max - 1])
        XCTAssertFalse(events.contains { $0.sequence == UInt64.max })
        let counts = await adapter.debugStorageCounts()
        XCTAssertEqual(counts.receipts, 0)
        XCTAssertEqual(counts.hosts, 0)
        XCTAssertEqual(counts.sequenceBases, 0)
        XCTAssertEqual(counts.tombstones, 0)
    }

    /// ATI-008-observe_external_agent_results: adapter event consumer cancellation abandons owned state.
    /// public adapter stream의 downstream cancellation이 process와 adapter receipts를 함께 정리하는지 검증합니다.
    /// - 검증 내용: event consumer cancellation, 단일 terminate/cleanup, receipts/hosts/tombstones eviction을 확인합니다.
    /// - 사전 조건: readiness를 통과하고 handshake 후 열린 controlled process가 있습니다.
    /// - 기대 결과: cancellation 뒤 모든 adapter storage가 비고 process 정리가 한 번 수행됩니다.
    func testAdapterEventConsumerCancellation_evictsOwnedState() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-cancel", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let cleanup = XCTestExpectation(description: "adapter cleanup")
        process.onCleanup = { cleanup.fulfill() }
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("cancel-run"),
            adapterID: .init("codex_exec"),
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: .init("prompt"),
        )
        let launchTask = Task { try await adapter.launch(request) }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-1"}"#)
        _ = try await launchTask.value
        let stream = try await adapter.eventStream(for: .init("cancel-run"))
        let consumer = Task { for try await _ in stream {} }
        runner.send(#"{"type":"turn.started","turn_id":"turn-1"}"#)
        consumer.cancel()
        _ = try? await consumer.value
        await fulfillment(of: [cleanup], timeout: 1)
        let counts = await adapter.debugStorageCounts()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        XCTAssertEqual(counts.receipts, 0)
        XCTAssertEqual(counts.hosts, 0)
        XCTAssertEqual(counts.tombstones, 0)
    }

    /// ATI-008-observe_external_agent_results: lifecycle-only adapter runs do not retain raw events.
    /// public adapter가 raw consumer 없이도 513개 이상의 progress를 lifecycle로 처리하는지 검증합니다.
    /// - 검증 내용: public CodexExecRuntimeAdapter의 lifecycle stream 소비, completed result, 단일 spawn을 확인합니다.
    /// - 사전 조건: handshake 뒤 513개 progress와 terminal event를 즉시 반환하는 fake process가 있습니다.
    /// - 기대 결과: raw internal stream overflow 없이 lifecycle과 terminal result가 정상 완료됩니다.
    func testAdapterLifecycleOnlyRun_handlesMoreThanRawCapacityWithoutOverflow() async throws {
        XCTAssertGreaterThanOrEqual(CodexExecProcessController.maximumBufferedLifecycleEvents, 513)
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-lifecycle-only", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        runner.initialLines = [#"{"type":"thread.started","thread_id":"thread-lifecycle"}"#]
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("lifecycle-only-run"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: .init("prompt"),
        )
        _ = try await adapter.launch(request)
        let stream = try await adapter.eventStream(for: request.runReference)
        let firstEventDelivered = expectation(description: "first lifecycle event delivered")
        let deliveryMilestones = [64, 128, 192, 256, 320, 384, 448, 512, 513]
            .map { expectation(description: "lifecycle event \($0) delivered") }
        let consumer = Task { () throws -> [RuntimeEventEnvelope] in
            var events: [RuntimeEventEnvelope] = []
            for try await event in stream {
                events.append(event)
                if events.count == 1 {
                    firstEventDelivered.fulfill()
                }
                if events.count.isMultiple(of: 64) || events.count == 513 {
                    let milestone = events.count == 513 ? 8 : (events.count / 64) - 1
                    deliveryMilestones[milestone].fulfill()
                }
            }
            return events
        }
        runner.send(#"{"type":"turn.started","turn_id":"turn-0"}"#)
        await fulfillment(of: [firstEventDelivered], timeout: 1)
        for batch in 1 ... 8 {
            let start = (batch - 1) * 64 + 1
            let end = batch * 64
            for index in start ... end {
                runner.send("{\"type\":\"turn.started\",\"turn_id\":\"turn-\(index)\"}")
            }
            await fulfillment(of: [deliveryMilestones[batch - 1]], timeout: 1)
        }
        await fulfillment(of: [deliveryMilestones[8]], timeout: 1)
        runner.send(#"{"type":"turn.completed"}"#)
        runner.finishStreams()
        let result = try await adapter.terminalResult(for: request.runReference)
        XCTAssertEqual(result.outcome, .completed)
        let events = try await consumer.value
        XCTAssertEqual(events.count, 514)
        XCTAssertEqual(events.map(\.sequence), Array(1 ... 514).map(UInt64.init))
        XCTAssertTrue(events.allSatisfy { $0.providerEventID.rawValue.hasPrefix("codex.pe.") })
        XCTAssertTrue(events.allSatisfy { $0.idempotencyKey.rawValue.hasPrefix("codex.ik.") })
        XCTAssertEqual(Set(events.map(\.providerEventID)).count, events.count)
        XCTAssertEqual(Set(events.map(\.idempotencyKey)).count, events.count)
        XCTAssertEqual(events.map(\.kind), Array(repeating: .progress, count: 513) + [.completed])
        XCTAssertEqual(Set(events).count, events.count)
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-008-observe_external_agent_results: public adapter rejects pre-attach event count overflow.
    /// public eventStream을 요청하지 않은 상태에서도 lifecycle buffer limit이 producer에 적용되는지 검증합니다.
    /// - 검증 내용: handshake 후 129번째 progress의 exact public error, 단일 terminate/cleanup과 state eviction을 확인합니다.
    /// - 사전 조건: public adapter를 launch하고 eventStream을 claim하지 않은 controlled process가 129개 progress를 방출합니다.
    /// - 기대 결과: terminalResult가 event_buffer_overflow로 실패하고 모든 owned state가 정리됩니다.
    func testAdapterPreAttachEventCountOverflow_mapsToPublicErrorAndCleansOnce() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-pre-attach-count", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let cleanup = expectation(description: "pre-attach count cleanup")
        process.onCleanup = { cleanup.fulfill() }
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("pre-attach-count"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: .init("prompt"),
        )
        let launchTask = Task { try await adapter.launch(request) }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-pre-attach-count"}"#)
        _ = try await launchTask.value
        for index in 0 ..< 129 {
            runner.send("{\"type\":\"turn.started\",\"turn_id\":\"turn-\(index)\"}")
        }
        runner.finishStreams()

        do {
            _ = try await adapter.terminalResult(for: request.runReference)
            XCTFail("129th pre-attach event should overflow")
        } catch let error as RuntimeHostError {
            XCTAssertEqual(error, .adapterFailure(.processExit, .init("event_buffer_overflow")))
        }
        await fulfillment(of: [cleanup], timeout: 1)
        let adapterCounts = await adapter.debugStorageCounts()
        let controllerCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        XCTAssertEqual(adapterCounts.receipts, 0)
        XCTAssertEqual(adapterCounts.hosts, 0)
        XCTAssertEqual(adapterCounts.tombstones, 0)
        XCTAssertEqual(controllerCounts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: public adapter rejects pre-attach encoded byte overflow.
    /// public eventStream을 요청하지 않은 상태에서도 aggregate framed byte limit이 producer에 적용되는지 검증합니다.
    /// - 검증 내용: count 129 전 encoded bytes 초과의 exact public error와 단일 terminate/cleanup을 확인합니다.
    /// - 사전 조건: handshake 후 individually valid progress frames의 aggregate encoded bytes가 1 MiB를 초과합니다.
    /// - 기대 결과: terminalResult가 encoded_event_buffer_overflow로 실패하고 모든 owned state가 정리됩니다.
    func testAdapterPreAttachEncodedByteOverflow_mapsToPublicErrorAndCleansOnce() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-pre-attach-bytes", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let cleanup = expectation(description: "pre-attach byte cleanup")
        process.onCleanup = { cleanup.fulfill() }
        let runner = CodexExecControlledRunner(process: process)
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("pre-attach-bytes"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: .init("prompt"),
        )
        let launchTask = Task { try await adapter.launch(request) }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"thread-pre-attach-bytes"}"#)
        _ = try await launchTask.value
        let padding = String(repeating: "x", count: 9000)
        for index in 0 ..< 128 {
            runner.send(
                "{\"type\":\"turn.started\",\"turn_id\":\"turn-\(index)\",\"message\":\"\(padding)\"}",
            )
        }
        runner.finishStreams()

        do {
            _ = try await adapter.terminalResult(for: request.runReference)
            XCTFail("pre-attach encoded bytes should overflow")
        } catch let error as RuntimeHostError {
            XCTAssertEqual(error, .adapterFailure(.processExit, .init("encoded_event_buffer_overflow")))
        }
        await fulfillment(of: [cleanup], timeout: 1)
        let adapterCounts = await adapter.debugStorageCounts()
        let controllerCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        XCTAssertEqual(adapterCounts.receipts, 0)
        XCTAssertEqual(adapterCounts.hosts, 0)
        XCTAssertEqual(adapterCounts.tombstones, 0)
        XCTAssertEqual(controllerCounts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: public forwarding overflow cancels and evicts the receipt.
    /// adapter가 controller lifecycle buffer overflow를 process exit로 안정적으로 매핑하는지 검증합니다.
    /// - 검증 내용: public stream을 열기 전 controller capacity 초과 시 exact error와 단일 cleanup을 확인합니다.
    /// - 사전 조건: raw/lifecycle source capacity보다 많은 lifecycle event를 초기화 시점에 적재합니다.
    /// - 기대 결과: event_buffer_overflow, terminate 1, cleanup 1, 모든 adapter/controller state 0입니다.
    func testAdapterForwardingBufferOverflow_cancelsAndEvictsOnce() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-forward-overflow", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let cleanup = XCTestExpectation(description: "forwarding cleanup")
        process.onCleanup = { cleanup.fulfill() }
        let runner = CodexExecControlledRunner(process: process)
        runner.initialLines =
            [#"{"type":"thread.started","thread_id":"thread-overflow"}"#]
                + (0 ... CodexExecProcessController.maximumBufferedLifecycleEvents).map {
                    #"{"type":"turn.started","turn_id":"turn-"# + String($0) + #""}"#
                }
        let controller = CodexExecProcessController(runner: runner.run)
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        _ = try await adapter.launch(
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("overflow-run"),
                adapterID: .init("codex_exec"),
                contextPolicy: .init(
                    branchReference: "branch",
                    authorizationGeneration: 0,
                    localCorrelation: "correlation",
                    workingDirectory: root.path,
                ),
                input: .init("prompt"),
            ),
        )
        do {
            _ = try await adapter.terminalResult(for: .init("overflow-run"))
            XCTFail("controller overflow should fail")
        } catch {
            XCTAssertEqual(
                error as? RuntimeHostError,
                .adapterFailure(.processExit, .init("event_buffer_overflow")),
            )
        }
        await fulfillment(of: [cleanup], timeout: 1)
        let adapterCounts = await adapter.debugStorageCounts()
        let controllerCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        XCTAssertEqual(adapterCounts.receipts, 0)
        XCTAssertEqual(adapterCounts.hosts, 0)
        XCTAssertEqual(adapterCounts.tombstones, 0)
        XCTAssertEqual(controllerCounts.fresh, 0)
    }

    /// ATI-008-observe_external_agent_results: adapter terminal failure abandons all owned state.
    /// terminal consumer가 typed failure를 받으면 event/host receipt가 남지 않는지 검증합니다.
    /// - 검증 내용: eofBeforeTerminal의 public mapping과 adapter storage eviction을 확인합니다.
    /// - 사전 조건: handshake 뒤 terminal event 없이 EOF가 되는 fake process가 있습니다.
    /// - 기대 결과: invalid/transport failure가 반환되고 adapter state가 모두 제거됩니다.
    func testAdapterTerminalFailure_evictsOwnedState() async throws {
        let root = URL(fileURLWithPath: "/tmp/voyager-adapter-terminal-failure", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
            },
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        _ = try await adapter.launch(
            RuntimeLaunchRequest(
                externalAgentSessionReference: .init("host"),
                runReference: .init("failure-run"),
                adapterID: .init("codex_exec"),
                contextPolicy: .init(
                    branchReference: "branch",
                    authorizationGeneration: 0,
                    localCorrelation: "correlation",
                    workingDirectory: root.path,
                ),
                input: .init("prompt"),
            ),
        )
        do {
            _ = try await adapter.terminalResult(for: .init("failure-run"))
            XCTFail("missing terminal should fail")
        } catch {
            XCTAssertEqual(
                error as? RuntimeHostError,
                .adapterFailure(.processExit, .init("eof_before_terminal")),
            )
        }
        let counts = await adapter.debugStorageCounts()
        XCTAssertEqual(counts.receipts, 0)
        XCTAssertEqual(counts.hosts, 0)
        XCTAssertEqual(counts.tombstones, 0)
    }

    /// ATI-008-observe_external_agent_results: unknown adapter stream failures map to transport loss.
    /// 알려지지 않은 stream error가 process exit로 오분류되지 않는지 검증합니다.
    /// - 검증 내용: adapter의 unknown error mapping과 stable diagnostic code를 확인합니다.
    /// - 사전 조건: adapter mapping 경계에 synthetic unknown error를 전달합니다.
    /// - 기대 결과: transportLoss와 stream_failure가 반환됩니다.
    func testAdapterUnknownStreamFailure_mapsToTransportLoss() {
        XCTAssertEqual(
            CodexExecRuntimeAdapter.map(ATI008UnknownStreamFailure()),
            .adapterFailure(.transportLoss, .init("stream_failure")),
        )
    }
}

private struct ATI008UnknownStreamFailure: Error {}
