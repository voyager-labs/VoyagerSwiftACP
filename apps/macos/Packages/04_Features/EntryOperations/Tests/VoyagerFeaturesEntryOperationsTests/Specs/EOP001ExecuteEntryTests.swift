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

        XCTAssertEqual(openCalls.recorded.count, 1)
        XCTAssertEqual(openCalls.recorded[0].0, fileURL)
        XCTAssertEqual(openCalls.recorded[0].1, .bundleID(bundleID))
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
}
