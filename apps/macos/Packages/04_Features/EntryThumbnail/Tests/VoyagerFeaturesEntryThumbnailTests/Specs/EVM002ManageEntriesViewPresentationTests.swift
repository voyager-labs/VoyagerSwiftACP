import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryThumbnail
import VoyagerShared
import XCTest

@MainActor
final class EVM002ManageEntriesViewPresentationTests: XCTestCase {
    // MARK: - EVM-002-set_entries_view_as_icon_grid

    /// EVM-002-set_entries_view_as_icon_grid: 요청 후보에서 처리 불필요한 경로 제외
    /// icon projection을 지원하는 package 기술 계약으로 중복 및 완료된 lifecycle 경로를 다시 처리하지 않는다.
    /// - 검증 내용: 중복, ready, in-flight, failed 경로를 제외하고 새 경로만 cache 조회하는지 확인
    /// - 사전 조건: 각 lifecycle 집합에 기존 경로가 있고 새 경로만 cache hit인 상태
    /// - 기대 결과: 새 경로만 ready가 되고 generation은 호출되지 않음
    func testRequestThumbnailsFiltersDuplicateAndTrackedPaths() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-filtering", isDirectory: true)
        let readyPath = root.appendingPathComponent("ready.png").path
        let inFlightPath = root.appendingPathComponent("in-flight.png").path
        let failedPath = root.appendingPathComponent("failed.png").path
        let newPath = root.appendingPathComponent("new.png").path
        let cacheLookups = LockIsolated<[String]>([])
        let generatedURLs = LockIsolated<[URL]>([])
        let store = TestStore(
            initialState: EntryThumbnailState(
                requestsInFlight: [inFlightPath],
                readyPaths: [readyPath],
                failedPaths: [failedPath],
            ),
        ) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient(
                getThumbnail: { path in
                    cacheLookups.withValue { $0.append(path) }
                    return NSImage(size: NSSize(width: 1, height: 1))
                },
                saveThumbnail: { _, _ in },
                removeThumbnails: { _ in },
                clearCache: {},
            )
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient { url, _, _ in
                generatedURLs.withValue { $0.append(url) }
                return nil
            }
        }

        await store.send(.requestThumbnails(paths: [
            newPath,
            readyPath,
            newPath,
            inFlightPath,
            failedPath,
        ])) {
            $0.readyPaths.insert(newPath)
            $0.renderVersion = 1
        }

        XCTAssertEqual(cacheLookups.value, [newPath])
        XCTAssertTrue(generatedURLs.value.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: 한 요청의 신규 경로 수 제한
    /// icon projection을 지원하는 package 기술 계약으로 한 번에 최대 200개 경로만 처리한다.
    /// - 검증 내용: 201개 신규 경로 요청에서 앞의 200개만 cache 조회 및 ready 처리되는지 확인
    /// - 사전 조건: 모든 경로가 cache hit이고 lifecycle 집합은 비어 있음
    /// - 기대 결과: readyPaths와 cache 조회가 첫 200개로 제한됨
    func testRequestThumbnailsCapsNewPathsAtTwoHundred() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-cap", isDirectory: true)
        let paths = (0 ... 200).map { root.appendingPathComponent("thumbnail-\($0).png").path }
        let cacheLookups = LockIsolated<[String]>([])
        let generatedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: EntryThumbnailState()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient(
                getThumbnail: { path in
                    cacheLookups.withValue { $0.append(path) }
                    return NSImage(size: NSSize(width: 1, height: 1))
                },
                saveThumbnail: { _, _ in },
                removeThumbnails: { _ in },
                clearCache: {},
            )
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient { url, _, _ in
                generatedURLs.withValue { $0.append(url) }
                return nil
            }
        }

        await store.send(.requestThumbnails(paths: paths)) {
            $0.readyPaths = Set(paths.prefix(200))
            $0.renderVersion = 1
        }

        XCTAssertEqual(cacheLookups.value, Array(paths.prefix(200)))
        XCTAssertTrue(generatedURLs.value.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: cache hit 즉시 ready 처리
    /// icon projection을 지원하는 package 기술 계약으로 cached thumbnail은 generation 없이 사용한다.
    /// - 검증 내용: cache hit 경로가 readyPaths에 추가되고 generator가 호출되지 않는지 확인
    /// - 사전 조건: 요청 경로의 thumbnail이 cache에 존재함
    /// - 기대 결과: 경로가 즉시 ready가 되고 renderVersion이 증가함
    func testCacheHitBecomesReadyWithoutGeneration() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-cached.png").path
        let generatedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: EntryThumbnailState()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient(
                getThumbnail: { _ in NSImage(size: NSSize(width: 1, height: 1)) },
                saveThumbnail: { _, _ in },
                removeThumbnails: { _ in },
                clearCache: {},
            )
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient { url, _, _ in
                generatedURLs.withValue { $0.append(url) }
                return nil
            }
        }

        await store.send(.requestThumbnails(paths: [path])) {
            $0.readyPaths.insert(path)
            $0.renderVersion = 1
        }

        XCTAssertTrue(generatedURLs.value.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: 생성 성공 결과 cache 저장 및 ready 처리
    /// icon projection을 지원하는 package 기술 계약으로 생성된 thumbnail을 cache에 저장한다.
    /// - 검증 내용: generator 성공 후 saveThumbnail 호출과 ready lifecycle 전이를 확인
    /// - 사전 조건: 요청 경로가 cache miss이고 generator가 image를 반환함
    /// - 기대 결과: 경로가 cache에 저장되고 in-flight에서 ready로 이동함
    func testGeneratedThumbnailIsSavedAndBecomesReady() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-generated.png").path
        let generatedURLs = LockIsolated<[URL]>([])
        let savedPaths = LockIsolated<[String]>([])
        let store = TestStore(initialState: EntryThumbnailState()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient(
                getThumbnail: { _ in nil },
                saveThumbnail: { _, path in savedPaths.withValue { $0.append(path) } },
                removeThumbnails: { _ in },
                clearCache: {},
            )
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient { url, _, _ in
                generatedURLs.withValue { $0.append(url) }
                return NSImage(size: NSSize(width: 1, height: 1))
            }
        }

        await store.send(.requestThumbnails(paths: [path])) {
            $0.requestsInFlight.insert(path)
        }
        await store.receive(\.thumbnailsReady) {
            $0.requestsInFlight.remove(path)
            $0.readyPaths.insert(path)
            $0.renderVersion = 1
        }
        await store.finish()

        XCTAssertEqual(generatedURLs.value, [URL(fileURLWithPath: path)])
        XCTAssertEqual(savedPaths.value, [path])
    }

    /// EVM-002-set_entries_view_as_icon_grid: 생성 실패 결과 failed 처리
    /// icon projection을 지원하는 package 기술 계약으로 생성 실패 경로를 재요청 대상에서 제외한다.
    /// - 검증 내용: generator nil 결과가 failed lifecycle action으로 귀결되는지 확인
    /// - 사전 조건: 요청 경로가 cache miss이고 generator가 nil을 반환함
    /// - 기대 결과: 경로가 in-flight에서 failed로 이동함
    func testGenerationFailureBecomesFailed() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-failed.png").path
        let store = TestStore(initialState: EntryThumbnailState()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient(
                getThumbnail: { _ in nil },
                saveThumbnail: { _, _ in XCTFail("실패한 thumbnail은 cache에 저장하면 안 됨") },
                removeThumbnails: { _ in },
                clearCache: {},
            )
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient { _, _, _ in nil }
        }

        await store.send(.requestThumbnails(paths: [path])) {
            $0.requestsInFlight.insert(path)
        }
        await store.receive(\.thumbnailRequestFailed) {
            $0.requestsInFlight.remove(path)
            $0.failedPaths.insert(path)
            $0.renderVersion = 1
        }
        await store.finish()
    }

    // MARK: - EVM-002-set_entries_view_as_list_table

    /// EVM-002-set_entries_view_as_list_table: ready 통지의 lifecycle 상태 정리
    /// list projection을 지원하는 package 기술 계약으로 완료 경로의 추적 상태와 render version을 갱신한다.
    /// - 검증 내용: thumbnailsReady가 in-flight/failed를 제거하고 ready를 추가하는지 확인
    /// - 사전 조건: 같은 경로가 in-flight와 failed에 있고 renderVersion이 4임
    /// - 기대 결과: 경로가 ready에만 남고 renderVersion이 5가 됨
    func testThumbnailsReadyReconcilesLifecycleAndIncrementsRenderVersion() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-ready-transition.png").path
        let store = TestStore(
            initialState: EntryThumbnailState(
                requestsInFlight: [path],
                failedPaths: [path],
                renderVersion: 4,
            ),
        ) {
            EntryThumbnailFeature()
        }

        await store.send(.thumbnailsReady(paths: [path])) {
            $0.requestsInFlight.remove(path)
            $0.failedPaths.remove(path)
            $0.readyPaths.insert(path)
            $0.renderVersion = 5
        }
    }

    /// EVM-002-set_entries_view_as_list_table: 실패 통지의 lifecycle 상태 정리
    /// list projection을 지원하는 package 기술 계약으로 실패 경로와 render version을 갱신한다.
    /// - 검증 내용: thumbnailRequestFailed가 in-flight를 제거하고 failed를 추가하는지 확인
    /// - 사전 조건: 경로가 in-flight에 있고 renderVersion이 7임
    /// - 기대 결과: 경로가 failed에 남고 renderVersion이 8이 됨
    func testThumbnailRequestFailedReconcilesLifecycleAndIncrementsRenderVersion() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("EVM002-failed-transition.png").path
        let store = TestStore(
            initialState: EntryThumbnailState(
                requestsInFlight: [path],
                renderVersion: 7,
            ),
        ) {
            EntryThumbnailFeature()
        }

        await store.send(.thumbnailRequestFailed(paths: [path])) {
            $0.requestsInFlight.remove(path)
            $0.failedPaths.insert(path)
            $0.renderVersion = 8
        }
    }
}
