import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SelectionGate {
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<String> = []

    func wait(_ key: String) async {
        started.insert(key)
        await withCheckedContinuation { waiters[key] = $0 }
    }

    func resume(_ key: String) {
        waiters.removeValue(forKey: key)?.resume()
    }

    func isStarted(_ key: String) -> Bool {
        started.contains(key)
    }
}

// MARK: - EOP-001-execute_entry

@MainActor
final class EOP001ExecuteEntryTests: XCTestCase {
    // MARK: - EOP-001-open_with_discovery

    /// EOP-001-open_with_discovery: 동일 타입의 단일·동시 조회는 대표 URL 하나만 탐색한다.
    /// - 검증 내용: 같은 UTType 두 경로의 순차 조회와 동시에 시작한 두 조회가 각각 underlying discovery 1회인지 확인한다.
    /// - 사전 조건: applicationsForType gate와 두 개의 txt 파일이 있다.
    /// - 기대 결과: discovery 호출 횟수 1회, 두 호출 완료 후 in-flight 상태가 비어 있다.
    func testOpenWithDiscoveryDeduplicatesSameTypeAndInFlightRequests() async {
        let gate = AsyncGate()
        let calls = LockIsolated(0)
        let fileA = EntryModelFixtures.makeFileEntry(id: "/tmp/a.txt", name: "a.txt")
        let fileB = EntryModelFixtures.makeFileEntry(id: "/tmp/b.txt", name: "b.txt")
        let app = ApplicationInfo(id: "preview", name: "Preview", bundleID: "preview")
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { _, _ in
                calls.withValue { $0 += 1 }
                await gate.wait()
                return [app]
            }
            $0.entryOpenClient.defaultApplication = { _ in app }
        }
        store.exhaustivity = .off

        await store.send(.openWith(.loadApplicationsForFile(file: fileA)))
        await store.send(.openWith(.loadApplicationsForFile(file: fileB)))
        XCTAssertEqual(calls.value, 1)
        await gate.resume()
        await store.skipReceivedActions()
        await store.finish()
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    /// EOP-001-open_with_discovery: 기본 앱 변경 reload의 최신 completion만 타입 앱 상태를 갱신한다.
    /// - 검증 내용: 초기 조회와 default mutation reload를 역순 완료시키고 최신 앱/default 표시와 loading 해제를 확인한다.
    /// - 사전 조건: 동일 타입에 old/new discovery gate와 old/new default 앱이 있다.
    /// - 기대 결과: old completion은 무시되고 new 결과가 저장되며 in-flight 상태가 비워진다.
    func testOpenWithDefaultMutationReloadIgnoresOlderSingleLoadCompletion() async {
        let gate = SelectionGate()
        let file = EntryModelFixtures.makeFileEntry(id: "/tmp/reload.txt", name: "reload.txt")
        let oldApp = ApplicationInfo(id: "old", name: "Old", bundleID: "old")
        let newApp = ApplicationInfo(id: "new", name: "New", bundleID: "new")
        let calls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { _, _ in
                let call = calls.withValue { value in
                    value += 1
                    return value
                }
                await gate.wait(call == 1 ? "old" : "new")
                return [call == 1 ? oldApp : newApp]
            }
            $0.entryOpenClient.defaultApplication = { _ in
                calls.value == 1 ? oldApp : newApp
            }
        }
        store.exhaustivity = .off

        await store.send(.openWith(.loadApplicationsForFile(file: file)))
        while await !gate.isStarted("old") {
            await Task.yield()
        }
        await store.send(.lifecycle(.operationFinished(file.fullPath, .setDefaultApp("new"), .success(()))))
        while await !gate.isStarted("new") {
            await Task.yield()
        }

