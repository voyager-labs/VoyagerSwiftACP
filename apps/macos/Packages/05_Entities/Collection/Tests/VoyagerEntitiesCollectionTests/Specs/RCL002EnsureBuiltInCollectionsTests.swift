@_spi(Internals)
import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class RCL002EnsureBuiltInCollectionsTests: XCTestCase {
    // VOY-570 Linear AC mapping (RCL owner):
    // AC2 -> testEnsure_emptyRootCreatesAndReloadsCanonicalPackages
    // AC3 -> testEnsure_emptyRootCreatesAndReloadsCanonicalPackages
    // AC4 -> testEnsure_zeroTagsDefersAllTagsAndLeavesExistingFileUntouched
    // AC6/AC7 -> testEnsure_changedTagsRepairsPackageWhilePinnedSeedRemainsSuppressed
    // AC8 -> testEnsure_corruptPackageRepairsAtCanonicalIdentityAndURL
    // AC9 -> testEnsure_oneItemWriteFailurePreservesOtherReadyResult
    // AC10 -> testEnsure_healthyPackagesDoesNotRewrite
    // Metrics/privacy -> testEnsure_emitsCanonicalLifecycleMetricsWithoutSensitiveMetadata

    // MARK: - RCL-002-ensure_built_in_collections

    /// RCL-002-ensure_built_in_collections: empty root에서 canonical built-in packages 생성
    /// ensure가 Application Support를 한 번만 resolve하고 저장 후 실제 package를 reload하는지 검증한다.
    /// - 검증 내용: Recents/All Tags ready descriptor, canonical URL/ID/schema/definition, root 생성
    /// - 사전 조건: 비어 있는 임시 Application Support와 Finder tags `Work`, `Personal`
    /// - 기대 결과: 두 package가 definition-only current schema로 생성되고 reload됨
    func testEnsure_emptyRootCreatesAndReloadsCanonicalPackages() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        let urlLookupCount = LockIsolated(0)

        let report = await fixture.ensure(
            tags: [" Work ", "Personal", "Work"],
            now: fixture.firstNow,
            urlLookupCount: urlLookupCount,
        )

        let recents = try readyDescriptor(report.recents)
        let allTags = try readyDescriptor(report.allTags)
        XCTAssertEqual(recents.identity, .recents)
        XCTAssertEqual(allTags.identity, .allTags)
        XCTAssertEqual(recents.packageURL, fixture.packageURL(for: .recents))
        XCTAssertEqual(allTags.packageURL, fixture.packageURL(for: .allTags))
        XCTAssertEqual(urlLookupCount.value, 1)
        try await fixture.assertCanonical(.recents, tags: [])
        try await fixture.assertCanonical(.allTags, tags: ["Personal", "Work"])
    }

    /// RCL-002-ensure_built_in_collections: healthy packages는 timestamp/appVersion 차이만으로 rewrite하지 않음
    /// semantic definition이 같으면 기존 파일 metadata 차이를 보존하고 save를 생략하는지 검증한다.
    /// - 검증 내용: 두 번째 ensure의 save call 0회와 기존 createdAt/updatedAt/appVersion 보존
    /// - 사전 조건: canonical packages를 만든 뒤 timestamp/appVersion만 변경한 package
    /// - 기대 결과: 두 item ready, 추가 save 없음
    func testEnsure_healthyPackagesDoesNotRewrite() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        _ = await fixture.ensure(tags: ["Work"], now: fixture.firstNow)
        let metadataNow = Date(timeIntervalSince1970: 1_600_000_000)
        try await fixture.replaceMetadata(
            identity: .recents,
            createdAt: metadataNow,
            updatedAt: metadataNow.addingTimeInterval(10),
            appVersion: "legacy-build",
        )
        let saveURLs = LockIsolated<[URL]>([])

        let report = await fixture.ensure(tags: ["Work"], now: fixture.secondNow, saveURLs: saveURLs)
        let loaded = try await fixture.load(.recents).file

        _ = try readyDescriptor(report.recents)
        _ = try readyDescriptor(report.allTags)
        XCTAssertTrue(saveURLs.value.isEmpty)
        XCTAssertEqual(loaded.createdAt, metadataNow)
        XCTAssertEqual(loaded.updatedAt, metadataNow.addingTimeInterval(10))
        XCTAssertEqual(loaded.appVersion, "legacy-build")
    }

    /// RCL-002-ensure_built_in_collections: stale All Tags는 stable identity와 createdAt을 보존해 sync
    /// Finder tag snapshot 변경이 같은 canonical URL의 definition만 repair하는지 검증한다.
    /// - 검증 내용: URL/ID/createdAt 보존, updatedAt 갱신, normalized tag condition
    /// - 사전 조건: `Work`로 생성된 All Tags와 다음 invocation의 `Personal`, `work`
    /// - 기대 결과: 같은 package가 새 tag set으로 reload 검증됨
    func testEnsure_changedTagsRepairsSamePackageAndPreservesCreatedAt() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        _ = await fixture.ensure(tags: ["Work"], now: fixture.firstNow)
        let original = try await fixture.load(.allTags).file

        let report = await fixture.ensure(tags: [" work ", "Personal"], now: fixture.secondNow)
        let descriptor = try readyDescriptor(report.allTags)
        let repaired = try await fixture.load(.allTags).file

        XCTAssertEqual(descriptor.packageURL, fixture.packageURL(for: .allTags))
        XCTAssertEqual(repaired.id, BuiltInCollectionIdentity.allTags.rawValue)
        XCTAssertEqual(repaired.createdAt, original.createdAt)
        XCTAssertEqual(repaired.updatedAt, fixture.secondNow)
        XCTAssertEqual(fixture.tagValues(in: repaired), ["Personal", "work"])
    }

    /// RCL-002-ensure_built_in_collections: corrupt package는 같은 identity와 URL에서 repair
    /// decode 실패를 item failure로 끝내지 않고 canonical save 후 post-load 검증하는지 확인한다.
    /// - 검증 내용: corrupt Recents payload 교체, recreated timestamps, canonical definition
    /// - 사전 조건: canonical Recents URL에 유효하지 않은 collection.plist가 존재
    /// - 기대 결과: Recents ready이고 createdAt/updatedAt이 injected now와 같음
    func testEnsure_corruptPackageRepairsAtCanonicalIdentityAndURL() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        try fixture.writeCorruptPackage(.recents)
        let saveURLs = LockIsolated<[URL]>([])

        let report = await fixture.ensure(tags: [], now: fixture.firstNow, saveURLs: saveURLs)
        let descriptor = try readyDescriptor(report.recents)
        let repaired = try await fixture.load(.recents).file

        XCTAssertEqual(descriptor.packageURL, fixture.packageURL(for: .recents))
        XCTAssertEqual(saveURLs.value, [fixture.packageURL(for: .recents)])
        XCTAssertEqual(repaired.id, BuiltInCollectionIdentity.recents.rawValue)
        XCTAssertEqual(repaired.createdAt, fixture.firstNow)
        XCTAssertEqual(repaired.updatedAt, fixture.firstNow)
        try await fixture.assertCanonical(.recents, tags: [])
    }

    /// RCL-002-ensure_built_in_collections: managed root symlink가 외부를 가리키면 모든 item을 차단
    /// root 생성 전 resolved containment를 검사해 canonical path를 통한 외부 write를 막는지 검증한다.
    /// - 검증 내용: Recents/All Tags failed, 외부 sentinel 보존, package payload 미생성
    /// - 사전 조건: canonical BuiltIn root가 Application Support sibling directory를 가리키는 symlink
    /// - 기대 결과: 공통 root 준비 실패로 두 item 모두 failed이며 외부 directory는 변경되지 않음
    func testEnsure_rootSymlinkEscapeFailsWithoutOutsideWrite() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        let outsideURL = try fixture.makeOutsideDirectory(named: "RootEscape")
        let sentinel = try fixture.writeSentinel(in: outsideURL)
        try fixture.installSymlink(at: fixture.rootURL, destination: outsideURL)

        let report = await fixture.ensure(tags: ["Work"], now: fixture.firstNow)

        assertFailed(report.recents)
        assertFailed(report.allTags)
        XCTAssertEqual(try Data(contentsOf: sentinel.url), sentinel.data)
        XCTAssertFalse(fixture.payloadExists(in: outsideURL, identity: .recents))
        XCTAssertFalse(fixture.payloadExists(in: outsideURL, identity: .allTags))
    }

    /// RCL-002-ensure_built_in_collections: package symlink escape는 해당 item만 격리
    /// package load/save 전 resolved containment를 검사하면서 다른 item ensure는 계속되는지 검증한다.
    /// - 검증 내용: Recents failed, All Tags ready, 외부 sentinel 보존 및 payload 미생성
    /// - 사전 조건: canonical Recents package가 managed root 밖 directory를 가리키는 symlink
    /// - 기대 결과: Recents 외부 write 없이 실패하고 All Tags는 canonical package로 생성됨
    func testEnsure_packageSymlinkEscapeFailsItemWithoutOutsideWrite() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        try fixture.createCanonicalRoot()
        let outsideURL = try fixture.makeOutsideDirectory(named: "PackageEscape")
        let sentinel = try fixture.writeSentinel(in: outsideURL)
        try fixture.installSymlink(at: fixture.packageURL(for: .recents), destination: outsideURL)

        let report = await fixture.ensure(tags: ["Work"], now: fixture.firstNow)

        assertFailed(report.recents)
        _ = try readyDescriptor(report.allTags)
        XCTAssertEqual(try Data(contentsOf: sentinel.url), sentinel.data)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: outsideURL.appendingPathComponent("collection.plist").path,
        ))
        try await fixture.assertCanonical(.allTags, tags: ["Work"])
    }

    /// RCL-002-ensure_built_in_collections: sibling package symlink는 canonical identity를 침범할 수 없음
    /// managed root 내부라도 다른 identity package로 resolve되면 load/save를 차단하는지 검증한다.
    /// - 검증 내용: Recents failed, All Tags ready, 기존 All Tags payload 보존
    /// - 사전 조건: Recents canonical URL이 기존 All Tags package를 가리키는 symlink
    /// - 기대 결과: Recents가 All Tags payload를 덮지 않고 item failure로 격리됨
    func testEnsure_packageSymlinkToSiblingIdentityFailsWithoutOverwrite() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        _ = await fixture.ensure(tags: ["Work"], now: fixture.firstNow)
        let allTagsPayload = try fixture.payloadData(.allTags)
        try FileManager.default.removeItem(at: fixture.packageURL(for: .recents))
        try fixture.installSymlink(
            at: fixture.packageURL(for: .recents),
            destination: fixture.packageURL(for: .allTags),
        )

        let report = await fixture.ensure(tags: ["Work"], now: fixture.secondNow)

        assertFailed(report.recents)
        _ = try readyDescriptor(report.allTags)
        XCTAssertEqual(try fixture.payloadData(.allTags), allTagsPayload)
        try await fixture.assertCanonical(.allTags, tags: ["Work"])
    }

    /// RCL-002-ensure_built_in_collections: zero normalized tags는 기존 All Tags를 그대로 defer
    /// 빈 Finder snapshot이 기존 package를 삭제하거나 empty condition으로 덮지 않는지 검증한다.
    /// - 검증 내용: All Tags deferred, package payload byte 보존, Recents ready
    /// - 사전 조건: 기존 `Work` package와 whitespace-only tag snapshot
    /// - 기대 결과: 기존 파일 untouched, All Tags completion 후보 없음
    func testEnsure_zeroTagsDefersAllTagsAndLeavesExistingFileUntouched() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        _ = await fixture.ensure(tags: ["Work"], now: fixture.firstNow)
        let before = try fixture.payloadData(.allTags)

        let report = await fixture.ensure(tags: [" ", "\t\n"], now: fixture.secondNow)

        _ = try readyDescriptor(report.recents)
        guard case .deferred = report.allTags else {
            return XCTFail("Expected All Tags to be deferred")
        }
        XCTAssertEqual(try fixture.payloadData(.allTags), before)
    }

    /// RCL-002-ensure_built_in_collections: 한 item write 실패가 다른 item ensure를 막지 않음
    /// Recents save failure를 report로 격리하면서 All Tags lifecycle은 계속 실행하는지 검증한다.
    /// - 검증 내용: Recents failed, All Tags ready 및 canonical reload
    /// - 사전 조건: Recents URL save만 throw하는 injected CollectionFileClient
    /// - 기대 결과: ensure는 throw하지 않고 독립 결과를 반환함
    func testEnsure_oneItemWriteFailurePreservesOtherReadyResult() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }

        let report = await fixture.ensure(
            tags: ["Work"],
            now: fixture.firstNow,
            failingIdentity: .recents,
        )

        guard case .failed = report.recents else {
            return XCTFail("Expected Recents to fail")
        }
        _ = try readyDescriptor(report.allTags)
        try await fixture.assertCanonical(.allTags, tags: ["Work"])
    }

    /// RCL-002-ensure_built_in_collections: concurrent ensure invocations는 coordinator에서 직렬화
    /// overlapping bootstrap이 package write를 겹치지 않게 하고 마지막 tag snapshot을 canonical하게 남기는지 검증한다.
    /// - 검증 내용: save boundary 최대 동시 실행 1회, 최종 package reload canonical
    /// - 사전 조건: 서로 다른 tag snapshot으로 동시에 시작한 두 ensure task
    /// - 기대 결과: 두 report 완료 후 package가 둘 중 하나의 완전한 canonical definition이며 write overlap 없음
    func testEnsure_concurrentInvocationsSerializePackageWrites() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        let probe = BuiltInCollectionSaveProbe()

        async let first = fixture.ensure(tags: ["First"], now: fixture.firstNow, saveProbe: probe)
        async let second = fixture.ensure(tags: ["Second"], now: fixture.secondNow, saveProbe: probe)
        _ = await (first, second)

        let loaded = try await fixture.load(.allTags).file
        let maximumConcurrentSaves = await probe.maximumConcurrentSaves()
        XCTAssertEqual(maximumConcurrentSaves, 1)
        XCTAssertTrue([["First"], ["Second"]].contains(fixture.tagValues(in: loaded)))
        XCTAssertEqual(loaded.id, BuiltInCollectionIdentity.allTags.rawValue)
        XCTAssertEqual(loaded.name, BuiltInCollectionIdentity.allTags.collectionName)
        XCTAssertEqual(loaded.schemaVersion, CollectionFileSchemaVersion.definitionOnlyCurrent)
        XCTAssertEqual(loaded.query, "")
        XCTAssertEqual(loaded.scopes, [])
        XCTAssertEqual(loaded.excludedScopes, [])
        XCTAssertTrue(loaded.includeSubfolders)
        XCTAssertTrue(loaded.includeDirectories)
        XCTAssertEqual(loaded.conditions.count, 1)
        XCTAssertNil(loaded.snapshot)
        XCTAssertNil(loaded.snapshotMeta)
    }

    /// RCL-002-ensure_built_in_collections: 취소된 queued ensure는 operation에 진입하지 않는다.
    /// cancellation handler가 waiter를 제거해 뒤의 bootstrap이 취소된 caller를 기다리지 않는지 검증한다.
    /// - 검증 내용: queued waiter 제거, cancelled operation 미진입, 최신 operation의 직렬 진입
    /// - 사전 조건: 첫 operation이 gate를 점유한 동안 두 번째 operation을 queue 후 취소
    /// - 기대 결과: 첫 번째와 최신 operation만 실행되고 queue에는 취소된 waiter가 남지 않음
    func testEnsure_cancelledQueuedInvocationNeverEntersAndDoesNotDelayNewerInvocation() async throws {
        let coordinator = BuiltInCollectionEnsureCoordinator()
        let entries = LockIsolated<[String]>([])
        let firstStarted = AsyncStream<Void>.makeStream()
        let releaseFirst = AsyncStream<Void>.makeStream()
        let first = Task {
            try await coordinator.run {
                entries.withValue { $0.append("first") }
                firstStarted.continuation.yield()
                for await _ in releaseFirst.stream {
                    break
                }
                return "first"
            }
        }
        var firstStartedIterator = firstStarted.stream.makeAsyncIterator()
        _ = await firstStartedIterator.next()

        let cancelled = Task {
            try await coordinator.run {
                entries.withValue { $0.append("cancelled") }
                return "cancelled"
            }
        }
        let didQueueCancelled = await waitUntilQueuedOperation(on: coordinator)
        XCTAssertTrue(didQueueCancelled)

        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled queued operation must throw CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let queuedAfterCancellation = await coordinator.queuedOperationCount
        XCTAssertEqual(queuedAfterCancellation, 0)

        let newest = Task {
            try await coordinator.run {
                entries.withValue { $0.append("newest") }
                return "newest"
            }
        }
        let didQueueNewest = await waitUntilQueuedOperation(on: coordinator)
        XCTAssertTrue(didQueueNewest)

        releaseFirst.continuation.yield()
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, "first")
        let newestValue = try await newest.value
        let recordedEntries = entries.value
        let finalQueuedOperationCount = await coordinator.queuedOperationCount
        XCTAssertEqual(newestValue, "newest")
        XCTAssertEqual(recordedEntries, ["first", "newest"])
        XCTAssertEqual(finalQueuedOperationCount, 0)
    }

    /// RCL-002-ensure_built_in_collections: package lifecycle metrics는 canonical event와 비민감 metadata만 기록한다.
    /// 실제 package 생성·defer·repair·failure 경로가 product 결과와 독립적으로 관측되는지 검증한다.
    /// - 검증 내용: exact event names, identity/outcome 전용 metadata, 실제 package round-trip
    /// - 사전 조건: 민감한 tag 문자열, zero tags, stale All Tags, corrupt Recents와 injected write failure
    /// - 기대 결과: 5개 canonical event 종류만 발생하고 tag/path/query payload는 metadata에 없음
    func testEnsure_emitsCanonicalLifecycleMetricsWithoutSensitiveMetadata() async throws {
        let fixture = try BuiltInCollectionTestFixture()
        defer { fixture.cleanup() }
        let metrics = LockIsolated<[BuiltInLifecycleMetric]>([])
        let sensitiveTag = "Sensitive Work /Users/alice?query=secret"

        try await exerciseLifecycleMetricScenarios(
            fixture: fixture,
            metrics: metrics,
            sensitiveTag: sensitiveTag,
        )

        XCTAssertEqual(metrics.value, Self.expectedLifecycleMetrics)
        try assertLifecycleMetricPrivacy(metrics.value, sensitiveTag: sensitiveTag)
    }

    private func exerciseLifecycleMetricScenarios(
        fixture: BuiltInCollectionTestFixture,
        metrics: LockIsolated<[BuiltInLifecycleMetric]>,
        sensitiveTag: String,
    ) async throws {
        _ = await fixture.ensure(tags: [], now: fixture.firstNow, metrics: metrics)
        _ = await fixture.ensure(tags: [sensitiveTag], now: fixture.secondNow, metrics: metrics)
        _ = await fixture.ensure(tags: ["Changed"], now: fixture.secondNow, metrics: metrics)
        try fixture.writeCorruptPackage(.recents)
        let failureReport = await fixture.ensure(
            tags: ["Changed"],
            now: fixture.secondNow,
            failingIdentity: .recents,
            metrics: metrics,
        )

        guard case .failed = failureReport.recents else {
            return XCTFail("corrupt Recents의 injected repair failure가 report에 남아야 함")
        }
        try await fixture.assertCanonical(.allTags, tags: ["Changed"])
    }

    private func assertLifecycleMetricPrivacy(
        _ metrics: [BuiltInLifecycleMetric],
        sensitiveTag: String,
    ) throws {
        for metric in metrics {
            if metric.name == "built_in_collection_ensure_started" {
                XCTAssertTrue(metric.tags.isEmpty)
                continue
            }
            let tags = metric.tags
            XCTAssertEqual(Set(tags.keys), Set(["identity", "outcome"]))
            XCTAssertTrue(["recents", "all_tags"].contains(tags["identity"]))
            XCTAssertEqual(tags["outcome"], metric.name.replacingOccurrences(
                of: "built_in_collection_item_",
                with: "",
            ))
            let metadata = tags.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            XCTAssertFalse(metadata.contains(sensitiveTag))
            XCTAssertFalse(metadata.contains("/Users/"))
            XCTAssertFalse(metadata.contains("query="))
        }
    }

    private static let expectedLifecycleMetrics: [BuiltInLifecycleMetric] = [
        .init(name: "built_in_collection_ensure_started", value: 1, tags: [:]),
        .init(
            name: "built_in_collection_item_ensured",
            value: 1,
            tags: ["identity": "recents", "outcome": "ensured"],
        ),
        .init(
            name: "built_in_collection_item_deferred",
            value: 1,
            tags: ["identity": "all_tags", "outcome": "deferred"],
        ),
        .init(name: "built_in_collection_ensure_started", value: 1, tags: [:]),
        .init(
            name: "built_in_collection_item_ensured",
            value: 1,
            tags: ["identity": "recents", "outcome": "ensured"],
        ),
        .init(
            name: "built_in_collection_item_ensured",
            value: 1,
            tags: ["identity": "all_tags", "outcome": "ensured"],
        ),
        .init(name: "built_in_collection_ensure_started", value: 1, tags: [:]),
        .init(
            name: "built_in_collection_item_ensured",
            value: 1,
            tags: ["identity": "recents", "outcome": "ensured"],
        ),
        .init(
            name: "built_in_collection_item_repaired",
            value: 1,
            tags: ["identity": "all_tags", "outcome": "repaired"],
        ),
        .init(name: "built_in_collection_ensure_started", value: 1, tags: [:]),
        .init(
            name: "built_in_collection_item_failed",
            value: 1,
            tags: ["identity": "recents", "outcome": "failed"],
        ),
        .init(
            name: "built_in_collection_item_ensured",
            value: 1,
            tags: ["identity": "all_tags", "outcome": "ensured"],
        ),
    ]

    private func waitUntilQueuedOperation(
        on coordinator: BuiltInCollectionEnsureCoordinator,
    ) async -> Bool {
        for _ in 0 ..< 1000 {
            if await coordinator.queuedOperationCount > 0 { return true }
            await Task.yield()
        }
        return false
    }

    private func assertFailed(_ result: BuiltInCollectionEnsureItemResult) {
        guard case .failed = result else {
            return XCTFail("Expected built-in item to fail")
        }
    }

    private func readyDescriptor(
        _ result: BuiltInCollectionEnsureItemResult,
    ) throws -> BuiltInCollectionDescriptor {
        guard case let .ready(descriptor) = result else {
            throw BuiltInCollectionTestError.expectedReady
        }
        return descriptor
    }
}

