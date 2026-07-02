import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

private let set010ReadFailedSentinel = "__voyager_default_file_viewer_read_failed__"

// SET-010-set_default_file_viewer / SET-010-restore_default_file_viewer 증거 계약.
// 기본 파일 뷰어 진단 상태 매핑, Finder ↔ Voyager 전환 성공/실패, 진행 중 버튼 비활성화(G4),
// 성공 후 자동 재진단(G5), unknown 상태에서 "다시 확인" 버튼(G16)을 검증한다.

/// 비동기 테스트용 호출 카운터
final class SET010Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

@MainActor
final class SET010DefaultFileViewerSettingsTests: XCTestCase {
    nonisolated(unsafe) private var storage = InMemoryStorage()

    override func setUp() {
        super.setUp()
        storage = InMemoryStorage()
    }

    override func tearDown() {
        storage = InMemoryStorage()
        super.tearDown()
    }

    private func makeStore(
        initialState: GeneralSettingsFeature.State = .init(),
        launchAtLoginEnabled: Bool = false,
        launchAtLoginSetEnabled: @escaping @Sendable (Bool) throws -> Void = { _ in },
        homePath: String = "/",
        pickDirectory: @escaping @Sendable () async -> String? = { nil },
        pathExists: @escaping @Sendable (String) -> Bool = { _ in false },
        isDirectory: @escaping @Sendable (String) -> Bool = { _ in false },
        diagnose: @escaping @Sendable () async -> DefaultFileViewerStatus = { .unknown },
        setVoyagerAsDefault: @escaping @Sendable () async throws -> Void = {},
        restoreFinder: @escaping @Sendable () async throws -> Void = {},
    ) -> TestStore<GeneralSettingsFeature.State, GeneralSettingsFeature.Action> {
        let storage = storage
        let userDefaultsClient = UserDefaultsClient(
            bool: { key in storage.getBool(key) ?? false },
            setBool: { value, key in storage.setBool(value, forKey: key) },
            string: { key in storage.getString(key) },
            setString: { value, key in storage.setString(value, forKey: key) },
            double: { _ in 0 },
            setDouble: { _, _ in },
            object: { key in storage.getObject(key) },
            setObject: { value, key in storage.setObject(value, forKey: key) },
        )
        let directoryClient = DirectorySelectionClient(
            pickDirectory: pickDirectory,
            pathExists: pathExists,
            isDirectory: isDirectory,
            defaultHomePath: { homePath },
        )
        let defaultFileViewerClient = DefaultFileViewerClient(
            appBundleID: DefaultFileViewerClient.voyagerBundleID,
            diagnose: diagnose,
            setVoyagerAsDefault: setVoyagerAsDefault,
            restoreFinder: restoreFinder,
        )
        return TestStore(initialState: initialState) {
            GeneralSettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = userDefaultsClient
            $0.launchAtLoginClient = LaunchAtLoginClient(
                isEnabled: { launchAtLoginEnabled },
                setEnabled: launchAtLoginSetEnabled,
            )
            $0.directorySelectionClient = directoryClient
            $0.defaultFileViewerClient = defaultFileViewerClient
        }
    }

    // MARK: - 추가 AC 1: 섹션 로드 자동 진단 (Tests 1-4)

