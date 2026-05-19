// swiftlint:disable file_length
import Foundation

import ComposableArchitecture
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import XCTest

// swiftlint:disable type_name
// swiftlint:disable type_body_length
@MainActor
final class ONB003ConfigureRequiredPermissionsFeatureTests: XCTestCase {
    // swiftlint:enable type_name
    // MARK: - ONB-003-show_onboarding_permission_status

    /// onAppear 시 초기 권한 상태 표시를 검증합니다.
    func testOnAppearLoadsHelperFolderAccessStatus() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.receive(\.launchAtLoginStateLoaded)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// FDA 상태가 unknown일 때의 초기 상태를 검증합니다.
    func testOnAppearWithFDAUnknownShowsNeedsAction() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .unknown })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse)
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
        }
        await store.receive(\.launchAtLoginStateLoaded)

        XCTAssertNotNil(store.state.nextDisabledMessage)
        XCTAssertEqual(store.state.fullDiskAccessStatus, .unknown)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// 헬퍼 폴더 접근이 부분적으로 허용된 상태 표시를 검증합니다.
    func testOnAppearWithPartialHelperAccessShowsPartial() async {
        let partialAccess = FolderAccessResult(
            desktop: .granted,
            documents: .granted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { partialAccess },
                requestAccess: { partialAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = partialAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }
        await store.receive(\.launchAtLoginStateLoaded)

        XCTAssertEqual(store.state.helperFolderAccessStatus, .partial)
        XCTAssertTrue(store.state.showsHelperFolderAccessAction)
        XCTAssertFalse(store.state.isComplete)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// 모든 권한이 거부되었을 때의 상태 표시를 검증합니다.
    func testOnAppearWithAllDeniedShowsCorrectStatus() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .denied })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { deniedAccess },
                requestAccess: { deniedAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .denied
        }
        await store.receive(\.helperFolderAccessStatusLoaded)
        await store.receive(\.launchAtLoginStateLoaded)

        XCTAssertEqual(store.state.fullDiskAccessStatus, .denied)
        XCTAssertEqual(store.state.helperFolderAccessStatus, .notGranted)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// RED: 초기 상태 → FDA와 헬퍼 접근 모두 허용될 때까지 isComplete가 false로 유지됩니다.
    func testInitialStatusIsNotCompleteUntilAllChecksPass() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .needsAction })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }
        await store.receive(\.launchAtLoginStateLoaded)

        // FDA 미허용 → isComplete가 false로 유지됨
        XCTAssertFalse(store.state.isComplete)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// RED: 일부 폴더의 헬퍼 접근이 허용되지 않음 → isComplete가 false로 유지됩니다.
    func testHelperFolderAccessDeniedBlocksCompletion() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { deniedAccess },
                requestAccess: { deniedAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.receive(\.helperFolderAccessStatusLoaded)
        await store.receive(\.launchAtLoginStateLoaded)

        // FDA 허용됨, 헬퍼 거부됨 → isComplete 여전히 false
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }

    // MARK: - ONB-003-refresh_onboarding_permission_status

    /// disappear 시 옵저데이션 수명 주기 정리를 검증합니다.
    func testOnDisappearCancelsAppActiveObservation() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .unknown })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse)
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
        }
        await store.receive(\.launchAtLoginStateLoaded)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// 앱 활성화 시 상태 새로고침을 검증합니다.
    func testAppDidBecomeActiveRefreshesHelperFolderAccessStatus() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.finish()
    }

    /// FDA 허용 후 새로고침 시 isComplete가 올바르게 갱신됨을 검증합니다.
    func testRefreshAfterFDAGrantMarksComplete() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }

        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    /// 헬퍼 폴더 접근 상태가 거부로 변경된 후 새로고침을 검증합니다.
    func testRefreshAfterHelperFolderAccessChangeUpdatesStatus() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { deniedAccess },
                requestAccess: { deniedAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.receive(\.helperFolderAccessStatusLoaded)

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.helperFolderAccessStatus, .notGranted)
        await store.finish()
    }

    /// 새로고침 시 로그인 시 실행 상태가 초기화되지 않음을 검증합니다.
    func testRefreshDoesNotResetLaunchAtLoginState() async {
        var initialState = PermissionsFeature.State()
        initialState.launchAtLoginEnabled = true

        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.isComplete = true
        }

        XCTAssertTrue(store.state.launchAtLoginEnabled)
        await store.finish()
    }

    /// RED: 초기 needsAction → 새로고침 후 .granted 반환 → isComplete가 true로 전환됩니다.
    func testRefreshAfterGrantingFDAClearsErrorAndCompletes() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        // 시드: FDA = needsAction, 헬퍼 = granted → 미완료
        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }
        XCTAssertFalse(store.state.isComplete)

        // 새로고침: FDA 이제 허용됨
        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }

        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.finish()
    }

    // MARK: - ONB-003-request_onboarding_permission_access

    /// Next 버튼에 대한 FDA 게이팅 동작을 검증합니다.
    func testFullDiskAccessGatesNext() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }

        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }

        XCTAssertEqual(store.state.nextDisabledMessage, "Turn on Full Disk Access to continue.")

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = true
        }

        XCTAssertNil(store.state.nextDisabledMessage)
        await store.finish()
    }

    /// 사용자가 활성화를 시도한 후 FDA 거부 상태를 검증합니다.
    func testFullDiskAccessDeniedAfterAttempt() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(true)) { state in
            state.systemSettingsError = nil
            state.hasAttemptedFullDiskAccessEnable = true
        }

        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .denied
            state.isComplete = false
        }

        XCTAssertEqual(store.state.fullDiskAccessStatus, .denied)
        await store.finish()
    }

    /// 시스템 설정 열기 실패 시 에러 표시를 검증합니다.
    func testOpenSystemSettingsFailureShowsError() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(false)) { state in
            state.systemSettingsError = "We couldn't open System Settings. Please open it manually."
            state.hasAttemptedFullDiskAccessEnable = false
        }

        await store.finish()
    }

    /// 로그인 시 실행 토글 성공을 검증합니다 (비게이팅 권한).
    func testLaunchAtLoginToggleSuccess() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
            state.launchAtLoginError = nil
        }

        await store.receive(\.launchAtLoginUpdateSucceeded)

        XCTAssertNil(store.state.launchAtLoginError)
        await store.finish()
    }

    /// 로그인 시 실행 토글 실패를 검증합니다 (비게이팅 권한).
    func testLaunchAtLoginToggleFailure() async {
        struct TestError: Error {}

        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in
                throw TestError()
            })
        }

        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
            state.launchAtLoginError = nil
        }

        await store.receive(\.launchAtLoginUpdateFailed) { state in
            state.launchAtLoginEnabled = false
            state.launchAtLoginError =
                "We couldn't update your Login Items. Manage this in System Settings."
        }

        await store.finish()
    }

    /// FDA 요청이 시스템 설정을 여는지 검증합니다.
    func testOpenSystemSettingsTappedCallsSystemSettingsClient() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: { true })
        }

        await store.send(.openSystemSettingsTapped)
        await store.receive(\.systemSettingsOpenResult) { state in
            state.hasAttemptedFullDiskAccessEnable = true
        }
        await store.finish()
    }

    /// 헬퍼 폴더 접근 요청 흐름을 검증합니다.
    func testRequestHelperFolderAccessTappedSucceeds() async {
        var initialState = PermissionsFeature.State()
        initialState.fullDiskAccessStatus = .granted

        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.requestHelperFolderAccessTapped) { state in
            state.isRequestingHelperFolderAccess = true
        }
        await store.receive(\.helperFolderAccessResponse) { state in
            state.isRequestingHelperFolderAccess = false
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.finish()
    }

    /// 헬퍼 폴더 접근 요청이 부분 허용 결과를 반환하는 경우를 검증합니다.
    func testRequestHelperFolderAccessTappedReturnsPartial() async {
        let partialAccess = FolderAccessResult(
            desktop: .granted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { partialAccess },
                requestAccess: { partialAccess },
            )
        }

        await store.send(.requestHelperFolderAccessTapped) { state in
            state.helperFolderAccessError = nil
            state.isRequestingHelperFolderAccess = true
        }
        await store.receive(\.helperFolderAccessResponse) { state in
            state.isRequestingHelperFolderAccess = false
            state.helperFolderAccess = partialAccess
            state.helperFolderAccessError =
                "VoyagerHelper still needs Desktop, Documents, and Downloads access."
            state.isComplete = false
        }

        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.helperFolderAccessError)
        await store.finish()
    }

    /// FDA 거부 시 Next 버튼이 비활성화됨을 검증합니다.
    func testFDABlocksNextWhenDenied() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.denied)) { state in
            state.fullDiskAccessStatus = .denied
            state.isComplete = false
        }

        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Turn on Full Disk Access to continue.",
        )
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// 헬퍼 접근 미허용 시 Next 버튼이 비활성화됨을 검증합니다.
    func testHelperAccessBlocksNextWhenNotGranted() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.send(.helperFolderAccessStatusLoaded(deniedAccess))

        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue.",
        )
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// 로그인 시 실행이 Next를 차단하지 않음을 검증합니다.
    func testLaunchAtLoginDoesNotBlockNextWhenDisabled() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.isComplete = true
        }
        await store.send(.launchAtLoginStateLoaded(false))

        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.nextDisabledMessage)
        await store.finish()
    }

    /// FDA 요청이 거부에서 허용으로 전환됨을 검증합니다 (재시도 성공).
    func testFDARetryFromDeniedToGranted() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(true)) { state in
            state.hasAttemptedFullDiskAccessEnable = true
        }
        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .denied
            state.isComplete = false
        }

        XCTAssertEqual(store.state.fullDiskAccessStatus, .denied)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }

        XCTAssertNotNil(store.state.nextDisabledMessage)
        await store.finish()
    }

    /// 로그인 시 실행 토글이 isComplete에 영향을 주지 않음을 검증합니다.
    func testLaunchAtLoginDoesNotGateCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = true
        }

        // 로그인 시 실행 토글 → isComplete true 유지
        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
        }
        await store.receive(\.launchAtLoginUpdateSucceeded)
        XCTAssertTrue(store.state.isComplete)

        await store.send(.launchAtLoginToggled(false)) { state in
            state.launchAtLoginEnabled = false
        }
        await store.receive(\.launchAtLoginUpdateSucceeded)
        XCTAssertTrue(store.state.isComplete)

        await store.finish()
    }

    /// RED: FDA = needsAction, 헬퍼 = granted → nextDisabledMessage가 non-nil입니다.
    func testFDARequiredGateBlocksNextButton() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }

        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }

        XCTAssertEqual(store.state.nextDisabledMessage, "Turn on Full Disk Access to continue.")
        XCTAssertFalse(store.state.isComplete)

        await store.finish()
    }

    /// RED: 헬퍼 미허용 → FDA가 허용되어도 차단됩니다.
    func testHelperFolderAccessRequiredGateBlocksNext() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }

        await store.send(.helperFolderAccessStatusLoaded(deniedAccess))

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue.",
        )

        await store.finish()
    }

    /// RED: FDA 허용 + 헬퍼 허용 + 로그인 시 실행 비활성화 → isComplete = true.
    func testLaunchAtLoginNonGateDoesNotBlockCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.receive(\.launchAtLoginStateLoaded)

        // 로그인 시 실행 비활성화, 필수 권한 모두 허용 → 완료
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.launchAtLoginEnabled)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }
    // swiftlint:enable type_body_length
}

// swiftlint:enable file_length