        await gate.resume("new")
        await Task.yield()
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.contains("public.plain-text"))
        await gate.resume("old")
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.applicationsForTypes["public.plain-text"]?.compactMap(\.bundleID), ["new"])
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    /// EOP-001-open_with_discovery: 다중 선택은 unique UTType 대표 URL만 조회하고 교집합을 재계산한다.
    /// - 검증 내용: 두 txt와 한 jpg 선택에서 discovery/default 조회가 타입별 1회이고, 캐시된 타입 조합 전환이 이전 교집합을 남기지 않는지 확인한다.
    /// - 사전 조건: 타입별 앱 목록과 default 앱 mock, 세 파일 선택이 있다.
    /// - 기대 결과: 타입 조회 2회, default 조회 2회, 두 번째 결과는 현재 선택의 교집합이다.
    func testOpenWithCommonApplicationsUsesUniqueTypesAndRecomputesCachedSelection() async {
        let txt = EntryModelFixtures.makeFileEntry(id: "/tmp/a.txt", name: "a.txt")
        let txt2 = EntryModelFixtures.makeFileEntry(id: "/tmp/b.txt", name: "b.txt")
        let jpg = EntryModelFixtures.makeFileEntry(id: "/tmp/c.jpg", name: "c.jpg", fileExtension: "jpg")
        let shared = ApplicationInfo(id: "shared", name: "Shared", bundleID: "shared")
        let textOnly = ApplicationInfo(id: "text", name: "Text", bundleID: "text")
        let imageOnly = ApplicationInfo(id: "image", name: "Image", bundleID: "image")
        let typeCalls = LockIsolated(0)
        let defaultCalls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { type, _ in
                typeCalls.withValue { $0 += 1 }
                return type.identifier == "public.plain-text" ? [shared, textOnly] : [shared, imageOnly]
            }
            $0.entryOpenClient.defaultApplication = { type in
                defaultCalls.withValue { $0 += 1 }
                return type.identifier == "public.plain-text" ? textOnly : imageOnly
            }
        }
        store.exhaustivity = .off

        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [txt, txt2, jpg])))
        await store.finish()
        await store.skipReceivedActions()
        XCTAssertEqual(typeCalls.value, 2)
        XCTAssertEqual(defaultCalls.value, 2)

        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [txt, txt2])))
        XCTAssertEqual(
            Set(store.state.commonApplicationsForSelectedFiles.compactMap(\.bundleID)),
            ["shared", "text"],
        )
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    /// EOP-001-open_with_discovery: 확장자 없는 다중 선택은 data 타입으로 공통 앱을 조회한다.
    /// 확장자가 없는 파일만 선택해도 Open With loading이 완료되는 fallback 경로를 검증한다.
    /// - 검증 내용: common discovery가 `UTType.data`로 앱 목록을 조회하고 결과를 상태에 반영한다.
    /// - 사전 조건: 확장자 없는 파일과 data 타입을 지원하는 앱 mock이 있다.
    /// - 기대 결과: data 타입 조회가 한 번 실행되고 공통 앱 결과와 in-flight 상태가 수렴한다.
    func testOpenWithCommonApplicationsUsesDataFallbackForExtensionlessFiles() async {
        let file = EntryModelFixtures.makeFileEntry(
            id: "/tmp/README",
            name: "README",
            fileExtension: "",
        )
        let app = ApplicationInfo(id: "text-edit", name: "TextEdit", bundleID: "text-edit")
        let requestedTypeIDs = LockIsolated<[String]>([])
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { type, _ in
                requestedTypeIDs.withValue { $0.append(type.identifier) }
                return [app]
            }
            $0.entryOpenClient.defaultApplication = { _ in nil }
        }
        // store.exhaustivity = .off: common discovery의 내부 completion보다 최종 fallback 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [file])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(requestedTypeIDs.value, [UTType.data.identifier])
        XCTAssertEqual(store.state.commonApplicationsForSelectedFiles.compactMap(\.bundleID), ["text-edit"])
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    /// EOP-001-open_with_discovery: 기본 앱 변경은 진행 중인 공통 조회의 이전 snapshot을 무효화한다.
    /// - 검증 내용: default mutation reload를 먼저 완료한 뒤 이전 common completion을 완료한다.
    /// - 사전 조건: 같은 txt 타입의 common 조회와 default mutation reload가 겹친다.
    /// - 기대 결과: 이전 common 결과가 최신 타입 앱 cache를 덮지 않고 공통 목록도 비워진다.
    func testOpenWithDefaultMutationInvalidatesOlderCommonCompletion() async {
        let gate = SelectionGate()
        let file = EntryModelFixtures.makeFileEntry(id: "/tmp/shared.txt", name: "shared.txt")
        let oldApp = ApplicationInfo(id: "old", name: "Old", bundleID: "old")
        let newApp = ApplicationInfo(id: "new", name: "New", bundleID: "new")
        let calls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { _, _ in
                let call = calls.withValue { value in
                    value += 1
                    return value
                }
                await gate.wait(call == 1 ? "common" : "reload")
                return [call == 1 ? oldApp : newApp]
            }
            $0.entryOpenClient.defaultApplication = { _ in newApp }
        }
        store.exhaustivity = .off

        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [file])))
        while await !gate.isStarted("common") {
            await Task.yield()
        }
        await store.send(.lifecycle(.operationFinished(file.fullPath, .setDefaultApp("new"), .success(()))))
        while await !gate.isStarted("reload") {
            await Task.yield()
        }

        await gate.resume("reload")
        await Task.yield()
        await gate.resume("common")
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.applicationsForTypes["public.plain-text"]?.compactMap(\.bundleID), ["new"])
        XCTAssertTrue(store.state.commonApplicationsForSelectedFiles.isEmpty)
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    /// EOP-001-open_with_discovery: 최신 다중 선택 결과만 공통 앱 상태를 갱신한다.
    /// - 검증 내용: 이전 선택과 최신 선택의 discovery를 gate로 역순 완료시켜 오래된 completion이 무시되는지 확인한다.
    /// - 사전 조건: txt와 jpg를 포함한 두 선택, 선택별 앱 목록, 두 discovery gate가 있다.
    /// - 기대 결과: 최신 선택 앱만 남고 모든 type in-flight 상태가 해제된다.
    func testOpenWithOverlappingCommonSelectionsIgnoreOlderCompletion() async {
        let gate = SelectionGate()
        let txt = EntryModelFixtures.makeFileEntry(id: "/tmp/a.txt", name: "a.txt")
        let jpg = EntryModelFixtures.makeFileEntry(id: "/tmp/b.jpg", name: "b.jpg", fileExtension: "jpg")
        let oldApp = ApplicationInfo(id: "old", name: "Old", bundleID: "old")
        let newApp = ApplicationInfo(id: "new", name: "New", bundleID: "new")
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { type, _ in
                if type.identifier == "public.plain-text" {
                    await gate.wait("old")
                    return [oldApp]
                }
                await gate.wait("new")
                return [newApp]
            }
            $0.entryOpenClient.defaultApplication = { _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [txt])))
        while await !gate.isStarted("old") {
            await Task.yield()
        }
        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [jpg])))
        while await !gate.isStarted("new") {
            await Task.yield()
        }

        await gate.resume("new")
        await Task.yield()
        await gate.resume("old")
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.commonApplicationsForSelectedFiles.compactMap(\.bundleID), ["new"])
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    /// EOP-001-open_with_discovery: 같은 타입을 공유하는 최신 선택이 이전 completion에 의해 loading 해제되지 않는다.
    /// - 검증 내용: 동일 타입 두 common request를 역순 완료시키고 최신 request가 pending인 중간 상태를 확인한다.
    /// - 사전 조건: 같은 txt 타입 선택 두 개와 old/new discovery gate가 있다.
    /// - 기대 결과: old completion 중간에도 in-flight가 유지되고 최종 최신 앱만 남는다.
    func testOpenWithOverlappingCommonSelectionsKeepSharedTypeInFlightForLatestGeneration() async {
        let gate = SelectionGate()
        let first = EntryModelFixtures.makeFileEntry(id: "/tmp/first.txt", name: "first.txt")
        let second = EntryModelFixtures.makeFileEntry(id: "/tmp/second.txt", name: "second.txt")
        let oldApp = ApplicationInfo(id: "old", name: "Old", bundleID: "old")
        let newApp = ApplicationInfo(id: "new", name: "New", bundleID: "new")
        let calls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.applicationsForType = { _, _ in
                let call = calls.withValue { value in
                    value += 1
                    return value
                }
                await gate.wait(call == 1 ? "old" : "new")
                return [call == 1 ? oldApp : newApp]
            }
            $0.entryOpenClient.defaultApplication = { _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [first])))
        while await !gate.isStarted("old") {
            await Task.yield()
        }
        await store.send(.openWith(.loadCommonApplicationsForFiles(files: [second])))
        while await !gate.isStarted("new") {
            await Task.yield()
        }

        await gate.resume("old")
        await Task.yield()
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.contains("public.plain-text"))
        await gate.resume("new")
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.commonApplicationsForSelectedFiles.compactMap(\.bundleID), ["new"])
        XCTAssertTrue(store.state.openWithInFlightTypeIDs.isEmpty)
    }

    // MARK: - EOP-001-open_entry_with_default_app

    /// EOP-001-open_entry_with_default_app: 기본 앱으로 엔트리 열기
    /// - 검증 내용: 기본 앱 열기 action이 선택된 파일 URL과 대상 앱으로 workspace open 호출을 수행하는지 확인합니다.
    /// - 사전 조건: WorkspaceClient mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 URL로 workspaceClient.openURLsWithApplication을 호출
    func testOpenEntryWithDefaultApp_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let fileURL = sandbox.fileURL
        let appURL = URL(fileURLWithPath: "/Applications/TextEdit.app")
        let openURLsWithApplicationCalls = CallRecorder<([URL], URL)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.workspaceClient.urlForApplicationToOpen = { _ in appURL }
            $0.workspaceClient.openURLsWithApplication = { urls, app, _, _ in
                openURLsWithApplicationCalls.record((urls, app))
            }
            $0.entryOpenClient.trashDirectoryPath = { nil }
        }

        await store.send(.open(.openFiles(paths: [filePath])))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        // 비-undo open 명령도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

        XCTAssertEqual(openURLsWithApplicationCalls.recorded.count, 1)
        XCTAssertEqual(openURLsWithApplicationCalls.recorded[0].0, [fileURL])
        XCTAssertEqual(openURLsWithApplicationCalls.recorded[0].1, appURL)
    }

    /// EOP-001-open_entry_with_default_app: 빈 경로 목록 전달 시 아무 동작도 수행하지 않음
    /// - 검증 내용: 빈 경로 입력에서 기본 앱 열기 의존성이 호출되지 않는지 확인합니다.
    /// - 사전 조건: 초기 상태, 의존성 mock 설정
    /// - 기대 결과: workspaceClient 호출 없음
    func testOpenEntryWithDefaultApp_emptyPaths_noOp() async {
        let openCalls = CallRecorder<(URL, OpenKind)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.open = { url, kind in
                openCalls.record((url, kind))
            }
        }

        await store.send(.open(.openFiles(paths: [])))

        XCTAssertTrue(openCalls.recorded.isEmpty)
    }

    // MARK: - EOP-001-open_entry_with_selected_app

    /// EOP-001-open_entry_with_selected_app: 선택한 앱으로 엔트리 열기
    /// - 검증 내용: 선택 앱 열기 action이 파일 URL과 bundle ID를 EntryOpenClient에 전달하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.open mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 URL과 bundleID로 EntryOpenClient.open을 호출
    func testOpenEntryWithSelectedApp_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let fileURL = sandbox.fileURL
        let bundleID = "com.apple.Preview"
        let openCalls = CallRecorder<(URL, OpenKind)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.open = { url, kind in
                openCalls.record((url, kind))
            }
            $0.entryOpenClient.trashDirectoryPath = { nil }
        }

        await store.send(.openWith(.openFileWithAppBundleID(
            filePath: filePath,
            bundleID: bundleID,
            url: fileURL,
        )))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }
        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        // 비-undo open-with 명령도 실제 OperationKind를 보존한 terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

        XCTAssertEqual(openCalls.recorded.count, 1)
        XCTAssertEqual(openCalls.recorded[0].0, fileURL)
        XCTAssertEqual(openCalls.recorded[0].1, .bundleID(bundleID))
    }

    /// EOP-001-open_entry_with_selected_app: 다중 선택 앱 열기는 완료 순서와 무관한 단일 aggregate terminal을 낸다.
    /// 두 파일의 성공·실패가 선택 순서와 반대로 완료되어도 accepted command 단위 결과가 하나로 수렴하는지 검증한다.
    /// - 검증 내용: 파일별 lifecycle은 유지하고 command metadata와 성공·실패 수를 담은 terminal을 정확히 한 번 기록한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 sandbox 파일과 원본 fixture를 선택하고 두 번째 실패를 먼저 완료한다.
    /// - 기대 결과: attempted 2, succeeded 1, failed 1, cancelled 0이며 targets가 비어 있는 terminal 한 건이 accepted metadata를 보존한다.
    func testOpenWithSelectedAppAggregatesMixedResultsWhenSecondFileFinishesFirst() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let files = [sandbox.fileURL, sandbox.originalFixture].map {
            EntryModelFixtures.makeFileEntry(id: $0.path, name: $0.lastPathComponent)
        }
        let bundleID = "com.apple.Preview"
        let commandID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000691"))
        let metadata = EntryCommandMetadata(
            id: commandID,
            interaction: .openEntryWithSelectedApp,
            source: .contextMenu,
        )
        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: files,
            currentPath: sandbox.root.path,
            bundleID: bundleID,
            metadata: metadata,
            failingPath: files[1].fullPath,
            completionOrder: [files[1].fullPath, files[0].fullPath],
        )

        XCTAssertEqual(Set(evidence.openStartedPaths), Set(files.map(\.fullPath)))
        XCTAssertEqual(Set(evidence.openFinishedPaths), Set(files.map(\.fullPath)))
        XCTAssertEqual(evidence.terminals.count, 1, "다중 Open With command는 terminal을 정확히 한 번 기록해야 한다.")
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.id, commandID)
        XCTAssertEqual(terminal.operationKind, .openWithApp(bundleID))
        XCTAssertTrue(terminal.targets.isEmpty)
        XCTAssertEqual(terminal.attemptedCount, 2)
        XCTAssertEqual(terminal.succeededCount, 1)
        XCTAssertEqual(terminal.failedCount, 1)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }

    /// EOP-001-open_entry_with_selected_app: 기본 앱 지정 다중 열기도 파일별 completion과 reload를 보존한다.
    /// selected app command를 기본 앱으로 지정할 때 기존 set-default lifecycle과 앱 목록 reload가 사라지지 않는지 검증한다.
    /// - 검증 내용: 두 파일의 setDefaultApp 호출·operationFinished·applicationsForType reload와 단일 open terminal을 함께 기록한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 sandbox 파일과 원본 fixture, 성공하는 default/open client가 있다.
    /// - 기대 결과: 파일별 default completion과 reload가 각각 두 번 유지되고 open aggregate는 attempted 2, succeeded 2인 한 건이다.
    func testOpenWithSelectedAppSetAsDefaultPreservesCompletionAndReload() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let files = [sandbox.fileURL, sandbox.originalFixture].map {
            EntryModelFixtures.makeFileEntry(id: $0.path, name: $0.lastPathComponent)
        }
        let bundleID = "com.apple.Preview"
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000692")),
            interaction: .openEntryWithSelectedApp,
            source: .contextMenu,
        )
        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: files,
            currentPath: sandbox.root.path,
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
        )

        XCTAssertEqual(evidence.setDefaultCallCount, 2)
        XCTAssertEqual(Set(evidence.defaultFinishedPaths), Set(files.map(\.fullPath)))
        XCTAssertEqual(evidence.reloadCallCount, 2)
        XCTAssertEqual(evidence.openCallCount, 2)
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.operationKind, .openWithApp(bundleID))
        XCTAssertTrue(terminal.targets.isEmpty)
        XCTAssertEqual(terminal.attemptedCount, 2)
        XCTAssertEqual(terminal.succeededCount, 2)
        XCTAssertEqual(terminal.failedCount, 0)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }

    /// EOP-001-open_entry_with_selected_app: 단일 Always Open With는 open 결과만 집계한 terminal 한 건을 낸다.
    /// - 검증 내용: 기본 앱 설정 성공과 앱 목록 reload를 보존하면서 open 실패만 command terminal에 집계한다.
    /// - 사전 조건: 고정 metadata, 성공하는 set-default와 실패하는 selected-app open이 있다.
    /// - 기대 결과: terminal 한 건이 attempted 1, succeeded 0, failed 1, cancelled 0과 원본 metadata를 보존한다.
    func testSingleOpenWithSetAsDefaultEmitsOneOpenAggregateTerminal() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let file = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
        )
        let bundleID = "com.apple.Preview"
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000693")),
            interaction: .openEntryWithSelectedApp,
            source: .contextMenu,
        )

        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: [file],
            currentPath: sandbox.root.path,
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
            failingPath: file.fullPath,
        )

        XCTAssertEqual(evidence.setDefaultCallCount, 1)
        XCTAssertEqual(evidence.defaultFinishedPaths, [file.fullPath])
        XCTAssertEqual(evidence.reloadCallCount, 1)
        XCTAssertEqual(evidence.openCallCount, 1)
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.operationKind, .openWithApp(bundleID))
        XCTAssertEqual(terminal.attemptedCount, 1)
        XCTAssertEqual(terminal.succeededCount, 0)
        XCTAssertEqual(terminal.failedCount, 1)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }
}