private struct BuiltInLifecycleMetric: Equatable {
    let name: String
    let value: Double
    let tags: [String: String]
}

private enum BuiltInCollectionTestError: Error {
    case expectedReady
    case injectedWriteFailure
}

private final class BuiltInCollectionTestFixture: @unchecked Sendable {
    let applicationSupportURL: URL
    let firstNow = Date(timeIntervalSince1970: 1_700_000_000)
    let secondNow = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RCL002BuiltInCollections-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    var rootURL: URL {
        BuiltInCollectionIdentity.canonicalRootURL(applicationSupportURL: applicationSupportURL)
    }

    func packageURL(for identity: BuiltInCollectionIdentity) -> URL {
        identity.canonicalPackageURL(applicationSupportURL: applicationSupportURL)
    }

    func createCanonicalRoot() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func makeOutsideDirectory(named name: String) throws -> URL {
        let url = applicationSupportURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func installSymlink(at url: URL, destination: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
    }

    func writeSentinel(in directoryURL: URL) throws -> (url: URL, data: Data) {
        let url = directoryURL.appendingPathComponent("sentinel.txt")
        let data = Data("outside sentinel".utf8)
        try data.write(to: url)
        return (url, data)
    }

    func payloadExists(in rootURL: URL, identity: BuiltInCollectionIdentity) -> Bool {
        let packageURL = rootURL.appendingPathComponent(identity.packageFilename, isDirectory: true)
        return FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("collection.plist").path,
        )
    }

