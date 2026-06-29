import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

// SET-010-set_default_file_viewer / SET-010-restore_default_file_viewer 증거 계약.
// 기본 파일 뷰어 진단 상태 매핑, Finder ↔ Voyager 전환 성공/실패, 진행 중 버튼 비활성화(G4),
// 성공 후 자동 재진단(G5), unknown 상태에서 "다시 확인" 버튼(G16)을 검증한다.

/// 비동기 테스트용 호출 카운터
final class SET010Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        n += 1
        return n
    }
}

@MainActor
final class SET010DefaultFileViewerSettingsTests: XCTestCase {
    nonisolated(unsafe) private var storage: InMemoryStorage!

    override func setUp() {
        super.setUp()
        storage = InMemoryStorage()
    }

    override func tearDown() {
        storage = nil
        super.tearDown()
    }

    private func makeStore(
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
        // swiftlint:disable:next force_unwrapping
        let storage = storage!
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
            appBundleID: "fm.voyager.Voyager",
            diagnose: diagnose,
            setVoyagerAsDefault: setVoyagerAsDefault,
            restoreFinder: restoreFinder,
        )
        return TestStore(initialState: GeneralSettingsFeature.State()) {
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
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .voyagerIsDefault)
    }

    /// 진단 결과 finderIsDefault 매핑
    func testDiagnoseFinderIsDefault() async {
        let store = makeStore(diagnose: { .finderIsDefault })
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)
    }

    /// 진단 결과 otherIsDefault 매핑
    func testDiagnoseOtherIsDefault() async {
        let store = makeStore(diagnose: { .otherIsDefault(appBundleID: "com.test.app", appDisplayName: "TestApp") })
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.otherIsDefault(
            appBundleID: "com.test.app",
            appDisplayName: "TestApp",
        )))
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
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown))
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
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerSucceeded)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .voyagerIsDefault)
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
    }

    // MARK: - SET-010-set AC#5: 실패 시 set_failed (Tests 6-8)

    /// permissionDenied 실패
    func testSetAsDefaultFailurePermissionDenied() async {
        let store = makeStore(
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: { throw DefaultFileViewerError.permissionDenied },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.permissionDenied))
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    /// systemError 실패
    func testSetAsDefaultFailureSystemError() async {
        let store = makeStore(
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: { throw DefaultFileViewerError.systemError("disk I/O") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.systemError("disk I/O")))
        XCTAssertFalse(store.state.isSettingDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    /// partialWrite 실패
    func testSetAsDefaultFailurePartialWrite() async {
        let store = makeStore(
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: { throw DefaultFileViewerError.partialWrite(message: "LSHandler failed") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))

        await store.send(.setAsDefaultFileViewerTapped)
        await store.receive(.setAsDefaultFileViewerFailed(.partialWrite(message: "LSHandler failed")))
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
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault))

        await store.send(.restoreDefaultFileViewerTapped)
        await store.receive(.restoreDefaultFileViewerSucceeded)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)
        XCTAssertFalse(store.state.isRestoringDefaultFileViewer)
    }

    // MARK: - SET-010-restore AC#4: 실패 시 restore_failed

    /// restore 실패
    func testRestoreFailure() async {
        let store = makeStore(
            diagnose: { .voyagerIsDefault },
            restoreFinder: { throw DefaultFileViewerError.systemError("LS API fail") },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault))

        await store.send(.restoreDefaultFileViewerTapped)
        await store.receive(.restoreDefaultFileViewerFailed(.systemError("LS API fail")))
        XCTAssertFalse(store.state.isRestoringDefaultFileViewer)
        XCTAssertNotNil(store.state.defaultFileViewerErrorMessage)
    }

    // MARK: - 추가 AC 3: 진행 중 버튼 비활성화 (G4) (Tests 11-12)

    /// isSetting=true일 때 두 번째 setAsDefaultFileViewerTapped는 no-op (G4)
    func testButtonDisableDuringSetProgress() async {
        let store = makeStore(
            diagnose: { .finderIsDefault },
            setVoyagerAsDefault: { try await Task.sleep(nanoseconds: 100_000_000) },
        )
        store.exhaustivity = .off
        await store.send(.defaultFileViewerSectionAppeared)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))

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
        await store.receive(.defaultFileViewerDiagnosisCompleted(.voyagerIsDefault))

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
        await store.receive(.defaultFileViewerDiagnosisCompleted(.unknown))

        await store.send(.defaultFileViewerDiagnoseRequested)
        await store.receive(.defaultFileViewerDiagnosisCompleted(.finderIsDefault))
        XCTAssertEqual(store.state.defaultFileViewerStatus, .finderIsDefault)
    }
}
