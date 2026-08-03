// FLOW-ID: fmw.handle_external_file_open_requests
import ComposableArchitecture
import Dependencies
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesExternalFileRouter
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import XCTest

/// AppRoot의 external-open ingress가 Router와 WindowManager를 거쳐 사용자에게 보이는 창 상태까지 도달하는지 검증한다.
/// URL parser, path normalizer, pending selection 소비의 세부 branch는 각각 FMW-003 package Specs가 소유한다.
@MainActor
final class HandleExternalFileOpenRequestsFlowTests: XCTestCase {
    // MARK: - FMW-003-open_external_folder

    /// FMW-003-open_external_folder: 유효한 folder deep link가 Router를 거쳐 새 focused window를 연다.
    /// - 검증 내용: AppRoot ingress → tracked Router request → openFolder delegate → tracked window opening의 실제 downstream
    /// chain
    /// - 사전 조건: real fixture를 격리 sandbox에 복사하고, 기존 warm window가 하나 있다.
    /// - 기대 결과: sandbox folder path를 표시하는 새 window가 열리고 focused window가 된다.
    func testFolderDeepLinkOpensAndFocusesSandboxFolderWindow() async throws {
        let sandbox = try FixtureSandbox.make()
        defer { sandbox.cleanup() }

        let originalWindowID = UUID(900)
        let openedWindowIDs = LockIsolated<[UUID]>([])
        let nativeOpenStarted = expectation(description: "Folder window native open starts")
        let nativeOpenGate = AsyncStream<Void>.makeStream()
        let store = Self.makeStore(
            initialState: Self.makeWarmState(windowID: originalWindowID),
            openedWindowIDs: openedWindowIDs,
            openWindow: { id in
                openedWindowIDs.withValue { $0.append(id) }
                nativeOpenStarted.fulfill()
                for await _ in nativeOpenGate.stream {
                    break
                }
            },
        )
        // store.exhaustivity = .off: flow는 child initialization action이 아니라 AppRoot-to-window observable outcome을 검증한다.
        store.exhaustivity = .off

        let deepLink = try Self.makeDeepLink(for: sandbox.folderURL, mode: .open)
        await store.send(.receiveExternalURL(deepLink))
        await store.receive(\.externalFileRouter.receiveTracked)
        await store.receive(\.externalFileRouter.normalizeCompleted)
        await store.receive(\.externalFileRouter.delegate.openFolder)
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [nativeOpenStarted], timeout: 1)
        await store.skipReceivedActions()
        nativeOpenGate.continuation.yield(())
        nativeOpenGate.continuation.finish()
        await store.receive(\.windowManager.trackedSingletonNativeOpenCompleted, UUID(0))
        await store.receive(\.windowManager.delegate.trackedSingletonCompleted, UUID(0))
        await store.finish()