extension EOP001ExecuteEntryTests {
    /// EOP-001-open_entry_with_selected_app: 기본 앱 설정 실패 후 열기 성공도 파일 결과는 실패로 남는다.
    /// Always Open With의 두 단계 중 기본 앱 설정 실패가 성공한 open에 의해 지워지지 않는지 검증한다.
    /// - 검증 내용: set-default와 open lifecycle을 각각 한 번 실행하고 파일 상태와 command aggregate에 첫 실패를 보존한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` sandbox, 실패하는 set-default와 성공하는 open client가 있다.
    /// - 기대 결과: attempted 1, succeeded 0, failed 1이며 최종 파일 오류가 set-default 오류다.
    func testSingleAlwaysOpenWithRetainsSetDefaultFailureWhenOpenSucceeds() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let file = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
        )
        let bundleID = "com.apple.Preview"
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000702")

        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: [file],
            currentPath: sandbox.root.path,
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
            failingDefaultTypeIDs: [UTType.plainText.identifier],
        )

        XCTAssertEqual(evidence.setDefaultCallCount, 1)
        XCTAssertEqual(evidence.defaultFailedPaths, [file.fullPath])
        XCTAssertEqual(evidence.openCallCount, 1)
        XCTAssertEqual(evidence.openFinishedPaths, [file.fullPath])
        XCTAssertEqual(evidence.lastErrors[file.fullPath], .system(message: "set default denied"))
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.attemptedCount, 1)
        XCTAssertEqual(terminal.succeededCount, 0)
        XCTAssertEqual(terminal.failedCount, 1)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }

    /// EOP-001-open_entry_with_selected_app: 기본 앱 설정 취소는 파일 열기 전에 명령을 종료한다.
    /// 사용자 취소가 후속 앱 열기와 추가 lifecycle을 발생시키지 않는지 검증한다.
    /// - 검증 내용: set-default 취소 뒤 open 호출 없이 cancelled terminal 한 건만 기록한다.
    /// - 사전 조건: 단일 텍스트 파일과 취소를 반환하는 set-default client가 있다.
    /// - 기대 결과: attempted 1, cancelled 1이며 open 호출과 open lifecycle이 없다.
    func testSingleAlwaysOpenWithSetDefaultCancellationStopsBeforeOpen() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let file = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
        )
        let bundleID = "com.apple.Preview"
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000704")

        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: [file],
            currentPath: sandbox.root.path,
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
            cancelledDefaultTypeIDs: [UTType.plainText.identifier],
        )

        XCTAssertEqual(evidence.setDefaultCallCount, 1)
        XCTAssertEqual(evidence.defaultFailedPaths, [file.fullPath])
        XCTAssertEqual(evidence.openCallCount, 0)
        XCTAssertTrue(evidence.openStartedPaths.isEmpty)
        XCTAssertTrue(evidence.openFinishedPaths.isEmpty)
        XCTAssertEqual(evidence.lastErrors[file.fullPath], .cancelled)
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.attemptedCount, 1)
        XCTAssertEqual(terminal.succeededCount, 0)
        XCTAssertEqual(terminal.failedCount, 0)
        XCTAssertEqual(terminal.cancelledCount, 1)
    }

    /// EOP-001-open_entry_with_selected_app: 두 파일의 역순 open 완료에도 기본 앱 설정 실패 집계는 결정적이다.
    /// 서로 다른 타입의 Always Open With가 선택 역순으로 완료되어도 파일별 결과와 terminal이 한 번만 수렴하는지 검증한다.
    /// - 검증 내용: 한 파일의 set-default만 실패시키고 두 open을 역순 완료해 최종 오류와 aggregate count를 확인한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`, `fixtures/fixtures/images/jpeg/resize.jpg` sandbox와 gated open
    /// client가 있다.
    /// - 기대 결과: attempted 2, succeeded 1, failed 1인 terminal 한 건과 실패 파일의 set-default 오류가 남는다.
    func testAlwaysOpenWithMixedSetDefaultResultsRemainDeterministicWhenOpenCompletesInReverse() async throws {
        let textSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { textSandbox.cleanup() }
        let imageSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/images/jpeg/resize.jpg")
        defer { imageSandbox.cleanup() }
        let files = [textSandbox.fileURL, imageSandbox.fileURL].map {
            EntryModelFixtures.makeFileEntry(
                id: $0.path,
                name: $0.lastPathComponent,
                fileExtension: $0.pathExtension,
            )
        }
        let bundleID = "com.apple.Preview"
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000703")

        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: files,
            currentPath: textSandbox.root.path,
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
            failingDefaultTypeIDs: [UTType.plainText.identifier],
            completionOrder: [files[1].fullPath, files[0].fullPath],
        )

        XCTAssertEqual(evidence.setDefaultCallCount, 2)
        XCTAssertEqual(evidence.defaultFailedPaths, [files[0].fullPath])
        XCTAssertEqual(Set(evidence.openFinishedPaths), Set(files.map(\.fullPath)))
        XCTAssertEqual(evidence.lastErrors[files[0].fullPath], .system(message: "set default denied"))
        XCTAssertNil(evidence.lastErrors[files[1].fullPath])
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.attemptedCount, 2)
        XCTAssertEqual(terminal.succeededCount, 1)
        XCTAssertEqual(terminal.failedCount, 1)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }
}

