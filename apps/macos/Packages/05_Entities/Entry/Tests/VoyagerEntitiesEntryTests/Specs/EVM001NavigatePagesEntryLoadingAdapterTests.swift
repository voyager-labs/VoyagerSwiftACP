import ComposableArchitecture
import Dependencies
import Foundation
@testable import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

@MainActor
final class EVM001NavigatePagesEntryLoadingAdapterTests: XCTestCase {
    // MARK: - EVM-001-progressive_entry_materialization

    /// EVM-001-progressive_entry_materialization: URL materialization batches only valid visible first-occurrence
    /// entries.
    /// 디렉터리 결과가 무거운 메타데이터보다 먼저 32개 단위로 전달되는 경계를 검증한다.
    /// - 검증 내용: 0/1/32/33/64/65 경계, 연속 batch index, 정확히 한 번의 coreFinished, hidden/duplicate 필터링
    /// - 사전 조건: 파일 존재 여부는 true이고 숨김 및 중복 경로가 포함된 URL 입력을 사용한다.
    /// - 기대 결과: 유효한 표시 항목만 32개 단위 batch를 차지하고 마지막 coreFinished는 batch 수를 보유한다.
    func testURLMaterializationBatchesVisibleFirstOccurrenceEntries() async throws {
        for count in [0, 1, 32, 33, 64, 65] {
            let urls = (0 ..< count).map { URL(fileURLWithPath: "/fixture/Entry-\($0).txt") }
            let events = try await collect(
                EntryStagedMaterializerLive.materializeURLs(
                    urls,
                    showHidden: false,
                    priority: .none,
                    entryLoadingClient: visibleEntryClient(),
                    workspaceClient: .testValue,
                ),
            )

            let batches = events.coreBatches
            XCTAssertEqual(batches.map(\.items.count), expectedBatchSizes(for: count))
            XCTAssertEqual(batches.map(\.batchIndex), Array(batches.indices))
            XCTAssertEqual(events.coreFinishedCounts, [batches.count])
        }

        var filteringClient = visibleEntryClient()
        filteringClient.fileExistsAtPath = { path, isDirectory in
            guard path != "/fixture/missing.txt" else { return false }
            isDirectory?.pointee = false
            return true
        }
        let filteredEvents = try await collect(
            EntryStagedMaterializerLive.materializeURLs(
                [
                    URL(fileURLWithPath: "/fixture/visible.txt"),
                    URL(fileURLWithPath: "/fixture/missing.txt"),
                    URL(fileURLWithPath: "/fixture/.hidden.txt"),
                    URL(fileURLWithPath: "/fixture/visible.txt"),
                    URL(fileURLWithPath: "/fixture/second.txt"),
                ],
                showHidden: false,
                priority: .none,
                entryLoadingClient: filteringClient,
                workspaceClient: .testValue,
            ),
        )
        XCTAssertEqual(filteredEvents.coreBatches.flatMap(\.items).map(\.id), [
            "/fixture/visible.txt",
            "/fixture/second.txt",
        ])
    }

    /// EVM-001-progressive_entry_materialization: URL core conversion advances with consumer batch demand.
    /// 첫 core batch를 요청하기 전에 전체 URL을 변환하지 않는 producer cursor 경계를 검증한다.
    /// - 검증 내용: stream 생성 시 변환 0회, 첫 event 소비 시 batchSize만큼 변환
    /// - 사전 조건: 유효한 URL 65개와 file existence 호출 recorder를 사용한다.
    /// - 기대 결과: 첫 event는 32개 coreBatch이고 converter 호출 수도 32회다.
    func testURLMaterializationConvertsOnlyFirstBatchOnFirstDemand() async throws {
        let calls = LockedCounter()
        var client = visibleEntryClient()
        client.fileExistsAtPath = { _, isDirectory in
            calls.increment()
            isDirectory?.pointee = false
            return true
        }
        let stream = EntryStagedMaterializerLive.materializeURLs(
            (0 ..< 65).map { URL(fileURLWithPath: "/fixture/Entry-\($0).txt") },
            showHidden: false,
            priority: .none,
            entryLoadingClient: client,
            workspaceClient: .testValue,
        )

        XCTAssertEqual(calls.value, 0)

        var iterator = stream.makeAsyncIterator()
        guard case let .coreBatch(items, batchIndex) = try await iterator.next() else {
            return XCTFail("Expected first core batch")
        }
        XCTAssertEqual(items.count, EntryStagedMaterializerLive.batchSize)
        XCTAssertEqual(batchIndex, 0)
        XCTAssertEqual(calls.value, EntryStagedMaterializerLive.batchSize)

        let sparseCalls = LockedCounter()
        var sparseClient = visibleEntryClient()
        sparseClient.fileExistsAtPath = { _, isDirectory in
            sparseCalls.increment()
            isDirectory?.pointee = false
            return true
        }
        let duplicateURL = URL(fileURLWithPath: "/fixture/duplicate.txt")
        let sparseStream = EntryStagedMaterializerLive.materializeURLs(
            Array(repeating: duplicateURL, count: 65),
            showHidden: false,
            priority: .none,
            entryLoadingClient: sparseClient,
            workspaceClient: .testValue,
        )

        XCTAssertEqual(sparseCalls.value, 0)

        var sparseIterator = sparseStream.makeAsyncIterator()
        guard case let .coreBatch(sparseItems, sparseBatchIndex) = try await sparseIterator.next() else {
            return XCTFail("Expected sparse first core batch")
        }
        XCTAssertEqual(sparseItems.map(\.id), [duplicateURL.path])
        XCTAssertEqual(sparseBatchIndex, 0)
        XCTAssertEqual(sparseCalls.value, EntryStagedMaterializerLive.batchSize)
    }

    /// EVM-001-progressive_entry_materialization: Core events complete before deferred patches begin.
    /// 첫 표시 경로에서 폴더 수와 보조 메타데이터 탐침이 실행되지 않는 순서를 검증한다.
    /// - 검증 내용: coreFinished 이후 patch 순서와 initial folder-count 호출 부재
    /// - 사전 조건: 33개의 폴더 URL과 supplementary 우선순위를 사용한다.
    /// - 기대 결과: 32+1 core batch와 finish가 먼저 오고, 이후 nil/fallback supplementary patch가 전달된다.
    func testURLMaterializationDefersMetadataUntilAfterCoreFinished() async throws {
        let calls = LockedCounter()
        var client = visibleEntryClient()
        client.getFolderItemCount = { _ in
            calls.increment()
            return nil
        }

        let events = try await collect(
            EntryStagedMaterializerLive.materializeURLs(
                (0 ..< 33).map { URL(fileURLWithPath: "/fixture/Folder-\($0)") },
                showHidden: false,
                priority: .active([.supplementaryMetadata]),
                entryLoadingClient: client,
                workspaceClient: .testValue,
            ),
        )

        guard let finishedIndex = events.firstIndex(where: { $0.isCoreFinished }) else {
            return XCTFail("Expected coreFinished event")
        }
        XCTAssertTrue(events[..<finishedIndex].allSatisfy(\.isCoreEvent))
        XCTAssertTrue(events[(finishedIndex + 1)...].allSatisfy(\.isMetadataPatchEvent))
        XCTAssertEqual(calls.value, 33)
    }

    /// EVM-001-progressive_entry_materialization: Deferred probes start only after the consumer observes core
    /// completion.
    /// core finish를 관찰하기 전에는 폴더 수 probe가 실행되지 않는 stream 경계를 검증한다.
    /// - 검증 내용: probe 호출 timeline과 coreFinished 전달 순서
    /// - 사전 조건: supplementary metadata가 활성화된 폴더 URL 하나와 timeline recorder를 사용한다.
    /// - 기대 결과: coreFinished를 소비한 뒤에만 folder-count probe가 호출되고 nil 결과는 patch로 전달된다.
    func testDeferredProbeTimelineStartsAfterCoreFinishedIsObserved() async throws {
        let timeline = ProbeTimeline()
        var client = visibleEntryClient()
        client.getFolderItemCount = { _ in
            timeline.recordProbe()
            return nil
        }

        var patches: [EntryMetadataPatch] = []
        for try await event in EntryStagedMaterializerLive.materializeURLs(
            [URL(fileURLWithPath: "/fixture/Folder-0")],
            showHidden: false,
            priority: .active([.supplementaryMetadata]),
            entryLoadingClient: client,
            workspaceClient: .testValue,
        ) {
            if event.isCoreFinished {
                timeline.recordCoreFinished()
            }
            if case let .metadataPatches(eventPatches) = event {
                patches.append(contentsOf: eventPatches)
            }
        }

        XCTAssertFalse(timeline.didProbeBeforeCoreFinished)
        XCTAssertTrue(patches.contains(.supplementaryMetadata(id: "/fixture/Folder-0", metadata: nil)))
    }

    /// EVM-001-progressive_entry_materialization: Cancelling a client stream after core completion stops deferred work.
    /// consumer가 core 완료 뒤 staged stream을 종료하면 bridge producer와 메타데이터 탐침이 함께 종료되는지 검증한다.
    /// - 검증 내용: coreFinished까지의 event 순서와 취소 뒤 folder-count probe 미호출
    /// - 사전 조건: supplementary metadata가 활성화된 폴더 항목 하나를 반환하는 staged client stream을 소비한다.
    /// - 기대 결과: consumer가 coreFinished에서 종료한 뒤 deferred patch 및 folder-count probe가 발생하지 않는다.
    func testCancellingClientStreamAfterCoreFinishedStopsDeferredProbes() async throws {
        let calls = LockedCounter()
        let folderURL = URL(fileURLWithPath: "/fixture/Folder-0")
        var client = visibleEntryClient()
        client.contentsOfDirectory = { _, _, _ in [folderURL] }
        client.getFolderItemCount = { _ in
            calls.increment()
            return nil
        }
        let stagedClient = client
        client.stagedLoadItems = { _, showHidden, priority in
            EntryStagedMaterializerLive.materializeURLs(
                [folderURL],
                showHidden: showHidden,
                priority: priority,
                entryLoadingClient: stagedClient,
                workspaceClient: .testValue,
            )
        }

        let consumer = Task { () throws -> [EntryLoadEvent] in
            var events: [EntryLoadEvent] = []
            for try await event in client.loadItems(
                URL(fileURLWithPath: "/fixture"),
                false,
                .active([.supplementaryMetadata]),
            ) {
                events.append(event)
                if event.isCoreFinished {
                    break
                }
            }
            return events
        }

        let events = try await consumer.value
        await Task.yield()

        XCTAssertEqual(events.coreBatches.map(\.items.count), [1])
        XCTAssertEqual(events.coreFinishedCounts, [1])
        XCTAssertFalse(events.contains(where: \.isMetadataPatchEvent))
        XCTAssertEqual(calls.value, 0)
    }

