import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

// MARK: - EOP-001-execute_entry

@MainActor
final class EOP001ExecuteEntryTests: XCTestCase {
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