extension EOP001ExecuteEntryTests {
    /// EOP-001-open_entry_with_selected_app: Other picker 다중 선택은 성공·실패를 terminal 한 건으로 집계한다.
    /// - 검증 내용: picker 선택 후 routed command metadata가 batch action과 단일 aggregate terminal까지 전파되는지 확인한다.
    /// - 사전 조건: 두 일반 파일, Other picker selection, 한 파일만 실패하는 open client가 있다.
    /// - 기대 결과: open 2회와 attempted 2, succeeded 1, failed 1인 terminal 한 건이 원본 metadata를 보존한다.
    func testOtherPickerMultipleFilesEmitsOneMixedResultTerminal() async throws {
        let files = ["/tmp/other-a.txt", "/tmp/other-b.txt"].map {
            EntryModelFixtures.makeFileEntry(id: $0, name: URL(fileURLWithPath: $0).lastPathComponent)
        }
        let bundleID = "com.apple.Preview"
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000698")
        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: files,
            currentPath: "/tmp",
            bundleID: bundleID,
            metadata: metadata,
            failingPath: files[1].fullPath,
            usesOtherPicker: true,
        )

        XCTAssertEqual(evidence.batchActionCount, 1)
        XCTAssertEqual(evidence.openCallCount, files.count)
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.operationKind, .openWithApp(bundleID))
        XCTAssertEqual(terminal.attemptedCount, files.count)
        XCTAssertEqual(terminal.succeededCount, 1)
        XCTAssertEqual(terminal.failedCount, 1)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }

    /// EOP-001-open_entry_with_selected_app: Other picker 혼합 Trash 선택은 mutation 전에 명령 전체를 취소한다.
    /// - 검증 내용: picker selection이 batch Trash preflight를 공유하고 파일별 set-default/open으로 분기하지 않는지 확인한다.
    /// - 사전 조건: 일반 파일과 휴지통 파일, set-default가 선택된 Other picker selection이 있다.
    /// - 기대 결과: mutation/open 호출 없이 attempted 2, cancelled 2인 terminal 한 건이 원본 metadata를 보존한다.
    func testOtherPickerMixedTrashSelectionCancelsWholeCommand() async throws {
        let trashPath = "/tmp/.Trash"
        let files = ["/tmp/normal.txt", "\(trashPath)/trashed.txt"].map {
            EntryModelFixtures.makeFileEntry(id: $0, name: URL(fileURLWithPath: $0).lastPathComponent)
        }
        let bundleID = "com.apple.Preview"
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000699")
        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: files,
            currentPath: "/tmp",
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
            usesOtherPicker: true,
            trashPath: trashPath,
        )

        XCTAssertEqual(evidence.batchActionCount, 1)
        XCTAssertEqual(evidence.setDefaultCallCount + evidence.openCallCount, 0)
        try assertCancelledTerminal(
            evidence.terminals.map { .lifecycle(.entryActionCompleted($0)) },
            metadata: metadata,
            operationKind: .openWithApp(bundleID),
            attemptedCount: files.count,
        )
    }

    /// EOP-001-open_entry_with_selected_app: Other picker 단일 Always Open With 실패는 terminal 한 건을 낸다.
    /// - 검증 내용: picker selection의 set-default와 open 실패가 파일별 terminal로 분리되지 않는지 확인한다.
    /// - 사전 조건: 단일 일반 파일, set-default가 선택된 Other picker, 실패하는 open client가 있다.
    /// - 기대 결과: set-default/open 각 1회와 attempted 1, failed 1인 terminal 한 건이 원본 metadata를 보존한다.
    func testOtherPickerSingleSetDefaultOpenFailureEmitsOneTerminal() async throws {
        let file = EntryModelFixtures.makeFileEntry(id: "/tmp/other-single.txt", name: "other-single.txt")
        let bundleID = "com.apple.Preview"
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000700")
        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: [file],
            currentPath: "/tmp",
            bundleID: bundleID,
            metadata: metadata,
            shouldSetAsDefault: true,
            failingPath: file.fullPath,
            usesOtherPicker: true,
        )

        XCTAssertEqual(evidence.batchActionCount, 1)
        XCTAssertEqual(evidence.setDefaultCallCount, 1)
        XCTAssertEqual(evidence.openCallCount, 1)
        XCTAssertEqual(evidence.terminals.count, 1)
        let terminal = try XCTUnwrap(evidence.terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.operationKind, .openWithApp(bundleID))
        XCTAssertEqual(terminal.attemptedCount, 1)
        XCTAssertEqual(terminal.succeededCount, 0)
        XCTAssertEqual(terminal.failedCount, 1)
        XCTAssertEqual(terminal.cancelledCount, 0)
    }

    /// EOP-001-open_entry_with_selected_app: Other picker 다중 선택 취소는 선택 전체를 cancelled로 집계한다.
    /// - 검증 내용: picker가 nil을 반환할 때 파일별 action 없이 command terminal 한 건만 생성되는지 확인한다.
    /// - 사전 조건: 두 일반 파일, 고정 metadata, 취소되는 Other picker가 있다.
    /// - 기대 결과: mutation/open과 batch action 없이 attempted 2, cancelled 2인 terminal 한 건이 metadata를 보존한다.
    func testOtherPickerMultipleFilesCancellationEmitsTruthfulTerminal() async throws {
        let files = ["/tmp/cancel-a.txt", "/tmp/cancel-b.txt"].map {
            EntryModelFixtures.makeFileEntry(id: $0, name: URL(fileURLWithPath: $0).lastPathComponent)
        }
        let metadata = try makeMetadata(id: "00000000-0000-0000-0000-000000000701")
        let evidence = await EntryOperationsTestSupport.runOpenWithCommand(
            files: files,
            currentPath: "/tmp",
            bundleID: "com.apple.Preview",
            metadata: metadata,
            shouldSetAsDefault: true,
            usesOtherPicker: true,
            cancelsOtherPicker: true,
        )

        XCTAssertEqual(evidence.batchActionCount, 0)
        XCTAssertEqual(evidence.setDefaultCallCount + evidence.openCallCount, 0)
        try assertCancelledTerminal(
            evidence.terminals.map { .lifecycle(.entryActionCompleted($0)) },
            metadata: metadata,
            operationKind: .openWithApp(""),
            attemptedCount: files.count,
        )
    }
}