    /// EVM-001-progressive_entry_materialization: Releasing a partially consumed stream closes instrumentation.
    /// 첫 core batch 뒤 stream 수명이 끝나면 추가 demand 없이 열린 request/core 계측을 닫는지 검증한다.
    /// - 검증 내용: coreFinished 전 stream 해제와 request interval 종료
    /// - 사전 조건: 두 batch가 필요한 33개 URL 중 첫 batch만 소비한다.
    /// - 기대 결과: stream 해제 후 request interval 종료 callback이 호출된다.
    func testReleasingStreamAfterFirstCoreBatchClosesInstrumentation() async throws {
        let requestClosed = expectation(description: "Request instrumentation closed")
        let instrumentation = EntryLoadingInstrumentation(
            onBegin: { _, _ in },
            onEnd: { interval, _, _ in
                if interval == .request {
                    requestClosed.fulfill()
                }
            },
        )

        for try await event in EntryStagedMaterializerLive.materializeURLs(
            (0 ..< 33).map { URL(fileURLWithPath: "/fixture/File-\($0)") },
            showHidden: false,
            configuration: .init(
                priority: .none,
                entryLoadingClient: visibleEntryClient(),
                workspaceClient: .testValue,
                sourceKind: .direct,
                instrumentation: instrumentation,
                favoriteTags: [],
            ),
        ) {
            if case .coreBatch = event {
                break
            }
        }

        await fulfillment(of: [requestClosed], timeout: 0.1)
    }

    /// EVM-001-progressive_entry_materialization: Cancelling while metadata probing is in progress stops remaining
    /// probes.
    /// 첫 deferred probe가 시작된 뒤 취소하면 후속 항목을 탐침하거나 부분 patch를 전달하지 않는지 검증한다.
    /// - 검증 내용: 첫 probe 시작 뒤 취소, 후속 probe 미호출, metadata patch 부재, 모든 계측 interval 종료
    /// - 사전 조건: supplementary metadata가 활성화된 폴더 세 개와 첫 probe를 대기시키는 gate를 사용한다.
    /// - 기대 결과: 첫 probe만 시작하고 취소 뒤 stream은 partial metadata patch 없이 종료된다.
    func testCancellingDuringMetadataProbeStopsRemainingProbesAndFinishesInstrumentation() async throws {
        let gate = ProbeGate()
        let calls = LockedCounter()
        let instrumentationRecorder = EntryLoadingInstrumentationRecorder()
        var client = visibleEntryClient()
        client.getFolderItemCount = { _ in
            calls.increment()
            gate.waitUntilOpened()
            return nil
        }

        let stream = EntryStagedMaterializerLive.materializeURLs(
            (0 ..< 3).map { URL(fileURLWithPath: "/fixture/Folder-\($0)") },
            showHidden: false,
            configuration: .init(
                priority: .active([.supplementaryMetadata]),
                entryLoadingClient: client,
                workspaceClient: .testValue,
                sourceKind: .direct,
                instrumentation: instrumentationRecorder.instrumentation,
                favoriteTags: [],
            ),
        )
        let consumer = Task.detached { () throws -> [EntryLoadEvent] in
            var events: [EntryLoadEvent] = []
            for try await event in stream {
                events.append(event)
            }
            return events
        }

        gate.waitForProbeStart()
        consumer.cancel()
        gate.open()
        let events = try await consumer.value

        XCTAssertEqual(calls.value, 1)
        XCTAssertFalse(events.contains(where: \.isMetadataPatchEvent))
        XCTAssertEqual(instrumentationRecorder.intervalNames, [
            "entry_loading_first_core_batch",
            "entry_loading_core_complete",
            "entry_loading_request",
            "entry_loading_metadata_complete",
        ])
    }

    /// EVM-001-progressive_entry_materialization: Active metadata priority is stable and deduplicated.
    /// 활성 sort/group probe가 먼저 오고 나머지 probe가 정해진 순서로 이어지는지 검증한다.
    /// - 검증 내용: active priority의 순서와 중복 제거
    /// - 사전 조건: tags, spotlight, tags 순서로 중복된 활성 probe를 제공한다.
    /// - 기대 결과: tags, spotlight, supplementaryMetadata 순서의 고유 probe 목록을 반환한다.
    func testActiveMetadataPriorityDeduplicatesAndAppendsRemainingProbes() {
        XCTAssertEqual(
            EntryMetadataPriority.active([.tags, .spotlight, .tags]).probes,
            [.tags, .spotlight, .supplementaryMetadata],
        )
    }

    /// EVM-001-progressive_entry_materialization: A nil probe result is observable while an inactive probe is absent.
    /// metadata nil fallback과 probe 미실행을 서로 다른 event 결과로 검증한다.
    /// - 검증 내용: supplementary nil patch와 none priority의 patch 부재
    /// - 사전 조건: folder-count client가 nil을 반환하는 폴더 URL을 사용한다.
    /// - 기대 결과: 활성 supplementary probe는 nil patch를 내보내고 비활성 priority는 metadata event를 내보내지 않는다.
    func testNilProbeResultIsDistinctFromNotQueried() async throws {
        var client = visibleEntryClient()
        client.getFolderItemCount = { _ in nil }
        let url = URL(fileURLWithPath: "/fixture/Folder-0")

        let queried = try await collect(EntryStagedMaterializerLive.materializeURLs(
            [url],
            showHidden: false,
            priority: .active([.supplementaryMetadata]),
            entryLoadingClient: client,
            workspaceClient: .testValue,
        ))
        let notQueried = try await collect(EntryStagedMaterializerLive.materializeURLs(
            [url], showHidden: false, priority: .none, entryLoadingClient: client, workspaceClient: .testValue,
        ))

        XCTAssertTrue(queried.metadataPatches.contains(.supplementaryMetadata(id: url.path, metadata: nil)))
        XCTAssertTrue(notQueried.metadataPatches.isEmpty)
    }