        let focusedWindowID = try XCTUnwrap(store.state.windowManager.focusedWindowID)
        let focusedWindow = try XCTUnwrap(store.state.windowManager.windows[id: focusedWindowID])
        XCTAssertNotEqual(focusedWindowID, originalWindowID)
        XCTAssertEqual(
            focusedWindow.window.content.navigation.navigationState,
            .folder(sandbox.folderURL.path),
        )
        XCTAssertEqual(openedWindowIDs.value, [focusedWindowID])
        XCTAssertNil(store.state.activePendingExternalURL)
    }

    // MARK: - FMW-003-open_external_file

    /// FMW-003-open_external_file: file deep link가 parent folder와 pending selection을 새 focused window에 전달한다.
    /// - 검증 내용: AppRoot ingress → Router openParentFolder delegate → tracked window가 parent route와 reveal identity를 함께
    /// 보존한다.
    /// - 사전 조건: real fixture file을 격리 sandbox에 복사하고, 기존 warm window가 하나 있다.
    /// - 기대 결과: 새 focused window는 parent folder를 표시하고 copied file path를 pending selection으로 가진다.
    func testFileDeepLinkOpensParentFolderWithPendingSelection() async throws {
        let sandbox = try FixtureSandbox.make()
        defer { sandbox.cleanup() }

        let originalWindowID = UUID(901)
        let openedWindowIDs = LockIsolated<[UUID]>([])
        let nativeOpenStarted = expectation(description: "File parent window native open starts")
        let nativeOpenGate = AsyncStream<Void>.makeStream()
        let store = Self.makeStore(
            initialState: Self.makeWarmState(windowID: originalWindowID),
            openedWindowIDs: openedWindowIDs,
            openWindow: { id in
                openedWindowIDs.withValue { $0.append(id) }
                nativeOpenStarted.fulfill()
                for await _ in nativeOpenGate.stream {
                    break
                }
            },
        )
        // store.exhaustivity = .off: loading/selection 소비의 package-local action 대신 parent-window handoff만 검증한다.
        store.exhaustivity = .off

        let deepLink = try Self.makeDeepLink(for: sandbox.fileURL, mode: .reveal)
        await store.send(.receiveExternalURL(deepLink))
        await store.receive(\.externalFileRouter.receiveTracked)
        await store.receive(\.externalFileRouter.normalizeCompleted)
        await store.receive(\.externalFileRouter.delegate.openParentFolder)
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [nativeOpenStarted], timeout: 1)
        await store.skipReceivedActions()
        nativeOpenGate.continuation.yield(())
        nativeOpenGate.continuation.finish()
        await store.receive(\.windowManager.trackedSingletonNativeOpenCompleted, UUID(0))
        await store.receive(\.windowManager.delegate.trackedSingletonCompleted, UUID(0))
        await store.finish()

        let focusedWindowID = try XCTUnwrap(store.state.windowManager.focusedWindowID)
        let focusedWindow = try XCTUnwrap(store.state.windowManager.windows[id: focusedWindowID])
        XCTAssertNotEqual(focusedWindowID, originalWindowID)
        XCTAssertEqual(
            focusedWindow.window.content.navigation.navigationState,
            .folder(sandbox.folderURL.path),
        )
        XCTAssertEqual(focusedWindow.window.content.pendingSelectEntryID, sandbox.fileURL.path)
        XCTAssertEqual(openedWindowIDs.value, [focusedWindowID])
        XCTAssertNil(store.state.activePendingExternalURL)
    }

    // MARK: - FMW-003-invalid_external_path

    /// FMW-003-invalid_external_path: 존재하지 않는 file URL은 parent-visible error만 만들고 창을 열지 않는다.
    /// - 검증 내용: Router invalid-path terminal이 AppRoot alert boundary까지 도달하며 새 window route가 발행되지 않는다.
    /// - 사전 조건: 기존 warm window 하나와 sandbox 밖의 존재하지 않는 file URL이 있다.
    /// - 기대 결과: alert가 한 번 기록되고 focused/original window 외 새 window는 없다.
    func testNonexistentFileDeepLinkShowsErrorWithoutOpeningWindow() async throws {
        let originalWindowID = UUID(902)
        let openedWindowIDs = LockIsolated<[UUID]>([])
        let alerts = LockIsolated<[String]>([])
        let store = Self.makeStore(
            initialState: Self.makeWarmState(windowID: originalWindowID),
            openedWindowIDs: openedWindowIDs,
            openWindow: { id in openedWindowIDs.withValue { $0.append(id) } },
            alerts: alerts,
        )
        // store.exhaustivity = .off: alert completion과 tracked terminal의 내부 순서보다 no-window failure outcome을 검증한다.
        store.exhaustivity = .off

        let missingURL = URL(fileURLWithPath: "/tmp/voyager-flow-missing-\(UUID().uuidString)")
        let deepLink = try Self.makeDeepLink(for: missingURL, mode: .open)
        await store.send(.receiveExternalURL(deepLink))
        await store.receive(\.externalFileRouter.receiveTracked)
        await store.receive(\.externalFileRouter.failed)
        await store.receive(\.externalFileRouter.delegate.showInvalidPathError)
        await store.receive(\.externalFileRouter.singletonRequestCompleted, UUID(0))
        await store.finish()

        XCTAssertEqual(Array(store.state.windowManager.windows.ids), [originalWindowID])
        XCTAssertEqual(store.state.windowManager.focusedWindowID, originalWindowID)
        XCTAssertTrue(openedWindowIDs.value.isEmpty)
        XCTAssertEqual(alerts.value.count, 1)
        XCTAssertNil(store.state.activePendingExternalURL)
    }

    // MARK: - File-local helpers

    private static func makeWarmState(windowID: UUID) -> AppRootState {
        var state = AppRootState()
        state.lifecycle.accessGatePhase = .granted
        state.windowManager.windows = [
            .init(id: windowID, window: .makeInitial(path: "/existing-window")),
        ]
        state.windowManager.focusedWindowID = windowID
        state.windowManager.lastUsedWindowIDs = [windowID]
        return state
    }

    private static func makeStore(
        initialState: AppRootState,
        openedWindowIDs _: LockIsolated<[UUID]>,
        openWindow: @escaping @Sendable (UUID) async -> Void,
        alerts: LockIsolated<[String]> = .init([]),
    ) -> TestStore<AppRootState, AppRootAction> {
        TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = openWindow
            $0.pathProbeClient.probeExistence = { path in
                var isDirectory = ObjCBool(false)
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                return .init(exists: exists, isDirectory: isDirectory.boolValue)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, message in
                alerts.withValue { $0.append(message) }
            }
        }
    }

    private static func makeDeepLink(for fileURL: URL, mode: DeepLinkMode) throws -> URL {
        var components = URLComponents()
        components.scheme = "voyager"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "url", value: fileURL.absoluteString),
            URLQueryItem(name: "mode", value: mode == .reveal ? "reveal" : "open"),
        ]
        return try XCTUnwrap(components.url)
    }
}

private struct FixtureSandbox {
    let rootURL: URL
    let folderURL: URL
    let fileURL: URL

    static func make() throws -> Self {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HandleExternalFileOpenRequestsFlowTests-\(UUID().uuidString)")
        let folderURL = rootURL.appendingPathComponent("fixture-folder")
        let fileURL = folderURL.appendingPathComponent("98.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureURL, to: fileURL)
        return Self(rootURL: rootURL, folderURL: folderURL, fileURL: fileURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static var fixtureURL: URL {
        var workspaceURL = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 7 {
            workspaceURL.deleteLastPathComponent()
        }
        return workspaceURL.appendingPathComponent("fixtures/fixtures/texts/plain/98.txt")
    }
}