extension EOP001ExecuteEntryTests {
    /// EOP-001-open_entry_with_default_app: 휴지통에서 거부된 기본 앱 Open은 cancelled terminal 한 건을 낸다.
    /// - 검증 내용: accepted command가 open lifecycle 없이 모든 거부 경로를 cancelled로 집계하는지 확인한다.
    /// - 사전 조건: 휴지통 아래 두 파일과 고정 metadata가 있다.
    /// - 기대 결과: open 호출과 operationStarted 없이 cancelled 2인 terminal 한 건이 metadata를 보존한다.
    func testDefaultOpenTrashPreflightEmitsCancelledTerminal() async throws {
        let trashPath = "/tmp/.Trash"
        let files = ["a.txt", "b.txt"].map {
            EntryModelFixtures.makeFileEntry(id: "\(trashPath)/\($0)", name: $0)
        }
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000694")),
            interaction: .openEntryWithDefaultApp,
            source: .contextMenu,
        )
        let actions = LockIsolated<[EntryOperationsAction]>([])
        let openCalls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeObservedStore(
            observeAction: { action in actions.withValue { $0.append(action) } },
            configure: {
                $0.entryOpenClient.trashDirectoryPath = { trashPath }
                $0.entryOpenClient.open = { _, _ in openCalls.withValue { $0 += 1 } }
                $0.entryOperationsAlertClient.showTrashFileAlert = { _, _ in true }
            },
        )
        // store.exhaustivity = .off: observer로 accepted command의 전체 lifecycle 부재와 terminal을 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .navigation(.openSelectedItem),
            context: .init(
                selectedIds: Set(files.map(\.id)),
                displayItems: files,
                currentPath: "/tmp",
            ),
            metadata: metadata,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(openCalls.value, 0)
        XCTAssertFalse(actions.value.contains { action in
            if case .lifecycle(.operationStarted) = action { return true }
            return false
        })
        let terminals = actions.value.compactMap { action -> EntryActionRecord? in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return nil }
            return record
        }
        XCTAssertEqual(terminals.count, 1)
        let terminal = try XCTUnwrap(terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.operationKind, .openDefault)
        XCTAssertEqual(terminal.attemptedCount, files.count)
        XCTAssertEqual(terminal.succeededCount, 0)
        XCTAssertEqual(terminal.failedCount, 0)
        XCTAssertEqual(terminal.cancelledCount, files.count)
    }

    /// EOP-001-open_entry_with_default_app: 휴지통과 일반 파일 혼합 선택은 명령 전체를 취소한다.
    /// - 검증 내용: 기본 앱 Open이 일부 경로만 실행하지 않고 선택 전체를 cancelled로 집계하는지 확인한다.
    /// - 사전 조건: 일반 파일 하나와 휴지통 파일 하나, 고정 metadata, open recorder가 있다.
    /// - 기대 결과: open 호출 없이 attempted 2, cancelled 2인 terminal 한 건이 metadata를 보존한다.
    func testDefaultOpenMixedTrashSelectionCancelsWholeCommand() async throws {
        let trashPath = "/tmp/.Trash"
        let files = [
            EntryModelFixtures.makeFileEntry(id: "/tmp/normal.txt", name: "normal.txt"),
            EntryModelFixtures.makeFileEntry(id: "\(trashPath)/trashed.txt", name: "trashed.txt"),
        ]
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000696")),
            interaction: .openEntryWithDefaultApp,
            source: .contextMenu,
        )
        let actions = LockIsolated<[EntryOperationsAction]>([])
        let openCalls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeObservedStore(
            observeAction: { action in actions.withValue { $0.append(action) } },
            configure: {
                $0.entryOpenClient.trashDirectoryPath = { trashPath }
                $0.entryOpenClient.open = { _, _ in openCalls.withValue { $0 += 1 } }
                $0.entryOperationsAlertClient.showTrashFileAlert = { _, _ in true }
            },
        )
        // store.exhaustivity = .off: observer와 recorder로 명령 전체 거부 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .navigation(.openSelectedItem),
            context: .init(
                selectedIds: Set(files.map(\.id)),
                displayItems: files,
                currentPath: "/tmp",
            ),
            metadata: metadata,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(openCalls.value, 0)
        try assertCancelledTerminal(
            actions.value,
            metadata: metadata,
            operationKind: .openDefault,
            attemptedCount: files.count,
        )
    }

    /// EOP-001-open_entry_with_selected_app: 휴지통 selected-app Open은 default mutation 전에 취소된다.
    /// - 검증 내용: Always Open With accepted command가 set-default와 open lifecycle 없이 cancelled terminal을 내는지 확인한다.
    /// - 사전 조건: 휴지통 파일, 고정 metadata, set-default와 open recorder가 있다.
    /// - 기대 결과: mutation과 open 호출 없이 cancelled 1인 terminal 한 건이 metadata를 보존한다.
    func testSelectedAppOpenTrashPreflightCancelsBeforeSetDefault() async throws {
        let trashPath = "/tmp/.Trash"
        let file = EntryModelFixtures.makeFileEntry(id: "\(trashPath)/a.txt", name: "a.txt")
        let bundleID = "com.apple.Preview"
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000695")),
            interaction: .openEntryWithSelectedApp,
            source: .contextMenu,
        )
        let actions = LockIsolated<[EntryOperationsAction]>([])
        let setDefaultCalls = LockIsolated(0)
        let openCalls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeObservedStore(
            observeAction: { action in actions.withValue { $0.append(action) } },
            configure: {
                $0.entryOpenClient.trashDirectoryPath = { trashPath }
                $0.entryOpenClient.setDefaultApp = { _, _ in setDefaultCalls.withValue { $0 += 1 } }
                $0.entryOpenClient.open = { _, _ in openCalls.withValue { $0 += 1 } }
                $0.entryOperationsAlertClient.showTrashFileAlert = { _, _ in true }
            },
        )
        // store.exhaustivity = .off: observer와 recorder로 preflight 이후 lifecycle 부재를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .navigation(.openWithSelectedItem(
                bundleID: bundleID,
                shouldSetAsDefault: true,
            )),
            context: .init(
                selectedIds: [file.id],
                displayItems: [file],
                currentPath: "/tmp",
            ),
            metadata: metadata,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(setDefaultCalls.value, 0)
        XCTAssertEqual(openCalls.value, 0)
        XCTAssertFalse(actions.value.contains { action in
            if case .lifecycle(.operationStarted) = action { return true }
            return false
        })
        try assertCancelledTerminal(
            actions.value,
            metadata: metadata,
            operationKind: .openWithApp(bundleID),
            attemptedCount: 1,
        )
    }

    /// EOP-001-open_entry_with_selected_app: 휴지통과 일반 파일 혼합 선택은 mutation 전에 명령 전체를 취소한다.
    /// - 검증 내용: suspended Trash 경고 중에도 set-default/open이 시작되지 않고 선택 전체가 cancelled로 집계되는지 확인한다.
    /// - 사전 조건: 일반 파일 하나와 휴지통 파일 하나, 고정 metadata, 경고 gate와 호출 recorder가 있다.
    /// - 기대 결과: 경고 완료 전후 mutation/open 호출 없이 attempted 2, cancelled 2인 terminal 한 건이 metadata를 보존한다.
    func testSelectedAppMixedTrashSelectionPreflightsBeforeMutationAndCancelsWholeCommand() async throws {
        let trashPath = "/tmp/.Trash"
        let files = [
            EntryModelFixtures.makeFileEntry(id: "/tmp/normal.txt", name: "normal.txt"),
            EntryModelFixtures.makeFileEntry(id: "\(trashPath)/trashed.txt", name: "trashed.txt"),
        ]
        let bundleID = "com.apple.Preview"
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000697")),
            interaction: .openEntryWithSelectedApp,
            source: .contextMenu,
        )
        let alertGate = SelectionGate()
        let actions = LockIsolated<[EntryOperationsAction]>([])
        let setDefaultCalls = LockIsolated(0)
        let openCalls = LockIsolated(0)
        let store = EntryOperationsTestSupport.makeObservedStore(
            observeAction: { action in actions.withValue { $0.append(action) } },
            configure: {
                $0.entryOpenClient.trashDirectoryPath = { trashPath }
                $0.entryOpenClient.setDefaultApp = { _, _ in setDefaultCalls.withValue { $0 += 1 } }
                $0.entryOpenClient.open = { _, _ in openCalls.withValue { $0 += 1 } }
                $0.entryOperationsAlertClient.showTrashFileAlert = { _, _ in
                    await alertGate.wait("trash-alert")
                    return true
                }
            },
        )
        // store.exhaustivity = .off: observer와 recorder로 preflight 중간·완료 상태를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .navigation(.openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: true)),
            context: .init(selectedIds: Set(files.map(\.id)), displayItems: files, currentPath: "/tmp"),
            metadata: metadata,
        )))
        while await !alertGate.isStarted("trash-alert") {
            await Task.yield()
        }

        XCTAssertEqual(setDefaultCalls.value + openCalls.value, 0)

        await alertGate.resume("trash-alert")
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(setDefaultCalls.value + openCalls.value, 0)
        try assertCancelledTerminal(
            actions.value,
            metadata: metadata,
            operationKind: .openWithApp(bundleID),
            attemptedCount: files.count,
        )
    }

    /// EOP-001-open_entry_with_selected_app: 휴지통 파일은 열지 않고 경고 표시
    /// - 검증 내용: 휴지통 파일을 선택 앱으로 열려 할 때 open 호출이 차단되는지 확인합니다.
    /// - 사전 조건: trashDirectoryPath가 휴지통 경로 반환
    /// - 기대 결과: EntryOpenClient.open이 호출되지 않음
    func testOpenEntryWithSelectedApp_trashFile_noOp() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let trashDir = sandbox.root.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trashPath = trashDir.path
        let filePath = trashDir.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        let openCalls = CallRecorder<(URL, OpenKind)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.trashDirectoryPath = { trashPath }
            $0.entryOpenClient.open = { url, kind in
                openCalls.record((url, kind))
            }
        }

        await store.send(.openWith(.openFileWithAppBundleID(
            filePath: filePath,
            bundleID: "com.apple.Preview",
            url: URL(fileURLWithPath: filePath),
        )))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .openWithApp("com.apple.Preview")
                && record.succeededCount == 0
                && record.failedCount == 0
                && record.cancelledCount == 1
        }

        XCTAssertTrue(openCalls.recorded.isEmpty)
    }

    // MARK: - EOP-001-set_default_app_for_entry

    /// EOP-001-set_default_app_for_entry: 파일 확장자의 기본 앱 설정
    /// - 검증 내용: 기본 앱 설정 action이 대상 파일 URL과 앱 URL을 workspace client에 전달하는지 확인합니다.
    /// - 사전 조건: 파일 엔트리와 EntryOpenClient.setDefaultApp mock 준비
    /// - 기대 결과: 리듀서가 올바른 UTType과 bundleID로 EntryOpenClient.setDefaultApp을 호출
    func testSetDefaultAppForEntry_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let file = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )
        let bundleID = "com.apple.TextEdit"
        let setDefaultAppCalls = CallRecorder<(UTType, String)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.setDefaultApp = { type, id in
                setDefaultAppCalls.record((type, id))
            }
        }

        // store.exhaustivity = .off: setDefaultAppForFile 이후 .openWith(.applicationsLoaded) 가
        // 추가로 발생하므로 최종 호출 기록과 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.openWith(.setDefaultAppForFile(
            type: UTType(filenameExtension: "txt"),
            bundleID: bundleID,
            file: file,
        )))
        await store.finish()

        XCTAssertEqual(setDefaultAppCalls.recorded.count, 1)
        XCTAssertEqual(setDefaultAppCalls.recorded[0].0.identifier, "public.plain-text")
        XCTAssertEqual(setDefaultAppCalls.recorded[0].1, bundleID)
    }

    /// EOP-001-set_default_app_for_entry: 폴더에 기본 앱 설정 시 차단
    /// - 검증 내용: 폴더에 기본 앱 설정을 시도하면 지원하지 않는 타입 오류로 상태가 갱신되는지 확인합니다.
    /// - 사전 조건: isFolder = true인 엔트리
    /// - 기대 결과: EntryOpenClient.setDefaultApp이 호출되지 않고 unsupportedType이 기록됨
    func testSetDefaultAppForEntry_folder_setsUnsupportedTypeError() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTestFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let folder = EntryModelFixtures.makeEntry(
            path: tempDir.path,
            isFolder: true,
        )
        let setDefaultAppCalls = CallRecorder<(UTType, String)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.setDefaultApp = { type, id in
                setDefaultAppCalls.record((type, id))
            }
        }

        await store.send(.openWith(.setDefaultAppForFile(
            type: nil,
            bundleID: "com.example.app",
            file: folder,
        ))) {
            $0.itemStates[folder.fullPath] = ItemOperationState(isBusy: false, lastError: .unsupportedType)
        }

        XCTAssertTrue(setDefaultAppCalls.recorded.isEmpty)
    }

    // MARK: - EOP-001-quick_look_entry

    /// EOP-001-quick_look_entry: Quick Look으로 엔트리 미리보기
    /// - 검증 내용: Quick Look action이 선택한 파일 URL을 preview 의존성에 전달하는지 확인합니다.
    /// - 사전 조건: EntryQuickLookClient mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 URL로 EntryQuickLookClient.quickLook을 호출
    func testQuickLookEntry_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let fileURL = sandbox.fileURL
        let quickLookCalls = CallRecorder<([URL], Int)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryQuickLookClient = EntryQuickLookClient(
                quickLook: { urls, index in
                    quickLookCalls.record((urls, index))
                },
            )
        }

        await store.send(.open(.quickLookFiles(paths: [filePath])))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        // 비-undo quickLook 명령도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

        XCTAssertEqual(quickLookCalls.recorded.count, 1)
        XCTAssertEqual(quickLookCalls.recorded[0].0, [fileURL])
        XCTAssertEqual(quickLookCalls.recorded[0].1, 0)
    }

    /// EOP-001-quick_look_entry: Quick Look 실패 시 error state 반영
    /// - 검증 내용: EntryQuickLookClient.quickLook 오류가 lifecycle failure로 변환된다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, Quick Look client는 실패를 던진다.
    /// - 기대 결과: 해당 경로의 busy 상태가 해제되고 lastError가 기록된다.
    func testQuickLookEntry_clientFailure_setsLastError() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let error = FileOpError.system(message: "Quick Look unavailable")

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryQuickLookClient = EntryQuickLookClient(
                quickLook: { _, _ in throw error },
            )
        }

        await store.send(.open(.quickLookFiles(paths: [filePath])))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false, lastError: error)
        }

        // 비-undo quickLook 명령도 실패 시에도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

        XCTAssertEqual(store.state.itemStates[filePath]?.lastError, error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-001-quick_look_entry: 빈 경로 목록 전달 시 아무 동작도 수행하지 않음
    /// - 검증 내용: 빈 경로 입력에서 Quick Look 의존성이 호출되지 않는지 확인합니다.
    /// - 사전 조건: 초기 상태, 의존성 mock 설정
    /// - 기대 결과: EntryQuickLookClient.quickLook이 호출되지 않음
    func testQuickLookEntry_emptyPaths_noOp() async {
        let quickLookCalls = CallRecorder<([URL], Int)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryQuickLookClient = EntryQuickLookClient(
                quickLook: { urls, index in
                    quickLookCalls.record((urls, index))
                },
            )
        }

        await store.send(.open(.quickLookFiles(paths: [])))

        XCTAssertTrue(quickLookCalls.recorded.isEmpty)
    }

    // MARK: - EOP-001-quick_look_selection_sync

    /// EOP-001-quick_look_selection_sync: 선택 동기화가 경로 순서와 인덱스를 그대로 전달한다.
    /// - 검증 내용: syncQuickLookSelection action이 순서가 유지된 URL 배열과 선택 인덱스를 client에 전달하고, 상태 변화나 lifecycle 이벤트가 없는지 확인한다.
    /// - 사전 조건: EntryQuickLookClient의 syncQuickLookSelection을 기록하는 recorder로 교체
    /// - 기대 결과: client 호출 1회, URL 순서 보존, 인덱스 일치, operationStarted/operationFinished 없음
    func testQuickLookSelectionSyncForwardsOrderedURLsAndIndex() async {
        let quickLookSyncCalls = CallRecorder<([URL], Int)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryQuickLookClient = EntryQuickLookClient(
                quickLook: { _, _ in },
                syncQuickLookSelection: { urls, index in
                    quickLookSyncCalls.record((urls, index))
                },
            )
        }

        await store.send(.open(.syncQuickLookSelection(
            paths: ["/a.txt", "/b.txt", "/c.txt"],
            selectedIndex: 1,
        )))
        await store.finish()

        XCTAssertEqual(quickLookSyncCalls.recorded.count, 1)
        XCTAssertEqual(
            quickLookSyncCalls.recorded[0].0,
            [URL(fileURLWithPath: "/a.txt"), URL(fileURLWithPath: "/b.txt"), URL(fileURLWithPath: "/c.txt")],
        )
        XCTAssertEqual(quickLookSyncCalls.recorded[0].1, 1)
    }

    /// EOP-001-quick_look_selection_sync: 빈 경로 목록 전달 시 아무 동작도 수행하지 않음
    /// - 검증 내용: 빈 경로 입력에서 syncQuickLookSelection 의존성이 호출되지 않고 lifecycle 이벤트도 없는지 확인한다.
    /// - 사전 조건: 초기 상태, 의존성 mock 설정
    /// - 기대 결과: syncQuickLookSelection 호출 없음, operationStarted/operationFinished 없음
    func testQuickLookSelectionSyncEmptyPathsNoOp() async {
        let quickLookSyncCalls = CallRecorder<([URL], Int)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryQuickLookClient = EntryQuickLookClient(
                quickLook: { _, _ in },
                syncQuickLookSelection: { urls, index in
                    quickLookSyncCalls.record((urls, index))
                },
            )
        }

        await store.send(.open(.syncQuickLookSelection(paths: [], selectedIndex: 0)))
        await store.finish()

        XCTAssertTrue(quickLookSyncCalls.recorded.isEmpty)
    }
}