    /// EVM-001-progressive_entry_materialization: Payload entries preserve source values without filesystem probes.
    /// Recents와 Tags의 완성된 검색 payload가 재물질화되지 않는 경계를 검증한다.
    /// - 검증 내용: payload batch, hidden/dedupe 필터링, filesystem probe 미호출
    /// - 사전 조건: 중복 및 hidden payload와 실패하도록 구성한 filesystem closure를 사용한다.
    /// - 기대 결과: 첫 visible payload만 source order로 batch되고 metadata patch는 없다.
    func testPayloadMaterializationAvoidsFilesystemReprobes() async throws {
        var client = EntryLoadingClient.testValue
        client.fileExistsAtPath = { _, _ in XCTFail("Payload must not probe file existence")
            return false
        }
        client.getItemMetadata = { _, _, _ in XCTFail("Payload must not probe Spotlight")
            return .init(kind: "", creatorApplication: nil, lastUsedDate: nil)
        }
        client.getFolderItemCount = { _ in XCTFail("Payload must not probe folder count")
            return nil
        }

        let entries = [
            makeEntry(path: "/payload/one.txt"),
            makeEntry(path: "/payload/.hidden.txt", isHidden: true),
            makeEntry(path: "/payload/one.txt"),
            makeEntry(path: "/payload/two.txt"),
        ]
        client.loadRecentItems = { _, _ in entries }
        let events = try await collect(client.loadRecentItems(false, .none))

        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), ["/payload/one.txt", "/payload/two.txt"])
        XCTAssertEqual(events.coreFinishedCounts, [1])
        XCTAssertFalse(events.contains(where: \.isMetadataPatchEvent))
    }

    /// EVM-001-progressive_entry_materialization: Recents legacy fallback forwards the injected workspace client.
    /// staged loader가 없을 때 Recents payload loader가 DependencyValues의 workspace client를 받는 경계를 검증한다.
    /// - 검증 내용: injected workspace client closure 호출과 fallback payload의 core event 전달
    /// - 사전 조건: stagedLoadRecentItems 없이 workspace client를 사용하는 legacy loadRecentItems closure를 설정한다.
    /// - 기대 결과: injected workspace client가 한 번 호출되고 fallback entry는 coreBatch 뒤 coreFinished로 전달된다.
    func testRecentFallbackForwardsInjectedWorkspaceClient() async throws {
        let workspaceCalls = LockedCounter()
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.urlForApplication = { _ in
            workspaceCalls.increment()
            return nil
        }
        let fallbackEntry = makeEntry(path: "/payload/recent-fallback.txt")
        var client = EntryLoadingClient.testValue
        client.loadRecentItems = { _, workspaceClient in
            _ = workspaceClient.urlForApplication("com.voyager.test")
            return [fallbackEntry]
        }

        let events = try await withDependencies {
            $0.workspaceClient = workspaceClient
        } operation: {
            try await collect(client.loadRecentItems(false, .none))
        }

        XCTAssertEqual(workspaceCalls.value, 1)
        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), [fallbackEntry.id])
        XCTAssertEqual(events.coreFinishedCounts, [1])
    }

    /// EVM-001-progressive_entry_materialization: Directory loading falls back to the injected payload loader.
    /// staged loader가 없을 때 기존 두 인자 loadItems 계약의 완료된 payload를 progressive event로 변환하는 경계를 검증한다.
    /// - 검증 내용: injected loadItems 단일 호출과 coreBatch 뒤 coreFinished event 순서
    /// - 사전 조건: stagedLoadItems 없이 sentinel URL을 반환하는 contentsOfDirectory와 EntryModel 하나를 반환하는 loadItems를 사용한다.
    /// - 기대 결과: 주입 loader는 한 번 호출되고 반환 EntryModel은 coreBatch 다음 coreFinished로 전달된다.
    func testDirectoryLoadingFallsBackToInjectedPayloadLoader() async throws {
        let calls = LockedCounter()
        let fallbackEntry = makeEntry(path: "/payload/fallback.txt")
        var client = EntryLoadingClient.testValue
        client.contentsOfDirectory = { _, _, _ in
            XCTFail("Custom payload loader must not enumerate the directory")
            return [URL(fileURLWithPath: "/fixture/sentinel.txt")]
        }
        client.loadItems = { _, _ in
            calls.increment()
            return [fallbackEntry]
        }

        let events = try await collect(client.loadItems(
            URL(fileURLWithPath: "/fixture"),
            false,
            .none,
        ))

        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(events.count, 2)
        guard case let .coreBatch(items, batchIndex) = events[0] else {
            return XCTFail("Expected fallback payload core batch")
        }
        XCTAssertEqual(items.map(\.id), [fallbackEntry.id])
        XCTAssertEqual(batchIndex, 0)
        XCTAssertEqual(events.coreFinishedCounts, [1])
    }

    /// EVM-001-progressive_entry_materialization: Tags staged loader batches complete payloads without filesystem
    /// probes.
    /// tag 검색 payload가 configured client의 staged path를 통해 그대로 batch되는지 검증한다.
    /// - 검증 내용: loadFilesWithTag overload의 payload batching과 filesystem probe 부재
    /// - 사전 조건: filesystem probe가 실패하도록 설정하고 complete tag payload를 반환한다.
    /// - 기대 결과: source order의 core batch와 finish만 전달되며 filesystem closure는 호출되지 않는다.
    func testTagPayloadStagedLoaderAvoidsFilesystemReprobes() async throws {
        var client = EntryLoadingClient.testValue
        client.fileExistsAtPath = { _, _ in XCTFail("Tag payload must not probe file existence")
            return false
        }
        client.getItemMetadata = { _, _, _ in XCTFail("Tag payload must not probe Spotlight")
            return .init(kind: "", creatorApplication: nil, lastUsedDate: nil)
        }
        client.getFolderItemCount = { _ in XCTFail("Tag payload must not probe folder count")
            return nil
        }
        let taggedEntry = makeEntry(path: "/payload/tagged.txt")
        client.loadFilesWithTag = { _, _, _ in [taggedEntry] }

        let events = try await collect(client.loadFilesWithTag("Work", false, .none))

        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), ["/payload/tagged.txt"])
        XCTAssertEqual(events.coreFinishedCounts, [1])
        XCTAssertTrue(events.metadataPatches.isEmpty)
    }

    /// EVM-001-progressive_entry_materialization: Tags legacy fallback forwards the injected workspace client.
    /// staged loader가 없을 때 Tags payload loader가 DependencyValues의 workspace client를 받는 경계를 검증한다.
    /// - 검증 내용: injected workspace client closure 호출과 fallback payload의 core event 전달
    /// - 사전 조건: stagedLoadFilesWithTag 없이 workspace client를 사용하는 legacy loadFilesWithTag closure를 설정한다.
    /// - 기대 결과: injected workspace client가 한 번 호출되고 fallback entry는 coreBatch 뒤 coreFinished로 전달된다.
    func testTagFallbackForwardsInjectedWorkspaceClient() async throws {
        let workspaceCalls = LockedCounter()
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.urlForApplication = { _ in
            workspaceCalls.increment()
            return nil
        }
        let fallbackEntry = makeEntry(path: "/payload/tag-fallback.txt")
        var client = EntryLoadingClient.testValue
        client.loadFilesWithTag = { _, _, workspaceClient in
            _ = workspaceClient.urlForApplication("com.voyager.test")
            return [fallbackEntry]
        }

        let events = try await withDependencies {
            $0.workspaceClient = workspaceClient
        } operation: {
            try await collect(client.loadFilesWithTag("Work", false, .none))
        }

        XCTAssertEqual(workspaceCalls.value, 1)
        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), [fallbackEntry.id])
        XCTAssertEqual(events.coreFinishedCounts, [1])
    }

    /// EVM-001-progressive_entry_materialization: Metadata patches preserve every unrelated facet and equality observes
    /// displayed values.
    /// 지연 메타데이터가 기존 모델의 다른 표시 값을 손상시키지 않는지 검증한다.
    /// - 검증 내용: spotlight, tags, supplementary patch 적용과 EntryModel 전체 표시값 equality
    /// - 사전 조건: 모든 facet이 채워진 EntryModel을 사용한다.
    /// - 기대 결과: 각 patch는 해당 facet만 바꾸고 변경 전후 모델은 같지 않다.
    func testMetadataPatchApplicationPreservesUnchangedFacetsAndEquality() {
        let original = makeEntry(path: "/payload/one.txt")
        let patched = original
            .applying(
                .spotlight(
                    id: original.id,
                    kind: "Text",
                    creatorApplication: "TextEdit",
                    lastOpenedDate: Date(timeIntervalSince1970: 10),
                ),
            )
            .applying(
                .tags(id: original.id, tags: [Tag(name: "Work", colorCode: 4)]),
            )
            .applying(
                .supplementaryMetadata(id: original.id, metadata: .compressedFileSize(42)),
            )

        XCTAssertEqual(patched.name, original.name)
        XCTAssertEqual(patched.fullPath, original.fullPath)
        XCTAssertEqual(patched.facets.createdDate, original.facets.createdDate)
        XCTAssertEqual(patched.facets.addedDate, original.facets.addedDate)
        XCTAssertEqual(patched.facets.kind, "Text")
        XCTAssertEqual(patched.facets.creatorApplication, "TextEdit")
        XCTAssertEqual(patched.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertEqual(patched.facets.supplementaryMetadata, .compressedFileSize(42))
        XCTAssertNotEqual(original, patched)
    }

    /// EVM-001-progressive_entry_materialization: staged tag patch는 favorite tag 색상을 복원한다.
    /// Finder tag name fallback이 colorCode 0을 반환해도 progressive patch가 favorite 색상을 사용해야 한다.
    /// - 검증 내용: staged tag metadata patch의 favorite color fallback
    /// - 사전 조건: colorCode 없는 Work tag가 저장된 임시 파일과 colorCode 4 favorite tag를 사용한다.
    /// - 기대 결과: metadata patch의 Work tag colorCode가 4다.
    func testStagedTagPatchUsesFavoriteColorFallback() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("tagged.txt")
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)
        do {
            try TagMetadataClient.setTagNames(["Work"], for: fileURL)
        } catch {
            throw XCTSkip("이 환경에서는 확장 속성을 설정할 수 없습니다: \(error)")
        }

        let events = try await collect(EntryStagedMaterializerLive.materializeURLs(
            [fileURL],
            showHidden: false,
            configuration: .init(
                priority: .active([.tags]),
                entryLoadingClient: visibleEntryClient(),
                workspaceClient: .testValue,
                sourceKind: .direct,
                instrumentation: .init(onBegin: { _, _ in }, onEnd: { _, _, _ in }),
                favoriteTags: [Tag(name: "Work", colorCode: 4)],
            ),
        ))

        XCTAssertTrue(events.metadataPatches.contains(.tags(
            id: fileURL.path,
            tags: [Tag(name: "Work", colorCode: 4)],
        )))
    }

    /// EVM-001-progressive_entry_materialization: Core URL conversion stores package classification before metadata
    /// patches.
    /// 패키지 분류가 후속 metadata patch와 tag normalization 재구성 경로에서 손실되지 않는지 검증한다.
    /// - 검증 내용: directory URL의 injected package classifier 호출과 patch/normalization 적용 뒤 isPackage 보존
    /// - 사전 조건: 존재하는 directory URL과 true를 반환하는 package classifier를 사용한다.
    /// - 기대 결과: core, patched, normalized entry 모두 package로 남고 tag color가 favorite color로 보정된다.
    func testCoreURLConversionPreservesPackageClassificationThroughMetadataPatch() {
        let packageClassifierCalls = LockedCounter()
        var client = EntryLoadingClient.testValue
        client.fileExistsAtPath = { _, isDirectory in
            isDirectory?.pointee = true
            return true
        }
        client.isPackageDirectory = { _ in
            packageClassifierCalls.increment()
            return true
        }

        guard let entry = EntryModelConverterLive.convertURLToCoreEntry(
            URL(fileURLWithPath: "/fixture/Voyager.app"),
            entryLoadingClient: client,
        ) else {
            return XCTFail("Expected a core entry")
        }
        let patched = entry.applying(.tags(id: entry.id, tags: [Tag(name: "Work", colorCode: 0)]))
        let normalized = EntryModelTagColorNormalizer.normalize(
            patched,
            favoriteTags: [Tag(name: "Work", colorCode: 4)],
        )

        XCTAssertEqual(packageClassifierCalls.value, 1)
        XCTAssertTrue(entry.isFolder)
        XCTAssertTrue(entry.isPackage)
        XCTAssertTrue(patched.isPackage)
        XCTAssertEqual(patched.facets.tags, [Tag(name: "Work", colorCode: 0)])
        XCTAssertEqual(normalized.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertTrue(normalized.isPackage)
    }

    /// EVM-001-progressive_entry_materialization: Directory staged loading forwards the injected client through
    /// materialization.
    /// 디렉터리 열거와 core/metadata 구체화가 동일한 dependency override를 사용하는 경계를 검증한다.
    /// - 검증 내용: injected file existence, package classification, Spotlight metadata closure 호출
    /// - 사전 조건: 실제 파일시스템에는 없는 package URL을 반환하는 EntryLoadingClient override를 사용한다.
    /// - 기대 결과: 주입된 client로 core entry와 metadata patch가 생성되고 package 분류가 유지된다.
    func testDirectoryStagedLoaderForwardsInjectedClientToMaterializer() async throws {
        let directoryURL = URL(fileURLWithPath: "/fixture")
        let packageURL = directoryURL.appendingPathComponent("Injected.app", isDirectory: true)
        let fileExistenceCalls = LockedCounter()
        let packageClassifierCalls = LockedCounter()
        let metadataCalls = LockedCounter()
        var client = EntryLoadingClient.testValue
        client.contentsOfDirectory = { requestedURL, _, _ in
            XCTAssertEqual(requestedURL, directoryURL)
            return [packageURL]
        }
        client.fileExistsAtPath = { path, isDirectory in
            XCTAssertEqual(path, packageURL.path)
            fileExistenceCalls.increment()
            isDirectory?.pointee = true
            return true
        }
        client.isPackageDirectory = { url in
            XCTAssertEqual(url.path, packageURL.path)
            packageClassifierCalls.increment()
            return true
        }
        client.getItemMetadata = { url, isDirectory, _ in
            XCTAssertEqual(url.path, packageURL.path)
            XCTAssertTrue(isDirectory)
            metadataCalls.increment()
            return .init(kind: "Injected Package", creatorApplication: "Injected App", lastUsedDate: nil)
        }

        client.resolvedDirectoryLoadItems = EntryLoadingLive.resolvedDirectoryLoadItems
        let events = try await withDependencies {
            $0.workspaceClient = .testValue
        } operation: {
            try await collect(client.loadItems(directoryURL, false, .active([.spotlight])))
        }

        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), [packageURL.path])
        XCTAssertTrue(events.coreBatches.flatMap(\.items).allSatisfy(\.isPackage))
        XCTAssertTrue(events.metadataPatches.contains(.spotlight(
            id: packageURL.path,
            kind: "Injected Package",
            creatorApplication: "Injected App",
            lastOpenedDate: nil,
        )))
        XCTAssertEqual(fileExistenceCalls.value, 1)
        XCTAssertGreaterThanOrEqual(packageClassifierCalls.value, 1)
        XCTAssertEqual(metadataCalls.value, 1)
    }

    /// EVM-001-progressive_entry_materialization: A configured client owns resolved-directory probes.
    /// ambient dependency 값이 달라도 loadItems 호출 client의 enumeration과 metadata closure를 유지하는지 검증한다.
    /// - 검증 내용: direct client load와 ambient default client의 source/probe 분리
    /// - 사전 조건: custom client는 sentinel child를 반환하고 ambient client는 다른 결과를 반환한다.
    /// - 기대 결과: custom client의 lexical child와 metadata만 전달된다.
    func testResolvedDirectoryLoadingUsesConfiguredClientWithoutAmbientCoupling() async throws {
        let directoryURL = URL(fileURLWithPath: "/fixture")
        let childURL = directoryURL.appendingPathComponent("configured.txt")
        let metadataCalls = LockedCounter()
        var client = EntryLoadingClient.testValue
        client.resolveDirectoryURL = { _ in directoryURL }
        client.directoryURLBatches = { requestedURL, _, _ in
            XCTAssertEqual(requestedURL, directoryURL)
            return AsyncThrowingStream { continuation in
                continuation.yield([childURL])
                continuation.finish()
            }
        }
        client.fileExistsAtPath = { path, isDirectory in
            XCTAssertEqual(path, childURL.path)
            isDirectory?.pointee = false
            return true
        }
        client.getItemMetadata = { url, _, _ in
            XCTAssertEqual(url, childURL)
            metadataCalls.increment()
            return .init(kind: "Configured File", creatorApplication: nil, lastUsedDate: nil)
        }
        client.resolvedDirectoryLoadItems = EntryLoadingLive.resolvedDirectoryLoadItems

        let ambientChildURL = directoryURL.appendingPathComponent("ambient.txt")
        var ambientClient = EntryLoadingClient.testValue
        ambientClient.directoryURLBatches = { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield([ambientChildURL])
                continuation.finish()
            }
        }

        let events = try await withDependencies {
            $0.entryLoadingClient = ambientClient
            $0.workspaceClient = .testValue
        } operation: {
            try await collect(client.loadItems(directoryURL, false, .active([.spotlight])))
        }
        let childID = childURL.path
        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), [childID])
        XCTAssertTrue(events.metadataPatches.contains(.spotlight(
            id: childID,
            kind: "Configured File",
            creatorApplication: nil,
            lastOpenedDate: nil,
        )))
        XCTAssertEqual(metadataCalls.value, 1)
    }

    /// EVM-001-progressive_entry_materialization: The default staged loader resolves its live client without recursion.
    /// 기본 staged loader가 자기 live dependency를 캡처해도 재귀하지 않고 실제 directory payload를 완료하는지 검증한다.
    /// - 검증 내용: live EntryLoadingClient를 dependency와 호출 주체로 함께 사용한 core event 완료
    /// - 사전 조건: 임시 디렉터리에 표시 가능한 파일 하나가 존재하고 metadata probe는 비활성화한다.
    /// - 기대 결과: 파일 하나의 coreBatch 뒤 coreFinished가 전달되고 호출이 정상 종료된다.
    func testDefaultDirectoryStagedLoaderDoesNotRecurseThroughLiveDependency() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("visible.txt")
        try "visible".write(to: fileURL, atomically: true, encoding: .utf8)

        let events = try await withDependencies {
            $0.entryLoadingClient = .liveValue
        } operation: {
            try await collect(EntryLoadingClient.liveValue.loadItems(directoryURL, false, .none))
        }

        XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.name), [fileURL.lastPathComponent])
        XCTAssertEqual(events.coreFinishedCounts, [1])
    }

    /// EVM-001-progressive_entry_materialization: Directory enumeration starts on first stream demand.
    /// staged loader 호출은 동기 파일시스템 작업 없이 즉시 stream을 반환하는 경계를 검증한다.
    /// - 검증 내용: stream 생성 전후 열거 호출 수와 첫 iterator demand 뒤 호출 수
    /// - 사전 조건: 호출 횟수를 기록하고 빈 URL 목록을 반환하는 EntryLoadingClient override를 사용한다.
    /// - 기대 결과: stream 생성 시 열거하지 않고 첫 next에서 정확히 한 번 열거한다.
    func testDirectoryStagedLoaderDefersEnumerationUntilFirstDemand() async throws {
        let enumerationCalls = LockedCounter()
        var client = EntryLoadingClient.testValue
        client.contentsOfDirectory = { _, _, _ in
            enumerationCalls.increment()
            return []
        }
        client.resolvedDirectoryLoadItems = EntryLoadingLive.resolvedDirectoryLoadItems

        let stream = withDependencies {
            $0.workspaceClient = .testValue
        } operation: {
            client.loadItems(URL(fileURLWithPath: "/fixture"), false, .none)
        }

        XCTAssertEqual(enumerationCalls.value, 0)
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        XCTAssertEqual(enumerationCalls.value, 1)
    }

    /// EVM-001-progressive_entry_materialization: First core demand consumes only one directory URL batch.
    /// 대용량 directory source의 첫 core batch가 전체 열거 완료를 기다리지 않는 경계를 검증한다.
    /// - 검증 내용: 첫 stream event까지 요청된 URL source batch 수와 core item 수
    /// - 사전 조건: 32개와 1개 URL을 순서대로 반환하는 lazy directory batch override를 사용한다.
    /// - 기대 결과: 첫 event는 32개 core item이며 두 번째 source batch는 아직 요청되지 않는다.
    func testDirectoryStagedLoaderConsumesOneSourceBatchPerCoreDemand() async throws {
        let batchRequests = LockedCounter()
        let firstBatch = (0 ..< 32).map { URL(fileURLWithPath: "/fixture/File-\($0)") }
        let secondBatch = [URL(fileURLWithPath: "/fixture/File-32")]
        let batches = [firstBatch, secondBatch]
        var client = visibleEntryClient()
        client.contentsOfDirectory = { _, _, _ in
            XCTFail("Expected lazy directory batches")
            return []
        }
        client.directoryURLBatches = { _, _, requestedBatchSize in
            XCTAssertEqual(requestedBatchSize, 32)
            return AsyncThrowingStream(unfolding: {
                let index = batchRequests.value
                guard index < batches.count else { return nil }
                batchRequests.increment()
                return batches[index]
            })
        }
        client.resolvedDirectoryLoadItems = EntryLoadingLive.resolvedDirectoryLoadItems

        let stream = withDependencies {
            $0.workspaceClient = .testValue
        } operation: {
            client.loadItems(URL(fileURLWithPath: "/fixture"), false, .none)
        }
        var iterator = stream.makeAsyncIterator()
        let firstEvent = try await iterator.next()

        guard case let .coreBatch(items, batchIndex) = firstEvent else {
            return XCTFail("Expected first core batch")
        }
        XCTAssertEqual(items.count, 32)
        XCTAssertEqual(batchIndex, 0)
        XCTAssertEqual(batchRequests.value, 1)
    }

    // MARK: - EVM-001-directory_symlink_loading

    /// EVM-001-directory_symlink_loading: relative and absolute directory aliases enumerate target children under
    /// their lexical roots.
    /// 실제 임시 파일시스템의 두 symlink 표기가 같은 target을 읽되 사용자에게 보이는 child ID를 보존하는지 검증한다.
    /// - 검증 내용: directory root resolution, lexical child fullPath/ID, lexical metadata patch ID
    /// - 사전 조건: 임시 target 디렉터리와 relative/absolute directory symlink를 사용한다.
    /// - 기대 결과: 두 alias 모두 target child를 표시하고 core 및 metadata patch ID가 alias prefix를 사용한다.
    func testDirectorySymlinkLoadingPreservesRelativeAndAbsoluteLexicalChildIDs() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        let client = fixture.liveClient()
        for aliasURL in [fixture.relativeAliasURL, fixture.absoluteAliasURL] {
            let events = try await collectDirectory(aliasURL, client: client, priority: .active([.spotlight]))
            let childID = aliasURL.appendingPathComponent("child.txt").path

            XCTAssertEqual(events.coreBatches.flatMap(\.items).map(\.id), [childID])
            XCTAssertTrue(events.metadataPatches.contains(.spotlight(
                id: childID,
                kind: "Fixture File",
                creatorApplication: nil,
                lastOpenedDate: nil,
            )))
        }
    }

    /// EVM-001-directory_symlink_loading: non-batched enumeration remaps source children to lexical aliases.
    /// 배치 열거를 사용할 수 없는 fallback에서도 source URL과 visible lexical URL이 분리되는지 검증한다.
    /// - 검증 내용: contentsOfDirectory fallback과 lexical child materialization
    /// - 사전 조건: injected fallback enumeration은 resolved target child URL 하나를 반환한다.
    /// - 기대 결과: 반환된 target URL이 아니라 요청 alias 아래의 child ID가 core event에 기록된다.
    func testDirectorySymlinkFallbackPreservesLexicalChildIDs() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        var client = fixture.liveClient()
        client.directoryURLBatches = nil
        client.contentsOfDirectory = { requestedURL, _, _ in
            XCTAssertEqual(requestedURL, fixture.targetURL)
            return [fixture.targetChildURL]
        }

        let events = try await collectDirectory(fixture.relativeAliasURL, client: client, priority: .none)
        XCTAssertEqual(
            events.coreBatches.flatMap(\.items).map(\.id),
            [fixture.relativeAliasURL.appendingPathComponent("child.txt").path],
        )
    }

    /// EVM-001-directory_symlink_loading: root resolution is demand-lazy and cached for one load.
    /// stream 생성은 resolver/enumerator를 건드리지 않고 첫 demand에서 root snapshot을 한 번만 만든다.
    /// - 검증 내용: resolver 호출 시점과 exact-once dispatch
    /// - 사전 조건: resolver와 resolved-directory closure 호출 recorder를 주입한다.
    /// - 기대 결과: 생성 시 호출 0회, 첫 demand 후 resolver/dispatch 각 1회다.
    func testDirectoryRootResolutionIsDemandLazyAndCached() async throws {
        let resolverCalls = LockedCounter()
        let dispatchCalls = LockedCounter()
        var client = EntryLoadingClient.testValue
        client.resolveDirectoryURL = { url in
            resolverCalls.increment()
            return url
        }
        client.resolvedDirectoryLoadItems = { _, _, _, _ in
            dispatchCalls.increment()
            return EntryStagedMaterializerLive.materializeURLs(
                [],
                showHidden: false,
                priority: .none,
                entryLoadingClient: .testValue,
                workspaceClient: .testValue,
            )
        }

        let stream = client.loadItems(URL(fileURLWithPath: "/fixture"), false, .none)
        XCTAssertEqual(resolverCalls.value, 0)
        XCTAssertEqual(dispatchCalls.value, 0)

        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        XCTAssertEqual(resolverCalls.value, 1)
        XCTAssertEqual(dispatchCalls.value, 1)

        _ = try await iterator.next()
        XCTAssertEqual(resolverCalls.value, 1)
        XCTAssertEqual(dispatchCalls.value, 1)
    }

    /// EVM-001-directory_symlink_loading: resolved ancestor equality fails before directory dispatch.
    /// 성공적으로 해석된 root가 ancestor와 같으면 열거 closure를 호출하지 않는 preflight 경계를 검증한다.
    /// - 검증 내용: root/ancestor resolver 호출 횟수와 resolved loader 미호출
    /// - 사전 조건: root와 ancestor가 같은 resolved URL을 반환하는 client를 주입한다.
    /// - 기대 결과: 첫 demand에서 cycle error가 발생하고 각 resolver는 한 번, dispatch는 0회다.
    func testDirectoryRootResolutionRejectsResolvedAncestorBeforeDispatch() async throws {
        let resolverCalls = LockedCounter()
        let dispatchCalls = LockedCounter()
        let resolvedURL = URL(fileURLWithPath: "/fixture/target")
        var client = EntryLoadingClient.testValue
        client.resolveDirectoryURL = { _ in
            resolverCalls.increment()
            return resolvedURL
        }
        client.resolvedDirectoryLoadItems = { _, _, _, _ in
            dispatchCalls.increment()
            return EntryStagedMaterializerLive.materializeURLs(
                [],
                showHidden: false,
                priority: .none,
                entryLoadingClient: .testValue,
                workspaceClient: .testValue,
            )
        }

        let stream = client.loadItems(
            URL(fileURLWithPath: "/fixture/alias"),
            false,
            .none,
            [URL(fileURLWithPath: "/fixture/ancestor")],
        )
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected resolved ancestor cycle")
        } catch is EntryDirectorySymlinkTraversalError {
            XCTAssertEqual(resolverCalls.value, 2)
            XCTAssertEqual(dispatchCalls.value, 0)
        }
    }

    /// EVM-001-directory_symlink_loading: sibling aliases keep independent lexical child identity sets.
    /// 같은 target을 가리키는 두 sibling alias가 materializer dedupe에서 서로 충돌하지 않는지 검증한다.
    /// - 검증 내용: lexical-ID dedupe와 alias independence
    /// - 사전 조건: alias-a와 alias-b가 하나의 target child를 각각 열거한다.
    /// - 기대 결과: 두 load의 child IDs가 서로 다르고 각 alias prefix를 유지한다.
    func testSiblingDirectoryAliasesKeepIndependentLexicalChildIDs() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        var client = fixture.liveClient()
        client.directoryURLBatches = nil
        client.contentsOfDirectory = { _, _, _ in [fixture.targetChildURL] }

        let aliasAEvents = try await collectDirectory(fixture.aliasAURL, client: client, priority: .none)
        let aliasBEvents = try await collectDirectory(fixture.aliasBURL, client: client, priority: .none)
        let aliasAID = fixture.aliasAURL.appendingPathComponent("child.txt").path
        let aliasBID = fixture.aliasBURL.appendingPathComponent("child.txt").path

        XCTAssertEqual(aliasAEvents.coreBatches.flatMap(\.items).map(\.id), [aliasAID])
        XCTAssertEqual(aliasBEvents.coreBatches.flatMap(\.items).map(\.id), [aliasBID])
        XCTAssertNotEqual(aliasAID, aliasBID)
    }

    /// EVM-001-directory_symlink_loading: ordinary directories retain their existing lexical child IDs.
    /// symlink 전용 경로 변경이 일반 디렉터리의 기존 materialization 결과를 바꾸지 않는지 검증한다.
    /// - 검증 내용: ordinary directory enumeration and lexical identity parity
    /// - 사전 조건: 실제 ordinary directory와 child.txt를 사용한다.
    /// - 기대 결과: ordinary/child.txt가 기존 경로 그대로 core event에 기록된다.
    func testOrdinaryDirectoryPreservesExistingLexicalChildIDs() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        let events = try await collectDirectory(fixture.ordinaryURL, client: fixture.liveClient(), priority: .none)
        XCTAssertEqual(
            events.coreBatches.flatMap(\.items).map(\.id),
            [fixture.ordinaryURL.appendingPathComponent("child.txt").path],
        )
    }

    /// EVM-001-directory_symlink_loading: broken directory aliases terminate with the existing source error.
    /// broken symlink가 성공적인 빈 directory load로 바뀌지 않고 기존 throwing boundary를 유지하는지 검증한다.
    /// - 검증 내용: broken-link stream error completion
    /// - 사전 조건: 존재하지 않는 target을 가리키는 directory symlink를 사용한다.
    /// - 기대 결과: load가 성공적인 coreFinished가 아니라 오류로 종료된다.
    func testBrokenDirectorySymlinkTerminatesWithSourceError() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        do {
            _ = try await collectDirectory(fixture.brokenAliasURL, client: fixture.liveClient(), priority: .none)
            XCTFail("Expected broken directory symlink to terminate with an error")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    /// EVM-001-directory_symlink_loading: self and A↔B loop roots terminate within a bounded load.
    /// Foundation이 loop root를 resolve하지 못하는 경우에도 batch enumerator가 hang하지 않는지 검증한다.
    /// - 검증 내용: self-loop/A↔B-loop bounded termination for the batched path
    /// - 사전 조건: 실제 self-loop와 두 방향 loop symlink root를 사용한다.
    /// - 기대 결과: 각 load가 제한 시간 내 오류 또는 종료를 반환하고 child row를 만들지 않는다.
    func testDirectorySymlinkLoopsTerminateForBatchedEnumeration() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        for loopURL in [fixture.selfLoopURL, fixture.loopAURL, fixture.loopBURL] {
            do {
                let events = try await collectDirectoryWithTimeout(
                    loopURL,
                    client: fixture.liveClient(),
                    priority: .none,
                )
                XCTAssertTrue(events.coreBatches.isEmpty)
            } catch is DirectoryLoadTimeoutError {
                XCTFail("Loop enumeration exceeded the bounded timeout: \(loopURL.path)")
            } catch {
                XCTAssertFalse(error is CancellationError)
            }
        }
    }

    /// EVM-001-directory_symlink_loading: self and A↔B loop roots terminate in the non-batched fallback.
    /// fallback contentsOfDirectory 경계도 filesystem loop에서 bounded error completion을 유지하는지 검증한다.
    /// - 검증 내용: self-loop/A↔B-loop bounded termination for contentsOfDirectory
    /// - 사전 조건: directoryURLBatches를 끄고 실제 loop root를 contentsOfDirectory에 전달한다.
    /// - 기대 결과: 각 fallback load가 제한 시간 내 오류 또는 빈 종료를 반환한다.
    func testDirectorySymlinkLoopsTerminateForContentsFallback() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        var client = fixture.liveClient()
        client.directoryURLBatches = nil
        client.contentsOfDirectory = { url, keys, options in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: options,
            )
        }

        for loopURL in [fixture.selfLoopURL, fixture.loopAURL, fixture.loopBURL] {
            do {
                let events = try await collectDirectoryWithTimeout(loopURL, client: client, priority: .none)
                XCTAssertTrue(events.coreBatches.isEmpty)
            } catch is DirectoryLoadTimeoutError {
                XCTFail("Loop fallback exceeded the bounded timeout: \(loopURL.path)")
            } catch {
                XCTAssertFalse(error is CancellationError)
            }
        }
    }

    /// EVM-001-directory_symlink_loading: root resolution snapshots the source before a lexical alias retarget.
    /// root resolution 뒤 alias를 다른 target으로 바꿔도 core와 deferred metadata가 같은 source snapshot을 쓰는지 검증한다.
    /// - 검증 내용: captured source URL probe, lexical core ID, lexical metadata patch ID
    /// - 사전 조건: target-a child를 source로 열거한 뒤 alias를 target-b로 retarget한다.
    /// - 기대 결과: metadata probe는 target-a를 읽고 core/patch ID는 alias child ID로 유지된다.
    func testDirectorySymlinkRetargetKeepsCapturedSourceAndLexicalIDs() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        let probePaths = LockedPaths()
        let enumerationPaths = LockedPaths()
        let resolverGate = ResolverInterleavingGate()
        var client = fixture.liveClient()
        client.resolveDirectoryURL = { lexicalURL in
            let resolvedURL = lexicalURL.standardizedFileURL.resolvingSymlinksInPath()
            resolverGate.markResolverReturned()
            return resolvedURL
        }
        client.directoryURLBatches = { requestedURL, _, _ in
            DirectorySymlinkBatchSource.stream {
                enumerationPaths.append(requestedURL.path)
                return try FileManager.default.contentsOfDirectory(
                    at: requestedURL,
                    includingPropertiesForKeys: [],
                    options: [],
                )
            }
        }
        let resolvedDirectoryLoadItems = try XCTUnwrap(client.resolvedDirectoryLoadItems)
        client.resolvedDirectoryLoadItems = { lexicalURL, resolvedURL, showHidden, priority in
            resolverGate.waitForResolverReturn()
            resolverGate.retarget(using: fixture)
            return resolvedDirectoryLoadItems(lexicalURL, resolvedURL, showHidden, priority)
        }
        client.getItemMetadata = { url, _, _ in
            probePaths.append(url.path)
            return .init(
                kind: url.standardizedFileURL.path == fixture.targetChildURL.standardizedFileURL
                    .path ? "Target A" : "Target B",
                creatorApplication: nil,
                lastUsedDate: nil,
            )
        }

        let stream = makeDirectoryStream(fixture.relativeAliasURL, client: client, priority: .active([.spotlight]))
        var iterator = stream.makeAsyncIterator()
        guard case let .coreBatch(items, _) = try await iterator.next() else {
            return XCTFail("Expected captured source core batch")
        }

        guard case .coreFinished = try await iterator.next() else {
            return XCTFail("Expected core completion before metadata")
        }
        guard case let .metadataPatches(patches) = try await iterator.next() else {
            return XCTFail("Expected deferred metadata patch")
        }

        let lexicalID = fixture.relativeAliasURL.appendingPathComponent("child.txt").path
        XCTAssertEqual(items.map(\.id), [lexicalID])
        XCTAssertTrue(patches.contains(.spotlight(
            id: lexicalID,
            kind: "Target A",
            creatorApplication: nil,
            lastOpenedDate: nil,
        )))
        XCTAssertEqual(enumerationPaths.values.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, [
            fixture.targetURL.resolvingSymlinksInPath().path,
        ])
        XCTAssertEqual(probePaths.values.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, [
            fixture.targetChildURL.resolvingSymlinksInPath().path,
        ])
        XCTAssertNil(resolverGate.error)
    }

    /// EVM-001-directory_symlink_loading: dropping a mapped stream terminates its upstream producer once.
    /// 부분 소비 후 mapped stream을 버리면 upstream batch producer가 중복 종료되지 않는지 검증한다.
    /// - 검증 내용: upstream AsyncThrowingStream termination propagation and exact-once cleanup
    /// - 사전 조건: 첫 batch를 내보낸 뒤 열린 상태로 남는 upstream stream을 사용한다.
    /// - 기대 결과: mapped stream drop 뒤 upstream termination callback이 정확히 한 번 호출된다.
    func testMappedDirectoryStreamDropTerminatesUpstreamExactlyOnce() async throws {
        let fixture = try DirectorySymlinkFixture.make()
        defer { fixture.remove() }

        let termination = expectation(description: "Upstream directory stream terminated")
        let terminationCount = LockedCounter()
        var client = fixture.liveClient()
        client.directoryURLBatches = { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield([fixture.targetChildURL])
                continuation.onTermination = { _ in
                    terminationCount.increment()
                    termination.fulfill()
                }
            }
        }

        do {
            let stream = makeDirectoryStream(fixture.targetURL, client: client, priority: .none)
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
        }

        await fulfillment(of: [termination], timeout: 1)
        XCTAssertEqual(terminationCount.value, 1)
    }

    // MARK: - EVM-001-entry_loading_performance

    /// EVM-001-entry_loading_performance: Core-only consumption closes its active instrumentation intervals.
    /// core 완료 직후 소비를 중단해도 metadata 계측을 열지 않고 request 계측을 닫는지 검증한다.
    /// - 검증 내용: core 완료 시 request 종료, metadata probe 미실행, metadata interval 미시작
    /// - 사전 조건: Spotlight metadata가 활성화된 단일 URL stream을 coreFinished까지만 소비한다.
    /// - 기대 결과: first/core/request interval만 종료되고 metadata closure는 호출되지 않는다.
    func testBreakingAfterCoreFinishedClosesRequestWithoutStartingMetadata() async throws {
        let recorder = EntryLoadingInstrumentationRecorder()
        let metadataCalls = LockedCounter()
        var client = visibleEntryClient()
        client.getItemMetadata = { _, _, _ in
            metadataCalls.increment()
            return .init(kind: "File", creatorApplication: nil, lastUsedDate: nil)
        }

        for try await event in EntryStagedMaterializerLive.materializeURLs(
            [URL(fileURLWithPath: "/fixture/File-0")],
            showHidden: false,
            configuration: .init(
                priority: .active([.spotlight]),
                entryLoadingClient: client,
                workspaceClient: .testValue,
                sourceKind: .direct,
                instrumentation: recorder.instrumentation,
                favoriteTags: [],
            ),
        ) where event.isCoreFinished {
            break
        }

        XCTAssertEqual(metadataCalls.value, 0)
        XCTAssertEqual(recorder.intervalNames, [
            "entry_loading_first_core_batch",
            "entry_loading_core_complete",
            "entry_loading_request",
        ])
    }

    /// EVM-001-entry_loading_performance: Staged URL loading closes each interval once in stream order.
    /// 빈 입력과 deferred probe 실패가 있어도 계측 interval과 work count가 결정론적으로 닫히는지 검증한다.
    /// - 검증 내용: request/first/core/metadata interval 순서, empty 완료, probe 실패 후 종료, folder-count work 수
    /// - 사전 조건: 빈 URL 입력과 supplementary probe가 nil을 반환하는 폴더 URL을 각각 사용한다.
    /// - 기대 결과: request는 core 완료와 함께 닫히고 metadata interval은 실제 probe가 있을 때만 뒤이어 닫힌다.
    func testStagedLoadingInstrumentationClosesIntervalsForEmptyAndProbeFailure() async throws {
        let emptyRecorder = EntryLoadingInstrumentationRecorder()
        _ = try await collect(EntryStagedMaterializerLive.materializeURLs(
            [],
            showHidden: false,
            configuration: .init(
                priority: .none,
                entryLoadingClient: visibleEntryClient(),
                workspaceClient: .testValue,
                sourceKind: .direct,
                instrumentation: emptyRecorder.instrumentation,
                favoriteTags: [],
            ),
        ))

        XCTAssertEqual(emptyRecorder.intervalNames, [
            "entry_loading_first_core_batch",
            "entry_loading_core_complete",
            "entry_loading_request",
        ])
        XCTAssertEqual(emptyRecorder.workCounts.folderCountProbes, 0)

        let probeRecorder = EntryLoadingInstrumentationRecorder()
        let calls = LockedCounter()
        var client = visibleEntryClient()
        client.getFolderItemCount = { _ in
            calls.increment()
            return nil
        }
        _ = try await collect(EntryStagedMaterializerLive.materializeURLs(
            [URL(fileURLWithPath: "/fixture/Folder-0")],
            showHidden: false,
            configuration: .init(
                priority: .active([.supplementaryMetadata]),
                entryLoadingClient: client,
                workspaceClient: .testValue,
                sourceKind: .direct,
                instrumentation: probeRecorder.instrumentation,
                favoriteTags: [],
            ),
        ))

        XCTAssertEqual(probeRecorder.intervalNames, [
            "entry_loading_first_core_batch",
            "entry_loading_core_complete",
            "entry_loading_request",
            "entry_loading_metadata_complete",
        ])
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(probeRecorder.workCounts.folderCountProbes, 1)
    }

    /// EVM-001-entry_loading_performance: The 1,000-entry benchmark is opt-in and reports serial samples.
    /// 일반 CI에서는 측정을 건너뛰고, 명시적 환경 변수에서만 fixture 생성 외의 stream 소비 시간을 측정한다.
    /// - 검증 내용: 환경 게이트, 20개 serial sample, JSON percentile 및 work-count 출력
    /// - 사전 조건: VOYAGER_ENTRY_LOADING_BENCHMARK 환경 변수를 명시적으로 설정하거나 설정하지 않는다.
    /// - 기대 결과: 기본 실행은 skip되고, gated 실행은 20개 유효 sample의 machine-readable report를 출력한다.
    func testEnvironmentGatedThousandEntryBenchmark() async throws {
        try await EntryLoadingBenchmark.runIfEnabled()
    }

    // MARK: - EVM-001-reload_directory_page_on_external_change

    /// EVM-001-reload_directory_page_on_external_change: Recents route loader maps helper payloads into entry models.
    /// Recents/Tags/Computer route refresh keeps route identity while refreshing the route-specific loader output.
    /// - 검증 내용: Recent search helper payload request options and EntryModel facet mapping
    /// - 사전 조건: Recents loader receives a helper response with tag, last-opened, creator, and supplementary metadata
    /// - 기대 결과: Helper payload fields are preserved on the resulting EntryModel used by the refreshed route
    func testRecentAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await EntryLoadingLive.loadRecentItemsViaSearch(
            showHidden: false,
            search: { request in
                XCTAssertEqual(request.scopeMode, .allIndexed)
                XCTAssertEqual(request.resultCap, 100)
                XCTAssertFalse(request.includeHidden)
                return VoyagerShared.RecentSearchResponsePayload(
                    items: [
                        VoyagerShared.SearchEntryPayload(
                            name: "Recent.txt",
                            fullPath: "/tmp/Recent.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 12,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: date,
                            kind: "Text",
                            creatorApplication: "TextEdit",
                            tags: [VoyagerShared.SearchTagPayload(name: "Work", colorCode: 4)],
                            supplementaryMetadata: .compressedFileSize(12),
                        ),
                    ],
                )
            },
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Recent.txt"])
        XCTAssertEqual(items.first?.facets.lastOpenedDate, date)
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertEqual(items.first?.facets.creatorApplication, "TextEdit")
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route loader falls back to an empty result on helper
    /// failure.
    /// Recents/Tags route refresh must not crash or mutate route identity when the route-specific helper fails.
    /// - 검증 내용: Tags helper failure fallback behavior
    /// - 사전 조건: Tags route loader receives a failing helper search dependency
    /// - 기대 결과: Loader returns an empty entry list for the failed refresh
    func testTagAdapterReturnsEmptyArrayOnHelperFailure() async {
        struct StubError: Error {}

        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Work",
            showHidden: false,
            search: { _ in throw StubError() },
        )

        XCTAssertEqual(items, [])
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route loader maps helper payloads into entry models.
    /// Tags route refresh keeps the route-specific requested tag and entry tag color data intact.
    /// - 검증 내용: Tags helper request contract and SearchEntryPayload to EntryModel tag facet mapping
    /// - 사전 조건: Tags route loader refreshes the Green tag route from a helper response
    /// - 기대 결과: Requested tag and color-coded entry tag facets are preserved in the loaded entries
    func testTagAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Green",
            showHidden: false,
            search: { request in
                XCTAssertEqual(request.requestedTag, "Green")
                XCTAssertTrue(request.exactTagVerification)
                return VoyagerShared.TagSearchResponsePayload(
                    requestedTag: request.requestedTag,
                    items: [
                        VoyagerShared.SearchEntryPayload(
                            name: "Tagged.txt",
                            fullPath: "/tmp/Tagged.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 12,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: date,
                            kind: "Text",
                            creatorApplication: "TextEdit",
                            tags: [VoyagerShared.SearchTagPayload(name: "Green", colorCode: 2)],
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            },
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Tagged.txt"])
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Green", colorCode: 2)])
    }

    /// EVM-001-reload_directory_page_on_external_change: gateway observer registration does not miss an event at setup.
    /// Interest registration and observer teardown must leave one lifecycle-owned event stream ready before delivery
    /// begins.
    /// - 검증 내용: observer를 생성하기 직전에 도착한 gateway event의 registration 경계
    /// - 사전 조건: live FileChangeGatewayClient의 distributed event payload가 observer 생성 직전에 게시된다.
    /// - 기대 결과: setup 경계의 event가 observer stream에서 전달되고 stream cancellation 뒤 observer가 teardown된다.
    func testGatewayObserverRegistrationAndTeardownAreLifecycleOwned() async {
        let event = FileChangeGatewayEvent(
            path: "/tmp/voyager/registration.txt",
            flags: 1,
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let observerStarted = expectation(description: "Gateway observer task started")
        let receivedCount = LockIsolated(0)
        let gateway = FileChangeGatewayClient.liveValue
        let eventsStream = gateway.observeEvents()
        let task = Task {
            observerStarted.fulfill()
            DistributedNotificationCenter.default().post(
                name: .voyagerFileChangeGatewayEvents,
                object: nil,
                userInfo: FileChangeGatewayPayload.userInfo(forEvents: [event]),
            )
            for await events in eventsStream {
                if events.events == [event] {
                    receivedCount.withValue { $0 += 1 }
                }
            }
        }
        await fulfillment(of: [observerStarted], timeout: 1)
        try? await Task.sleep(for: .milliseconds(100))
        guard receivedCount.value == 1 else {
            XCTFail("Expected the setup event to be observed before cancellation")
            task.cancel()
            await task.value
            return
        }
        task.cancel()
        await task.value

        DistributedNotificationCenter.default().post(
            name: .voyagerFileChangeGatewayEvents,
            object: nil,
            userInfo: FileChangeGatewayPayload.userInfo(forEvents: [event]),
        )
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(receivedCount.value, 1)
    }

    /// EVM-001-reload_directory_page_on_external_change: fixed delivery token crosses notification decoding intact.
    /// 분산 알림 userInfo의 private delivery token이 raw event schema와 분리된 채 observer 경계로 전달되는지 검증한다.
    /// - 검증 내용: 고정 UUID token extraction
    /// - 사전 조건: notification userInfo에 UUID 형식 deliveryChainToken 하나가 존재한다.
    /// - 기대 결과: extraction 결과가 입력 token과 동일하다.
    func testGatewayDeliveryChainTokenPreservesFixedToken() {
        let fixedToken = "00000000-0000-0000-0000-000000000001"

        XCTAssertEqual(
            fileChangeGatewayDeliveryChainToken(from: ["deliveryChainToken": fixedToken]),
            fixedToken,
        )
    }
}

private extension EVM001NavigatePagesEntryLoadingAdapterTests {
    func collect(_ stream: AsyncThrowingStream<EntryLoadEvent, Error>) async throws -> [EntryLoadEvent] {
        var events: [EntryLoadEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func collectDirectory(
        _ directoryURL: URL,
        client: EntryLoadingClient,
        priority: EntryMetadataPriority,
    ) async throws -> [EntryLoadEvent] {
        try await withDependencies {
            $0.workspaceClient = .testValue
        } operation: {
            try await collect(client.loadItems(directoryURL, false, priority))
        }
    }

    func makeDirectoryStream(
        _ directoryURL: URL,
        client: EntryLoadingClient,
        priority: EntryMetadataPriority,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        withDependencies {
            $0.workspaceClient = .testValue
        } operation: {
            client.loadItems(directoryURL, false, priority)
        }
    }

    func collectDirectoryWithTimeout(
        _ directoryURL: URL,
        client: EntryLoadingClient,
        priority: EntryMetadataPriority,
    ) async throws -> [EntryLoadEvent] {
        let stream = makeDirectoryStream(directoryURL, client: client, priority: priority)
        return try await withThrowingTaskGroup(of: [EntryLoadEvent].self) { group in
            group.addTask {
                var events: [EntryLoadEvent] = []
                for try await event in stream {
                    events.append(event)
                }
                return events
            }
            group.addTask {
                try await Task.sleep(for: .seconds(1))
                throw DirectoryLoadTimeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    func visibleEntryClient() -> EntryLoadingClient {
        var client = EntryLoadingClient.testValue
        client.fileExistsAtPath = { path, isDirectory in
            isDirectory?.pointee = ObjCBool(path.contains("/Folder-"))
            return true
        }
        return client
    }

    func expectedBatchSizes(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return stride(from: 0, to: count, by: 32).map { min(32, count - $0) }
    }

    func makeEntry(path: String, isHidden: Bool = false) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1)
        return EntryModel(
            name: URL(fileURLWithPath: path).lastPathComponent,
            fullPath: path,
            isFolder: false,
            isHidden: isHidden,
            size: 1,
            modifiedDate: date,
            fileExtension: "txt",
            facets: .init(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: "File",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

private struct DirectorySymlinkFixture {
    let rootURL: URL
    let targetURL: URL
    let targetBURL: URL
    let targetChildURL: URL
    let ordinaryURL: URL
    let relativeAliasURL: URL
    let absoluteAliasURL: URL
    let aliasAURL: URL
    let aliasBURL: URL
    let brokenAliasURL: URL
    let selfLoopURL: URL
    let loopAURL: URL
    let loopBURL: URL

    static func make() throws -> DirectorySymlinkFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-717-entry-\(UUID().uuidString)", isDirectory: true)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let targetBURL = rootURL.appendingPathComponent("target-b", isDirectory: true)
        let ordinaryURL = rootURL.appendingPathComponent("ordinary", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetBURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ordinaryURL, withIntermediateDirectories: true)

        let targetChildURL = targetURL.appendingPathComponent("child.txt")
        try Data("target-a".utf8).write(to: targetChildURL)
        try Data("target-b".utf8).write(to: targetBURL.appendingPathComponent("child.txt"))
        try Data("ordinary".utf8).write(to: ordinaryURL.appendingPathComponent("child.txt"))

        let relativeAliasURL = rootURL.appendingPathComponent("alias-relative", isDirectory: true)
        let absoluteAliasURL = rootURL.appendingPathComponent("alias-absolute", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a", isDirectory: true)
        let aliasBURL = rootURL.appendingPathComponent("alias-b", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: relativeAliasURL.path, withDestinationPath: "target")
        try FileManager.default.createSymbolicLink(at: absoluteAliasURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(atPath: aliasAURL.path, withDestinationPath: "target")
        try FileManager.default.createSymbolicLink(atPath: aliasBURL.path, withDestinationPath: "target")

        let brokenAliasURL = rootURL.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: brokenAliasURL.path, withDestinationPath: "missing-target")
        let selfLoopURL = rootURL.appendingPathComponent("self-loop", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: selfLoopURL.path, withDestinationPath: "self-loop")
        let loopAURL = rootURL.appendingPathComponent("loop-a", isDirectory: true)
        let loopBURL = rootURL.appendingPathComponent("loop-b", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: loopAURL.path, withDestinationPath: "loop-b")
        try FileManager.default.createSymbolicLink(atPath: loopBURL.path, withDestinationPath: "loop-a")

        return DirectorySymlinkFixture(
            rootURL: rootURL,
            targetURL: targetURL,
            targetBURL: targetBURL,
            targetChildURL: targetChildURL,
            ordinaryURL: ordinaryURL,
            relativeAliasURL: relativeAliasURL,
            absoluteAliasURL: absoluteAliasURL,
            aliasAURL: aliasAURL,
            aliasBURL: aliasBURL,
            brokenAliasURL: brokenAliasURL,
            selfLoopURL: selfLoopURL,
            loopAURL: loopAURL,
            loopBURL: loopBURL,
        )
    }

    func liveClient() -> EntryLoadingClient {
        var client = EntryLoadingClient.liveValue
        client.getItemMetadata = { url, _, _ in
            EntryItemMetadata(
                kind: url.standardizedFileURL.path == targetChildURL.standardizedFileURL
                    .path ? "Fixture File" : "Other File",
                creatorApplication: nil,
                lastUsedDate: nil,
            )
        }
        client.directoryURLBatches = { requestedURL, _, _ in
            DirectorySymlinkBatchSource.stream {
                try FileManager.default.contentsOfDirectory(
                    at: requestedURL,
                    includingPropertiesForKeys: [],
                    options: [],
                )
            }
        }
        return client
    }

    func retargetRelativeAliasToTargetB() throws {
        try FileManager.default.removeItem(at: relativeAliasURL)
        try FileManager.default.createSymbolicLink(atPath: relativeAliasURL.path, withDestinationPath: "target-b")
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class DirectorySymlinkBatchSource: @unchecked Sendable {
    private let load: () throws -> [URL]
    private let lock = NSLock()
    private var didLoad = false

    init(load: @escaping () throws -> [URL]) {
        self.load = load
    }

    static func stream(load: @escaping () throws -> [URL]) -> AsyncThrowingStream<[URL], Error> {
        let source = DirectorySymlinkBatchSource(load: load)
        return AsyncThrowingStream(unfolding: { try source.next() })
    }

    private func next() throws -> [URL]? {
        try lock.withLock {
            guard !didLoad else { return nil }
            didLoad = true
            let urls = try load()
            return urls.isEmpty ? nil : urls
        }
    }
}

private final class LockedPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ path: String) {
        lock.withLock { storage.append(path) }
    }
}

private struct DirectoryLoadTimeoutError: Error {}

private extension [EntryLoadEvent] {
    var coreBatches: [(items: [EntryModel], batchIndex: Int)] {
        compactMap {
            guard case let .coreBatch(items, batchIndex) = $0 else { return nil }
            return (items, batchIndex)
        }
    }

    var coreFinishedCounts: [Int] {
        compactMap {
            guard case let .coreFinished(batchCount) = $0 else { return nil }
            return batchCount
        }
    }

    var metadataPatches: [EntryMetadataPatch] {
        flatMap { event -> [EntryMetadataPatch] in
            guard case let .metadataPatches(patches) = event else { return [] }
            return patches
        }
    }
}

private extension EntryLoadEvent {
    var isCoreEvent: Bool {
        switch self {
        case .coreBatch, .coreFinished:
            true
        case .metadataPatches:
            false
        }
    }

    var isCoreFinished: Bool {
        if case .coreFinished = self { return true }
        return false
    }

    var isMetadataPatchEvent: Bool {
        if case .metadataPatches = self { return true }
        return false
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

private final class ProbeTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private var didObserveCoreFinished = false
    private var storage = false

    var didProbeBeforeCoreFinished: Bool {
        lock.withLock { storage }
    }

    func recordCoreFinished() {
        lock.withLock { didObserveCoreFinished = true }
    }

    func recordProbe() {
        lock.withLock { storage = storage || !didObserveCoreFinished }
    }
}

private final class ProbeGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var didStart = false
    private var isOpen = false

    func waitForProbeStart() {
        condition.lock()
        defer { condition.unlock() }
        while !didStart {
            condition.wait()
        }
    }

    func waitUntilOpened() {
        condition.lock()
        didStart = true
        condition.broadcast()
        while !isOpen {
            condition.wait()
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class ResolverInterleavingGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var didResolve = false
    private var storedError: Error?

    func markResolverReturned() {
        condition.lock()
        didResolve = true
        condition.broadcast()
        condition.unlock()
    }

    func waitForResolverReturn() {
        condition.lock()
        while !didResolve {
            condition.wait()
        }
        condition.unlock()
    }

    func retarget(using fixture: DirectorySymlinkFixture) {
        do {
            try fixture.retargetRelativeAliasToTargetB()
        } catch {
            condition.lock()
            storedError = error
            condition.unlock()
        }
    }

    var error: Error? {
        condition.lock()
        defer { condition.unlock() }
        return storedError
    }

    /// EVM-001-reload_directory_page_on_external_change: directory loader uses injected favorite color.
    /// Directory refresh must resolve favorite tags before detached filesystem work begins.
    /// - 검증 내용: EntryLoadingLive.loadItems가 주입된 favorite 색상으로 directory entry를 정규화하는지 확인
    /// - 사전 조건: 임시 directory 파일에 색상 없는 태그가 저장되고 favorite client가 같은 이름의 색상을 반환함
    /// - 기대 결과: directory loader 결과의 태그가 주입된 favorite 색상으로 정규화됨
    func testDirectoryAdapterUsesInjectedFavoriteTagColor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerEntryLoading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Tagged.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        let tagName = "InjectedFavorite"
        let favoriteTag = Tag(name: tagName, colorCode: 6)
        try TagMetadataClient.setTags([Tag(name: tagName, colorCode: 0)], for: fileURL)

        let items = try? await withDependencies {
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [tagName] },
                favoriteTags: { [favoriteTag] },
            )
        } operation: {
            try await EntryLoadingLive.loadItems(directory, true)
        }

        XCTAssertEqual(items?.first?.facets.tags, [favoriteTag])
    }

    /// EVM-001-reload_directory_page_on_external_change: Recents loader uses injected favorite color.
    /// Recents refresh must normalize helper payload tags with the scoped favorite client.
    /// - 검증 내용: Recents loader가 주입된 favorite 색상으로 payload tag를 정규화하는지 확인
    /// - 사전 조건: Recents search closure가 색상 없는 동일 이름 tag payload를 반환함
    /// - 기대 결과: Recents 결과의 태그가 주입된 favorite 색상으로 정규화됨
    func testRecentAdapterUsesInjectedFavoriteTagColor() async {
        let tagName = "InjectedFavorite"
        let favoriteTag = Tag(name: tagName, colorCode: 6)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await withDependencies {
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [tagName] },
                favoriteTags: { [favoriteTag] },
            )
        } operation: {
            await EntryLoadingLive.loadRecentItemsViaSearch(showHidden: false) { _ in
                RecentSearchResponsePayload(
                    items: [
                        SearchEntryPayload(
                            name: "Recent.txt",
                            fullPath: "/tmp/Recent.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 1,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: nil,
                            kind: "Text",
                            creatorApplication: nil,
                            tags: [SearchTagPayload(name: tagName, colorCode: 0)],
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            }
        }

        XCTAssertEqual(items.first?.facets.tags, [favoriteTag])
    }

    /// EVM-001-reload_directory_page_on_external_change: tag-search loader uses injected favorite color.
    /// Tag route refresh must normalize helper payload tags with the scoped favorite client.
    /// - 검증 내용: Tag search loader가 주입된 favorite 색상으로 payload tag를 정규화하는지 확인
    /// - 사전 조건: Tag search closure가 색상 없는 동일 이름 tag payload를 반환함
    /// - 기대 결과: Tag search 결과의 태그가 주입된 favorite 색상으로 정규화됨
    func testTagAdapterUsesInjectedFavoriteTagColor() async {
        let tagName = "InjectedFavorite"
        let favoriteTag = Tag(name: tagName, colorCode: 6)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await withDependencies {
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [tagName] },
                favoriteTags: { [favoriteTag] },
            )
        } operation: {
            await EntryLoadingLive.loadFilesWithTagViaSearch(tag: tagName, showHidden: false) { request in
                TagSearchResponsePayload(
                    requestedTag: request.requestedTag,
                    items: [
                        SearchEntryPayload(
                            name: "Tagged.txt",
                            fullPath: "/tmp/Tagged.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 1,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: nil,
                            kind: "Text",
                            creatorApplication: nil,
                            tags: [SearchTagPayload(name: tagName, colorCode: 0)],
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            }
        }

        XCTAssertEqual(items.first?.facets.tags, [favoriteTag])
    }
}
