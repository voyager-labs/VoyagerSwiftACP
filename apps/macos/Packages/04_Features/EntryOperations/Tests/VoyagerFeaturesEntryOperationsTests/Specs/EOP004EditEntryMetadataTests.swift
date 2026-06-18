import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EOP004EditEntryMetadataTests: XCTestCase {
    /// EOP-004-rename_entry: 엔트리 이름 변경
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사
    /// - 기대 결과: 파일명이 변경되고, FileOpsRecorder에 기록되며, 새 경로에 파일 존재
    func testRenameEntry_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let originalPath = sandbox.fileURL.path
        let renamedName = "11-renamed.txt"
        let renamedPath = sandbox.fileURL.deletingLastPathComponent().appendingPathComponent(renamedName).path
        let entry = EntryModelFixtures.makeFileEntry(
            id: originalPath,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.renameFile = { source, destination in
            try await liveClient.renameFile(source, destination)
            recorder.recordRename(source: source, destination: destination)
        }

        var initialState = EntryOperationsState()
        initialState.items = [entry]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
        }

        // store.exhaustivity = .off: rename은 startRename→commitRename→renameItem 비동기 체인으로
        // 중간 lifecycle action이 많아 최종 state, recorder, filesystem만 검증한다.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.edit(.startRename(item: entry, text: renamedName)))

        await store.send(.edit(.commitRename))

        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertEqual(recorder.renamedPaths.count, 1)
        XCTAssertEqual(recorder.renamedPaths.first?.source.path, originalPath)
        XCTAssertEqual(recorder.renamedPaths.first?.destination.path, renamedPath)
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.operationKind, .rename)
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.beforePath, originalPath)
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.afterPath, renamedPath)
    }

    /// EOP-004-get_entry_info: 엔트리 상세 정보 확인
    /// - 사전 조건: `fixtures/fixtures/archives/COMPRESS-264.zip`를 FixtureSandbox로 복사
    /// - 기대 결과: Get Info 경로가 실행되고, 파일 속성(name/size/type)이 정확히 읽힘
    func testGetEntryInfo_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/archives/COMPRESS-264.zip")
        defer { sandbox.cleanup() }

        let path = sandbox.fileURL.path
        let expectedAttributes = try FileManager.default.attributesOfItem(atPath: path)
        let expectedSize = try XCTUnwrap(expectedAttributes[.size] as? Int)

        let capture = FileInfoCapture()

        let openClient = EntryOpenClient.previewValue
        var entryOpenClient = openClient
        entryOpenClient.openFinderInfo = { urls in
            XCTAssertEqual(urls.count, 1)
            try capture.record(
                url: urls.first,
                values: urls.first?.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .nameKey]),
            )
        }

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient = entryOpenClient
            $0.entryThumbnailCacheClient = .testValue
        }

        await store.send(.open(.openFinderInfo(paths: [path])))

        await store.receive { action in
            if case .lifecycle(.operationStarted(path, .getInfo)) = action { return true }
            return false
        } assert: { state in
            state.itemStates[path] = ItemOperationState(isBusy: true, lastError: nil)
        }

        await store.receive { action in
            if case .lifecycle(.operationFinished(path, .getInfo, .success(()))) = action { return true }
            return false
        } assert: { state in
            state.itemStates[path]?.isBusy = false
        }

        XCTAssertEqual(capture.url, sandbox.fileURL)
        XCTAssertEqual(capture.resourceValues?.fileSize, expectedSize)
        XCTAssertEqual(capture.resourceValues?.isRegularFile, true)
        XCTAssertEqual(capture.resourceValues?.name, sandbox.fileURL.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-004-rename_entry itemsLoaded 취소

    /// EOP-004-rename_entry: itemsLoaded에 의한 rename 자동 취소
    /// 이름 변경이 진행 중일 때 directory listing이 갱신되어 대상 Entry가 더 이상 목록에 없으면 rename 상태가 자동 정리된다.
    /// - 검증 내용: `itemsLoaded` 이벤트가 renamingItemId 미포함 목록으로 들어오면 `cancelRename`이 자동 발생한다.
    /// - 사전 조건: renamingItemId가 설정된 상태에서 itemsLoaded가 다른 항목들만 포함한 목록으로 들어온다.
    /// - 기대 결과: renamingItemId, renamingText, renamingItem이 모두 nil/빈 문자열로 초기화된다.
    func testRenameEntry_itemsLoadedCancelsWhenItemDisappears() async {
        let entry = EntryModelFixtures.makeFileEntry(
            id: "/tmp/disappeared.txt",
            name: "disappeared.txt",
            fileExtension: "txt",
        )
        let otherEntry = EntryModelFixtures.makeFileEntry(
            id: "/tmp/other.txt",
            name: "other.txt",
            fileExtension: "txt",
        )

        var initialState = EntryOperationsState()
        initialState.items = [entry]
        initialState.renamingItemId = entry.id
        initialState.renamingText = "new_name.txt"
        initialState.renamingItem = entry

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryThumbnailCacheClient = .testValue
        }

        // store.exhaustivity = .off: itemsLoaded가 cancelRename을 내부 발생시켜 수신 action이 예측 가능해야 한다.
        store.exhaustivity = .off

        // itemsLoaded에 renamingItemId가 포함되지 않은 목록이 들어옴
        await store.send(.loading(.itemsLoaded([otherEntry]))) {
            $0.items = IdentifiedArrayOf(uniqueElements: [otherEntry])
            $0.isLoading = false
            $0.isReloading = false
        }

        // cancelRename이 자동으로 발생하여 renaming 상태가 정리됨
        await store.receive(\.edit.cancelRename) {
            $0.renamingItemId = nil
            $0.renamingText = ""
            $0.renamingItem = nil
        }

        await store.finish()

        XCTAssertNil(store.state.renamingItemId)
        XCTAssertEqual(store.state.renamingText, "")
        XCTAssertNil(store.state.renamingItem)
    }

    /// EOP-004-rename_entry: itemsLoaded 시 대상 Entry가 여전히 존재하면 rename이 유지된다
    /// 이름 변경이 진행 중일 때 directory listing이 갱신되어도 대상 Entry가 여전히 존재하면 rename 상태가 보존된다.
    /// - 검증 내용: `itemsLoaded` 이벤트가 renamingItemId 포함 목록으로 들어오면 rename 상태가 유지된다.
    /// - 사전 조건: renamingItemId가 설정된 상태에서 itemsLoaded에 해당 ID가 포함된다.
    /// - 기대 결과: renamingItemId, renamingText, renamingItem이 그대로 유지된다.
    func testRenameEntry_itemsLoadedPreservesWhenItemStillExists() async {
        let entry = EntryModelFixtures.makeFileEntry(
            id: "/tmp/kept.txt",
            name: "kept.txt",
            fileExtension: "txt",
        )

        var initialState = EntryOperationsState()
        initialState.isLoading = true
        initialState.items = [entry]
        initialState.renamingItemId = entry.id
        initialState.renamingText = "new_name.txt"
        initialState.renamingItem = entry

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryThumbnailCacheClient = .testValue
        }

        await store.send(.loading(.itemsLoaded([entry]))) {
            $0.isLoading = false
            $0.isReloading = false
        }

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "new_name.txt")
        XCTAssertEqual(store.state.renamingItem?.id, entry.id)
    }

    // MARK: - EOP-004-rename_entry extension_change_alert

    /// EOP-004-rename_entry: 확장자 변경 시 alert 표시 후 사용자가 Continue 선택하면 rename이 진행된다
    /// 파일 확장자가 변경되면 확인 alert이 표시되고, 사용자가 Continue를 선택하면 새 이름으로 rename이 실행된다.
    /// - 검증 내용: `commitRename`에서 extension transition 감지 후 alert을 거쳐 renameItem이 실행된다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사, renamingText를 다른 확장자로 설정.
    /// - 기대 결과: alert이 표시되고(기본값 true), 새 확장자 파일이 생성되며 원본은 제거된다.
    func testRenameEntry_extensionChangeAlert_confirmed() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let originalPath = sandbox.fileURL.path
        let renamedName = "11.png"
        let renamedPath = sandbox.fileURL.deletingLastPathComponent().appendingPathComponent(renamedName).path
        let entry = EntryModelFixtures.makeFileEntry(
            id: originalPath,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.renameFile = { source, destination in
            try await liveClient.renameFile(source, destination)
            recorder.recordRename(source: source, destination: destination)
        }

        var initialState = EntryOperationsState()
        initialState.items = [entry]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
            // testValue 기본 showRenameExtensionChangeAlert = true
        }

        // store.exhaustivity = .off: rename 비동기 체인으로 중간 action이 많아 최종 state만 검증한다.
        store.exhaustivity = .off

        await store.send(.edit(.startRename(item: entry, text: renamedName)))
        await store.send(.edit(.commitRename))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
        XCTAssertEqual(recorder.renamedPaths.count, 1)
        XCTAssertEqual(recorder.renamedPaths.first?.source.path, originalPath)
        XCTAssertEqual(recorder.renamedPaths.first?.destination.path, renamedPath)
    }

    /// EOP-004-rename_entry: 확장자 변경 alert에서 사용자가 Cancel 선택하면 rename이 중단된다
    /// 파일 확장자가 변경되면 확인 alert이 표시되고, 사용자가 Cancel을 선택하면 이름 변경이 중단된다.
    /// - 검증 내용: `commitRename`에서 extension transition 감지 후 alert에서 false 반환 시 rename이 실행되지 않는다.
    /// - 사전 조건: renamingText를 다른 확장자로 설정, alert client가 false를 반환하도록 주입.
    /// - 기대 결과: 원본 파일이 그대로 유지되고 새 이름의 파일은 생성되지 않는다.
    func testRenameEntry_extensionChangeAlert_cancelled() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let originalPath = sandbox.fileURL.path
        let renamedName = "11.png"
        let renamedPath = sandbox.fileURL.deletingLastPathComponent().appendingPathComponent(renamedName).path
        let entry = EntryModelFixtures.makeFileEntry(
            id: originalPath,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.renameFile = { source, destination in
            try await liveClient.renameFile(source, destination)
            recorder.recordRename(source: source, destination: destination)
        }

        var initialState = EntryOperationsState()
        initialState.items = [entry]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
            $0.entryOperationsAlertClient.showRenameExtensionChangeAlert = { _, _ in false }
        }

        store.exhaustivity = .off

        await store.send(.edit(.startRename(item: entry, text: renamedName)))
        await store.send(.edit(.commitRename))
        await store.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedPath))
        XCTAssertTrue(recorder.renamedPaths.isEmpty)
    }

    /// EOP-004-rename_entry: 폴더 이름 변경 시 확장자 변경 alert이 표시되지 않는다
    /// 폴더는 확장자 검사에서 제외되어, 이름에 점이 포함되어도 alert 없이 바로 rename이 진행된다.
    /// - 검증 내용: isFolder=true인 Entry는 extension transition이 항상 `.none`이어야 한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사 후 폴더 Entry로 설정.
    /// - 기대 결과: alert 호출 없이 rename이 바로 실행되고 새 이름의 폴더가 생성된다.
    func testRenameEntry_folderNoExtensionAlert() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let originalPath = sandbox.fileURL.path
        let renamedName = "11.config"
        let renamedPath = sandbox.fileURL.deletingLastPathComponent().appendingPathComponent(renamedName).path

        let entry = EntryModelFixtures.makeEntry(
            path: originalPath,
            isFolder: true,
        )

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.renameFile = { source, destination in
            try await liveClient.renameFile(source, destination)
            recorder.recordRename(source: source, destination: destination)
        }

        let alertCounter = LockIsolated(0)
        var initialState = EntryOperationsState()
        initialState.items = [entry]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
            $0.entryOperationsAlertClient.showRenameExtensionChangeAlert = { _, _ in
                alertCounter.withValue { $0 += 1 }
                return true
            }
        }

        // store.exhaustivity = .off: 폴더 rename은 바로 renameItem으로 이어져 최종 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.edit(.startRename(item: entry, text: renamedName)))
        await store.send(.edit(.commitRename))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(alertCounter.value, 0, "폴더 이름 변경 시 확장자 alert이 호출되지 않아야 한다")
        XCTAssertEqual(recorder.renamedPaths.count, 1)
        XCTAssertEqual(recorder.renamedPaths.first?.destination.path, renamedPath)
    }

    // AC: EOP-004-rename_entry Edge Case #8 (same extension → no alert)
    /// EOP-004-rename_entry: 같은 확장자로 이름 변경 시 alert 없이 바로 rename이 진행된다
    /// 파일의 확장자가 동일하게 유지되면 extension-change alert이 표시되지 않고 이름 변경이 바로 실행된다.
    /// - 검증 내용: `.txt` → `.txt`처럼 확장자가 같으면 alert client가 호출되지 않는다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사, 동일 확장자로 rename.
    /// - 기대 결과: alert 호출 횟수 0, rename 정상 수행, 새 이름 파일 존재.
    func testRenameEntry_sameExtension_noAlert_renamesDirectly() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let originalPath = sandbox.fileURL.path
        let renamedName = "Draft.txt"
        let renamedPath = sandbox.fileURL.deletingLastPathComponent().appendingPathComponent(renamedName).path
        let entry = EntryModelFixtures.makeFileEntry(
            id: originalPath,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.renameFile = { source, destination in
            try await liveClient.renameFile(source, destination)
            recorder.recordRename(source: source, destination: destination)
        }

        let alertCounter = LockIsolated(0)
        var initialState = EntryOperationsState()
        initialState.items = [entry]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
            $0.entryOperationsAlertClient.showRenameExtensionChangeAlert = { _, _ in
                alertCounter.withValue { $0 += 1 }
                return true
            }
        }

        // store.exhaustivity = .off: rename 비동기 체인으로 중간 action이 많아 최종 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.edit(.startRename(item: entry, text: renamedName)))
        await store.send(.edit(.commitRename))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(alertCounter.value, 0, "같은 확장자로 이름 변경 시 alert이 호출되지 않아야 한다")
        XCTAssertEqual(recorder.renamedPaths.count, 1)
        XCTAssertEqual(recorder.renamedPaths.first?.source.path, originalPath)
        XCTAssertEqual(recorder.renamedPaths.first?.destination.path, renamedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
    }

    /// EOP-004-rename_entry: dotfile은 확장자 없는 파일로 취급되어 alert이 표시되지 않는다
    /// `.env` 같은 dotfile은 점 뒤에 추가 점이 없으면 확장자 없는 파일로 취급한다.
    /// - 검증 내용: dotfile 간 이름 변경 시 EntryRenameExtensionPolicy가 `.none`을 반환한다.
    /// - 사전 조건: `.env` → `.zshrc`로 변경 (둘 다 dotfile, extensionless).
    /// - 기대 결과: 전이 유형이 `.none`이다.
    func testRenameEntry_dotfileNoExtensionAlert() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: ".env",
            to: ".zshrc",
            isFolder: false,
        )
        XCTAssertEqual(transition, .none, ".env → .zshrc는 둘 다 extensionless dotfile이므로 확장자 변경이 아니다")
    }

    // MARK: - EOP-004-edit_entry_tags

    /// EOP-004-edit_entry_tags: 엔트리 태그 편집 미구현 AC 추적
    /// 해당 인터랙션의 AC가 아직 구현되지 않았다.
    /// - 검증 내용: 해당 인터랙션의 AC가 아직 구현되지 않았다.
    /// - 사전 조건: 인터랙션 스펙 문서 status가 "planned"이다.
    /// - 기대 결과: 구현 시 이 XCTSkip을 실제 테스트로 교체한다.
    func testEditEntryTags_pendingImplementation() throws {
        throw XCTSkip("AC not yet implemented: edit_entry_tags (status: planned)")
    }

    // MARK: - EOP-004-change_entry_permissions

    /// EOP-004-change_entry_permissions: 엔트리 권한 변경 미구현 AC 추적
    /// 해당 인터랙션의 AC가 아직 구현되지 않았다.
    /// - 검증 내용: 해당 인터랙션의 AC가 아직 구현되지 않았다.
    /// - 사전 조건: 인터랙션 스펙 문서 status가 "planned"이다.
    /// - 기대 결과: 구현 시 이 XCTSkip을 실제 테스트로 교체한다.
    func testChangeEntryPermissions_pendingImplementation() throws {
        throw XCTSkip("AC not yet implemented: change_entry_permissions (status: planned)")
    }

    // MARK: - EOP-004-batch_rename_entries

    /// EOP-004-batch_rename_entries: 다중 엔트리 일괄 이름 변경 미구현 AC 추적
    /// 해당 인터랙션의 AC가 아직 구현되지 않았다.
    /// - 검증 내용: 해당 인터랙션의 AC가 아직 구현되지 않았다.
    /// - 사전 조건: 인터랙션 스펙 문서 status가 "planned"이다.
    /// - 기대 결과: 구현 시 이 XCTSkip을 실제 테스트로 교체한다.
    func testBatchRenameEntries_pendingImplementation() throws {
        throw XCTSkip("AC not yet implemented: batch_rename_entries (status: planned)")
    }
}

private final class FileInfoCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _url: URL?
    private var _resourceValues: URLResourceValues?

    func record(url: URL?, values: URLResourceValues?) throws {
        lock.lock()
        defer { lock.unlock() }
        _url = url
        _resourceValues = values
    }

    var url: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _url
    }

    var resourceValues: URLResourceValues? {
        lock.lock()
        defer { lock.unlock() }
        return _resourceValues
    }
}