    func ensure(
        tags: [String],
        now: Date,
        urlLookupCount: LockIsolated<Int>? = nil,
        saveURLs: LockIsolated<[URL]>? = nil,
        failingIdentity: BuiltInCollectionIdentity? = nil,
        saveProbe: BuiltInCollectionSaveProbe? = nil,
        metrics: LockIsolated<[BuiltInLifecycleMetric]>? = nil,
    ) async -> BuiltInCollectionEnsureReport {
        let appSupport = applicationSupportURL
        var fileManagerClient = FileManagerClient.liveValue
        fileManagerClient.urlsForDirectory = { directory, domain in
            XCTAssertEqual(directory, .applicationSupportDirectory)
            XCTAssertEqual(domain, .userDomainMask)
            urlLookupCount?.withValue { $0 += 1 }
            return [appSupport]
        }
        let collectionClient = makeCollectionClient(
            saveURLs: saveURLs,
            failingIdentity: failingIdentity,
            saveProbe: saveProbe,
        )
        let normalizedTags = Array(Set(tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }))
            .sorted()
        return await withDependencies {
            $0.collectionFileClient = collectionClient
            $0.fileManagerClient = fileManagerClient
            $0.collectionMetricClient = CollectionMetricClient(
                logMetric: { name, value, tags, _ in
                    metrics?.withValue { $0.append(.init(name: name, value: value, tags: tags)) }
                },
            )
            $0.date = .constant(now)
        } operation: {
            await BuiltInCollectionClient.liveValue.ensureAll(
                makeRecentsContext(),
                normalizedTags.isEmpty ? nil : makeAllTagsContext(tags: normalizedTags),
            )
        }
    }

    private func makeRecentsContext() -> CollectionContext {
        CollectionContext(
            includeSubfolders: true,
            includeDirectories: false,
            conditions: [
                Condition(
                    propertyKey: "last_used_date",
                    propertyLabel: "last_used_date",
                    propertyType: "date",
                    operatorCode: "gt",
                    operatorValueArity: 1,
                    valueType: "unknown",
                    values: ["$time.today(-1000000)"],
                ),
                Condition(
                    propertyKey: "content_type_tree",
                    propertyLabel: "content_type_tree",
                    propertyType: "string",
                    operatorCode: "neq",
                    operatorValueArity: 1,
                    valueType: "string",
                    values: ["public.folder"],
                ),
            ],
        )
    }

    private func makeAllTagsContext(tags: [String]) -> CollectionContext {
        CollectionContext(
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [
                Condition(
                    propertyKey: "tag_names",
                    propertyLabel: "tag_names",
                    propertyType: "categorical",
                    operatorCode: "any",
                    operatorValueArity: 1,
                    operatorValueUIKind: "listText",
                    valueType: "categorical",
                    values: tags,
                ),
            ],
        )
    }

    private func makeCollectionClient(
        saveURLs: LockIsolated<[URL]>?,
        failingIdentity: BuiltInCollectionIdentity?,
        saveProbe: BuiltInCollectionSaveProbe?,
    ) -> CollectionFileClient {
        let liveCollectionClient = CollectionFileClient.liveValue
        let appSupport = applicationSupportURL
        return CollectionFileClient(
            save: { file, url in
                saveURLs?.withValue { $0.append(url) }
                if BuiltInCollectionIdentity.classify(
                    packageURL: url,
                    applicationSupportURL: appSupport,
                ) == failingIdentity {
                    throw BuiltInCollectionTestError.injectedWriteFailure
                }
                await saveProbe?.enter()
                do {
                    for _ in 0 ..< 50 {
                        await Task.yield()
                    }
                    try await liveCollectionClient.save(file, url)
                    await saveProbe?.leave()
                } catch {
                    await saveProbe?.leave()
                    throw error
                }
            },
            load: liveCollectionClient.load,
        )
    }

    func load(_ identity: BuiltInCollectionIdentity) async throws -> CollectionFileLoadResult {
        try await CollectionFileClient.liveValue.load(packageURL(for: identity))
    }

    func assertCanonical(_ identity: BuiltInCollectionIdentity, tags: [String]) async throws {
        let file = try await load(identity).file
        XCTAssertEqual(file.id, identity.rawValue)
        XCTAssertEqual(file.name, identity.collectionName)
        XCTAssertEqual(file.schemaVersion, CollectionFileSchemaVersion.definitionOnlyCurrent)
        XCTAssertEqual(file.query, "")
        XCTAssertEqual(file.scopes, [])
        XCTAssertEqual(file.excludedScopes, [])
        XCTAssertTrue(file.includeSubfolders)
        assertCanonicalConditions(file, identity: identity, tags: tags)
        XCTAssertNil(file.snapshot)
        XCTAssertNil(file.snapshotMeta)
        XCTAssertNil(file.appVersion)
    }

    private func assertCanonicalConditions(
        _ file: VoyagerCollectionFile,
        identity: BuiltInCollectionIdentity,
        tags: [String],
    ) {
        switch identity {
        case .recents:
            XCTAssertFalse(file.includeDirectories)
            XCTAssertEqual(file.conditions, [
                CollectionCondition(
                    propertyKey: "last_used_date",
                    operatorCode: "gt",
                    value: .string("$time.today(-1000000)"),
                ),
                CollectionCondition(
                    propertyKey: "content_type_tree",
                    operatorCode: "neq",
                    value: .string("public.folder"),
                ),
            ])
        case .allTags:
            XCTAssertTrue(file.includeDirectories)
            XCTAssertEqual(file.conditions, [
                CollectionCondition(
                    propertyKey: "tag_names",
                    operatorCode: "any",
                    value: .array(tags.map(JSONValue.string)),
                ),
            ])
        }
    }

    func replaceMetadata(
        identity: BuiltInCollectionIdentity,
        createdAt: Date,
        updatedAt: Date,
        appVersion: String,
    ) async throws {
        let file = try await load(identity).file
        let replacement = VoyagerCollectionFile(
            schemaVersion: file.schemaVersion,
            id: file.id,
            name: file.name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            query: file.query,
            scopes: file.scopes,
            excludedScopes: file.excludedScopes,
            includeSubfolders: file.includeSubfolders,
            includeDirectories: file.includeDirectories,
            conditions: file.conditions,
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: appVersion,
        )
        try await CollectionFileClient.liveValue.save(replacement, packageURL(for: identity))
    }

    func writeCorruptPackage(_ identity: BuiltInCollectionIdentity) throws {
        let url = packageURL(for: identity)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: url.appendingPathComponent("collection.plist"))
    }

    func payloadData(_ identity: BuiltInCollectionIdentity) throws -> Data {
        try Data(contentsOf: packageURL(for: identity).appendingPathComponent("collection.plist"))
    }

    func tagValues(in file: VoyagerCollectionFile) -> [String] {
        guard let value = file.conditions.first(where: { $0.propertyKey == "tag_names" })?.value,
              case let .array(values) = value
        else { return [] }
        return values.compactMap { value in
            guard case let .string(name) = value else { return nil }
            return name
        }
    }
}

private actor BuiltInCollectionSaveProbe {
    private var activeSaves = 0
    private var maximumSaves = 0

    func enter() {
        activeSaves += 1
        maximumSaves = max(maximumSaves, activeSaves)
    }

    func leave() {
        activeSaves -= 1
    }

    func maximumConcurrentSaves() -> Int {
        maximumSaves
    }
}