private extension EOP001ExecuteEntryTests {
    func makeMetadata(id: String) throws -> EntryCommandMetadata {
        try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: id)),
            interaction: .openEntryWithSelectedApp,
            source: .contextMenu,
        )
    }

    func assertCancelledTerminal(
        _ actions: [EntryOperationsAction],
        metadata: EntryCommandMetadata,
        operationKind: OperationKind,
        attemptedCount: Int,
    ) throws {
        let terminals = actions.compactMap { action -> EntryActionRecord? in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return nil }
            return record
        }
        XCTAssertEqual(terminals.count, 1)
        let terminal = try XCTUnwrap(terminals.first)
        XCTAssertEqual(terminal.command, metadata)
        XCTAssertEqual(terminal.operationKind, operationKind)
        XCTAssertEqual(terminal.attemptedCount, attemptedCount)
        XCTAssertEqual(terminal.succeededCount, 0)
        XCTAssertEqual(terminal.failedCount, 0)
        XCTAssertEqual(terminal.cancelledCount, attemptedCount)
    }
}

// MARK: - Entry Command Terminal Records

extension EOP001ExecuteEntryTests {
    // MARK: - EOP-001-entry_command_terminal

    /// EOP-001-entry_command_terminal: 수용된 비-undo 명령은 정확히 한 건의 command-level terminal을 낸다.
    /// quickLook 성공 시 operationFinished 이후 entryActionCompleted terminal이 정확히 한 번 이어지는지 검증한다.
    /// - 검증 내용: terminal record의 operationKind는 .quickLook이고 targets는 비며 failedCount는 0이다.
    /// - 사전 조건: EntryQuickLookClient mock 성공 응답
    /// - 기대 결과: entryActionCompleted(.quickLook, targets: [], failedCount: 0)가 한 번 수신된다.
    func testQuickLookCommandEmitsSingleTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryQuickLookClient = EntryQuickLookClient(quickLook: { _, _ in })
        }
        // store.exhaustivity = .off: terminal 계약만 검증하고 중간 lifecycle 수신은 생략함
        store.exhaustivity = .off

        await store.send(.open(.quickLookFiles(paths: [filePath])))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .quickLook
                && record.targets.isEmpty
                && record.failedCount == 0
                && record.succeededCount == 1
        }
        await store.finish()
    }

    /// EOP-001-entry_command_terminal: 공유 명령도 한 건의 command-level terminal을 낸다.
    /// - 검증 내용: terminal record의 operationKind는 .share이고 실패 없이 완료된다.
    /// - 사전 조건: EntryOpenClient.shareItems mock 성공 응답
    /// - 기대 결과: entryActionCompleted(.share, targets: [], failedCount: 0)가 한 번 수신된다.
    func testShareCommandEmitsSingleTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.shareItems = { _, _ in }
        }
        // store.exhaustivity = .off: terminal 계약만 검증하고 중간 lifecycle 수신은 생략함
        store.exhaustivity = .off

        await store.send(.open(.shareItems(paths: [filePath], anchor: nil)))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .share
                && record.targets.isEmpty
                && record.failedCount == 0
                && record.succeededCount == 1
        }
        await store.finish()
    }

    /// EOP-001-entry_command_terminal: Finder 표시 명령도 한 건의 command-level terminal을 낸다.
    /// - 검증 내용: terminal record의 operationKind는 .revealInFinder이고 실패 없이 완료된다.
    /// - 사전 조건: EntryOpenClient.revealInFinder mock 성공 응답
    /// - 기대 결과: entryActionCompleted(.revealInFinder, targets: [], failedCount: 0)가 한 번 수신된다.
    func testRevealInFinderCommandEmitsSingleTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.revealInFinder = { _ in }
        }
        // store.exhaustivity = .off: terminal 계약만 검증하고 중간 lifecycle 수신은 생략함
        store.exhaustivity = .off

        await store.send(.open(.revealInFinder(paths: [filePath])))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .revealInFinder
                && record.targets.isEmpty
                && record.failedCount == 0
                && record.succeededCount == 1
        }
        await store.finish()
    }

    /// EOP-001-entry_command_terminal: open 전체 실패도 failedCount를 담은 한 건의 terminal을 낸다.
    /// 모든 파일 열기가 실패하면 targets 없이 시도 수만큼 failedCount를 가진 record로 마무리되는지 검증한다.
    /// - 검증 내용: terminal record의 operationKind는 .openDefault이고 failedCount는 시도 수와 같다.
    /// - 사전 조건: 기본 앱 해석 실패(urlForApplicationToOpen nil)와 open client 실패
    /// - 기대 결과: entryActionCompleted(.openDefault, targets: [], failedCount: 2)가 한 번 수신된다.
    func testOpenFilesAllFailureEmitsFailureTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let error = FileOpError.system(message: "open unavailable")

        let store = EntryOperationsTestSupport.makeStore {
            $0.workspaceClient.urlForApplicationToOpen = { _ in nil }
            $0.entryOpenClient.open = { _, _ in throw error }
        }
        // store.exhaustivity = .off: 전체 실패 terminal 계약만 검증함
        store.exhaustivity = .off

        await store.send(.open(.openFiles(paths: [
            sandbox.fileURL.path,
            sandbox.originalFixture.path,
        ])))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .openDefault
                && record.targets.isEmpty
                && record.failedCount == 2
                && record.succeededCount == 0
        }
        await store.finish()
    }

    /// EOP-001-entry_command_terminal: open 성공은 failedCount 0인 한 건의 terminal을 낸다.
    /// - 검증 내용: terminal record의 operationKind는 .openDefault이고 failedCount는 0이다.
    /// - 사전 조건: 기본 앱 해석 실패 이후 개별 open은 성공하는 mock
    /// - 기대 결과: entryActionCompleted(.openDefault, targets: [], failedCount: 0)가 한 번 수신된다.
    func testOpenFilesSuccessEmitsSingleTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let store = EntryOperationsTestSupport.makeStore {
            $0.workspaceClient.urlForApplicationToOpen = { _ in nil }
        }
        // store.exhaustivity = .off: terminal 계약만 검증하고 중간 lifecycle 수신은 생략함
        store.exhaustivity = .off

        await store.send(.open(.openFiles(paths: [sandbox.fileURL.path])))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .openDefault
                && record.targets.isEmpty
                && record.failedCount == 0
                && record.succeededCount == 1
        }
        await store.finish()
    }

    /// EOP-001-entry_command_terminal: 선택 앱 열기 성공은 실제 OperationKind를 보존한 terminal을 낸다.
    /// - 검증 내용: terminal record의 operationKind는 .openWithApp(bundleID)이고 succeededCount는 1이다.
    /// - 사전 조건: EntryOpenClient.open 성공 mock, 비휴지통 경로
    /// - 기대 결과: entryActionCompleted(.openWithApp, targets: [], failed: 0, succeeded: 1)가 한 번 수신된다.
    func testOpenFileWithAppBundleIDEmitsTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.trashDirectoryPath = { nil }
            $0.entryOpenClient.open = { _, _ in }
        }
        // store.exhaustivity = .off: terminal 계약만 검증하고 중간 lifecycle 수신은 생략함
        store.exhaustivity = .off

        await store.send(.openWith(.openFileWithAppBundleID(
            filePath: filePath,
            bundleID: "com.apple.Preview",
            url: sandbox.fileURL,
        )))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .openWithApp("com.apple.Preview")
                && record.targets.isEmpty
                && record.failedCount == 0
                && record.succeededCount == 1
        }
        await store.finish()
    }

    /// EOP-001-entry_command_terminal: 선택 앱 열기 실패도 실패 aggregate를 담은 terminal을 낸다.
    /// - 검증 내용: terminal record의 failedCount는 1이고 succeededCount는 0이다.
    /// - 사전 조건: EntryOpenClient.open 실패 mock
    /// - 기대 결과: entryActionCompleted(.openWithApp, targets: [], failed: 1, succeeded: 0)가 한 번 수신된다.
    func testOpenFileWithAppBundleIDFailureEmitsFailureTerminalRecord() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.trashDirectoryPath = { nil }
            $0.entryOpenClient.open = { _, _ in throw FileOpError.system(message: "open denied") }
        }
        // store.exhaustivity = .off: 전체 실패 terminal 계약만 검증함
        store.exhaustivity = .off

        await store.send(.openWith(.openFileWithAppBundleID(
            filePath: filePath,
            bundleID: "com.apple.Preview",
            url: sandbox.fileURL,
        )))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .openWithApp("com.apple.Preview")
                && record.targets.isEmpty
                && record.failedCount == 1
                && record.succeededCount == 0
        }
        await store.finish()
    }
}