    /// 진단 결과 voyagerIsDefault 매핑
    func testDiagnoseVoyagerIsDefault() async {
        let store = makeStore(diagnose: { .voyagerIsDefault })
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .sectionAppeared))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .voyagerIsDefault)
    }

    /// 진단 결과 finderIsDefault 매핑
    func testDiagnoseFinderIsDefault() async {
        let store = makeStore(diagnose: { .finderIsDefault })
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)
    }

    /// 진단 결과 otherIsDefault 매핑
    func testDiagnoseOtherIsDefault() async {
        let store = makeStore(diagnose: { .otherIsDefault(appBundleID: "com.test.app", appDisplayName: "TestApp") })
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(
            .otherIsDefault(
                appBundleID: "com.test.app",
                appDisplayName: "TestApp",
            ),
            source: .sectionAppeared,
        ))
        XCTAssertEqual(
            store.state.defaultFileViewerStatus,
            .otherIsDefault(appBundleID: "com.test.app", appDisplayName: "TestApp"),
        )
    }

    /// 진단 결과 unknown 매핑
    func testDiagnoseUnknown() async {
        let store = makeStore(diagnose: { .unknown })
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown, source: .sectionAppeared))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .unknown)
    }

    // MARK: - SET-010-set AC#1, AC#3, G5

    /// Finder → Voyager 전환 성공. 성공 후 자동 재진단으로 voyagerIsDefault 확정 (G5)
    func testSetAsDefaultSuccess() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .finderIsDefault : .voyagerIsDefault },
            setVoyagerAsDefault: {},
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerSucceeded)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .afterSetSucceeded))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .voyagerIsDefault)
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
    }

    /// 설정 진행 중 section 재등장은 진행 중인 mutation phase를 덮지 않는다.
    func testSectionAppearedIgnoredWhileSettingDefaultFileViewer() async {
        var state = GeneralSettingsFeature.State()
        state.defaultFileViewerPhase = .setting
        let store = makeStore(initialState: state)

        await store.send(.defaultFileViewerSectionAppeared)
        XCTAssertTrue(store.state.isSettingDefaultFileViewer)
    }

    // MARK: - SET-010-set AC#5: 실패 시 set_failed (Tests 6-8)

    /// permissionDenied 실패
    func testSetAsDefaultFailurePermissionDenied() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .finderIsDefault : .unknown },
            setVoyagerAsDefault: { throw FileOpError.system(message: "Permission denied") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.system(message: "Permission denied")))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown, source: .afterSetFailed))
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    /// systemError 실패
    func testSetAsDefaultFailureSystemError() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .finderIsDefault : .unknown },
            setVoyagerAsDefault: { throw FileOpError.system(message: "disk I/O") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.system(message: "disk I/O")))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown, source: .afterSetFailed))
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    /// system(LSHandler failed) 실패
    func testSetAsDefaultFailureSystemLSError() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .finderIsDefault : .unknown },
            setVoyagerAsDefault: { throw FileOpError.system(message: "LSHandler failed") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.system(message: "LSHandler failed")))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown, source: .afterSetFailed))
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    // MARK: - SET-010-restore AC#1, AC#2, G5

    /// Voyager → Finder 복원 성공. 성공 후 자동 재진단으로 finderIsDefault 확정 (G5)
    func testRestoreSuccess() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .voyagerIsDefault : .finderIsDefault },
            restoreFinder: {},
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .sectionAppeared))

        await store.send(.restoreDefaultFileViewerTapped)
        await store.receive(.restoreDefaultFileViewerSucceeded)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .afterRestoreSucceeded))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)
        XCTAssertFalse(store.state.isRestoringDefaultFileViewer)
    }

    /// 복구 진행 중 수동 진단은 진행 중인 mutation phase를 덮지 않는다.
    func testManualDiagnosisIgnoredWhileRestoringDefaultFileViewer() async {
        var state = GeneralSettingsFeature.State()
        state.defaultFileViewerPhase = .restoring
        let store = makeStore(initialState: state)

        await store.send(.defaultFileViewerDiagnoseRequested(.manual))
        XCTAssertTrue(store.state.isRestoringDefaultFileViewer)
    }

    // MARK: - SET-010-restore AC#4: 실패 시 restore_failed

    /// restore 실패
    func testRestoreFailure() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .voyagerIsDefault : .unknown },
            restoreFinder: { throw FileOpError.system(message: "LS API fail") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .sectionAppeared))

        await store.send(.restoreDefaultFileViewerTapped)
        await store.receive(.restoreDefaultFileViewerFailed(.system(message: "LS API fail")))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown, source: .afterRestoreFailed))
        XCTAssertFalse(store.state.isRestoringDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    // MARK: - P1 rollback: 부분 적용 방지

    /// SettingsHost 실행이어도 live client는 실제 Voyager bundle ID를 사용한다.
    func testLiveValueUsesVoyagerBundleID() {
        XCTAssertEqual(DefaultFileViewerClient.liveValue.appBundleID, DefaultFileViewerClient.voyagerBundleID)
    }

    /// 진단은 UserDefaults 캐시가 아니라 주입된 defaultsStore에서 NSFileViewer를 읽는다.
    func testDiagnoseReadsNSFileViewerFromDefaultsStore() async {
        let values = SET010DefaultsRecorder(initialValue: DefaultFileViewerClient.voyagerBundleID)
        let entryOpenClient = makeEntryOpenClient(
            defaultApplication: { _ in
                ApplicationInfo(
                    id: "voyager",
                    name: "Voyager",
                    bundleID: DefaultFileViewerClient.voyagerBundleID,
                )
            },
        )

        let status = await DefaultFileViewerLive.diagnose(
            appBundleID: DefaultFileViewerClient.voyagerBundleID,
            entryOpenClient: entryOpenClient,
            defaultsStore: values.store,
        )

        XCTAssertEqual(status, .voyagerIsDefault)
    }

    /// NSFileViewer 읽기 실패처럼 모르는 값이면 Finder LSHandler만으로 정상 복구 상태로 오진하지 않는다.
    func testDiagnoseUnknownWhenNSFileViewerReadIsIndeterminate() async {
        let values = SET010DefaultsRecorder(initialValue: "__read_failed__")
        let entryOpenClient = makeEntryOpenClient(
            defaultApplication: { _ in
                ApplicationInfo(id: "finder", name: "Finder", bundleID: "com.apple.finder")
            },
        )

        let status = await DefaultFileViewerLive.diagnose(
            appBundleID: DefaultFileViewerClient.voyagerBundleID,
            entryOpenClient: entryOpenClient,
            defaultsStore: values.store,
        )

        XCTAssertEqual(status, .unknown)
    }

    /// 수동 재진단이 정상 상태로 회복되면 stale 오류 배너를 지운다.
    func testDiagnosisCompletedClearsErrorWhenStatusRecovers() async {
        var initialState = GeneralSettingsFeature.State()
        initialState.defaultFileViewerPhase = .diagnosing(.manual)
        initialState.defaultFileViewerErrorMessage = "Permission denied"
        let store = makeStore(initialState: initialState)

        await store.send(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .manual)) {
            $0.defaultFileViewerPhase = .idle
            $0.defaultFileViewerStatus = .finderIsDefault
            $0.defaultFileViewerErrorMessage = nil
        }
    }

    /// set 실패 후 자동 재진단이 정상 상태를 읽어도 실패 배너를 유지한다.
    func testSetFailureFollowUpDiagnosisKeepsErrorWhenStatusStillHealthy() async {
        let store = makeStore(
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: { throw FileOpError.system(message: "Permission denied") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.system(message: "Permission denied")))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .afterSetFailed))
        XCTAssertEqual(store.state.defaultFileViewerErrorMessage, "Permission denied")
    }

    /// restore 실패 후 자동 재진단이 정상 상태를 읽어도 실패 배너를 유지한다.
    func testRestoreFailureFollowUpDiagnosisKeepsErrorWhenStatusStillHealthy() async {
        let store = makeStore(
            diagnose: { .voyagerIsDefault },
            restoreFinder: { throw FileOpError.system(message: "LS API fail") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .sectionAppeared))

        await store.send(.restoreDefaultFileViewerTapped)
        await store.receive(.restoreDefaultFileViewerFailed(.system(message: "LS API fail")))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .afterRestoreFailed))
        XCTAssertEqual(store.state.defaultFileViewerErrorMessage, "LS API fail")
    }

    /// LSHandler 실패 시 NSFileViewer write를 이전 값으로 롤백한다.
    func testSetAsDefaultRollsBackNSFileViewerWhenLSHandlerFails() async throws {
        let values = SET010DefaultsRecorder(initialValue: "com.apple.finder")
        let entryOpenClient = makeEntryOpenClient(
            setDefaultApp: { _, _ in throw FileOpError.system(message: "LSHandler failed") },
        )

        do {
            try await DefaultFileViewerLive.setVoyagerAsDefault(
                appBundleID: "fm.voyager.Voyager",
                entryOpenClient: entryOpenClient,
                defaultsStore: values.store,
            )
            XCTFail("Expected LSHandler failure")
        } catch let error as FileOpError {
            XCTAssertEqual(error, .system(message: "LSHandler failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(values.currentValue, "com.apple.finder")
        XCTAssertEqual(values.events, [.write("fm.voyager.Voyager"), .write("com.apple.finder")])
    }

    /// Finder 복구 중 LSHandler 실패 시 NSFileViewer delete를 이전 Voyager 값으로 롤백한다.
    func testRestoreFinderRollsBackNSFileViewerWhenLSHandlerFails() async throws {
        let values = SET010DefaultsRecorder(initialValue: "fm.voyager.Voyager")
        let entryOpenClient = makeEntryOpenClient(
            setDefaultApp: { _, _ in throw FileOpError.system(message: "LSHandler failed") },
        )

        do {
            try await DefaultFileViewerLive.restoreFinder(
                entryOpenClient: entryOpenClient,
                defaultsStore: values.store,
            )
            XCTFail("Expected LSHandler failure")
        } catch let error as FileOpError {
            XCTAssertEqual(error, .system(message: "LSHandler failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(values.currentValue, "fm.voyager.Voyager")
        XCTAssertEqual(values.events, [.delete, .write("fm.voyager.Voyager")])
    }

    /// 이전 NSFileViewer 읽기 실패 시 Voyager 설정은 전역 defaults를 건드리기 전에 중단한다.
    func testSetAsDefaultStopsBeforeMutationWhenNSFileViewerReadFails() async throws {
        let values = SET010DefaultsRecorder(initialValue: set010ReadFailedSentinel)
        let entryOpenClient = makeEntryOpenClient(
            setDefaultApp: { _, _ in throw FileOpError.system(message: "LSHandler failed") },
        )

        do {
            try await DefaultFileViewerLive.setVoyagerAsDefault(
                appBundleID: "fm.voyager.Voyager",
                entryOpenClient: entryOpenClient,
                defaultsStore: values.store,
            )
            XCTFail("Expected NSFileViewer read failure")
        } catch let error as FileOpError {
            XCTAssertEqual(error, .system(message: "Failed to read current default file viewer."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(values.events.isEmpty)
    }

    /// 이전 NSFileViewer 읽기 실패 시 Finder 복구도 전역 defaults를 건드리기 전에 중단한다.
    func testRestoreFinderStopsBeforeMutationWhenNSFileViewerReadFails() async throws {
        let values = SET010DefaultsRecorder(initialValue: set010ReadFailedSentinel)
        let entryOpenClient = makeEntryOpenClient(
            setDefaultApp: { _, _ in throw FileOpError.system(message: "LSHandler failed") },
        )

        do {
            try await DefaultFileViewerLive.restoreFinder(
                entryOpenClient: entryOpenClient,
                defaultsStore: values.store,
            )
            XCTFail("Expected NSFileViewer read failure")
        } catch let error as FileOpError {
            XCTAssertEqual(error, .system(message: "Failed to read current default file viewer."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(values.events.isEmpty)
    }

    // MARK: - 추가 AC 3: 진행 중 버튼 비활성화 (G4)

    /// isSetting=true일 때 두 번째 setAsDefaultFileViewerTapped는 no-op (G4)
    func testButtonDisableDuringSetProgress() async {
        let store = makeStore(
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: { try await Task.sleep(nanoseconds: 100_000_000) },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .sectionAppeared))

        await store.send(.setAsDefaultFileViewerTapped)
        // 두 번째 탭 — isSetting=true이므로 reducer가 guard로 무시해야 함 (G4)
        await store.send(.setAsDefaultFileViewerTapped)
    }

    /// isRestoring=true일 때 두 번째 restoreDefaultFileViewerTapped는 no-op (G4)
    func testButtonDisableDuringRestoreProgress() async {
        let store = makeStore(
            diagnose: { .voyagerIsDefault },
            restoreFinder: { try await Task.sleep(nanoseconds: 100_000_000) },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault, source: .sectionAppeared))

        await store.send(.restoreDefaultFileViewerTapped)
        // 두 번째 탭 — isRestoring=true이므로 reducer가 guard로 무시해야 함 (G4)
        await store.send(.restoreDefaultFileViewerTapped)
    }

    // MARK: - G16: unknown → retry만

    /// unknown 상태에서 "다시 확인" 버튼 → defaultFileViewerDiagnoseRequested → 재진단 (G16)
    func testUnknownStateRetryButton() async {
        let counter = SET010Counter()
        let store = makeStore(
            diagnose: { counter.next() == 1 ? .unknown : .finderIsDefault },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown, source: .sectionAppeared))

        await store.send(.defaultFileViewerDiagnoseRequested(.manual))
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault, source: .manual))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)
    }
}

private enum SET010DefaultsEvent: Equatable {
    case write(String)
    case delete
}

private final class SET010DefaultsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var recordedEvents: [SET010DefaultsEvent] = []

    init(initialValue: String?) {
        value = initialValue
    }

    var currentValue: String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    var events: [SET010DefaultsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    var store: DefaultFileViewerDefaultsStore {
        DefaultFileViewerDefaultsStore(
            read: { [weak self] in self?.currentValue },
            write: { [weak self] value in self?.write(value) },
            delete: { [weak self] in self?.delete() },
        )
    }

    private func write(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
        recordedEvents.append(.write(value))
    }

    private func delete() {
        lock.lock()
        defer { lock.unlock() }
        value = nil
        recordedEvents.append(.delete)
    }
}

private func makeEntryOpenClient(
    setDefaultApp: @escaping @Sendable (UTType, String) async throws -> Void = { _, _ in },
    defaultApplication: @escaping @Sendable (UTType) async -> ApplicationInfo? = { _ in nil },
) -> EntryOpenClient {
    EntryOpenClient(
        open: { _, _ in },
        setDefaultApp: setDefaultApp,
        openFinderInfo: { _ in },
        shareItems: { _, _ in },
        performService: { _, _ in },
        revealInFinder: { _ in },
        applicationsForFile: { _ in [] },
        defaultApplication: defaultApplication,
        trashDirectoryPath: { nil },
    )
}
