import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB003RequestPermissionsTests: XCTestCase {
    // MARK: - ONB-003-request_onboarding_permission_access

    // 사용자의 권한 요청 액션(FDA 활성화, 헬퍼 폴더 접근 요청, 로그인 시 실행 토글,
    // 시스템 설정 열기)이 올바른 Effect를 트리거하고, 그 결과가 State에
    // 반영되는지 검증합니다. Next 버튼의 게이팅 로직(FDA + 헬퍼 필수,
    // 로그인 시 실행 선택)도 이 그룹에서 확인합니다.

    /// ONB-003-request_onboarding_permission_access: FDA가 미충족일 때 progression을 평가하면 Next/Complete를 차단한다.
    /// FDA 상태에 따라 Next 버튼이 활성화·비활성화되는 게이팅 동작을 검증합니다.
    ///
    /// - 검증 내용: 헬퍼 폴더는 `kGrantedHelperAccess`로 통과하더라도
    ///   FDA가 `.needsAction`이면 nextDisabledMessage가 "Turn on Full Disk Access to continue."이고,
    ///   FDA가 `.granted`로 전환되면 nextDisabledMessage가 nil이 되고 isComplete == true가 됩니다.
    /// - 사전 조건: 의존성 기본값(모든 클라이언트 기본 구현).
    /// - 기대 결과: FDA `.needsAction` 시 Next 비활성화, FDA `.granted` 시 Next 활성화.
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

    /// ONB-003-request_onboarding_permission_access: FDA 요청 후 거부 상태가 유지될 때 응답을 처리하면 denied 상태와 blocking을 유지한다.
    /// 사용자가 시스템 설정 열기를 시도한 후 FDA가 여전히 거부 상태인 경우를 검증합니다.
    ///
    /// - 검증 내용: systemSettingsOpenResult(operationID, true)로 hasAttemptedFullDiskAccessEnable를 true로
    ///   설정한 후, fullDiskAccessStatusResponse(.needsAction)이 오면
    ///   fullDiskAccessStatus가 `.denied`로 처리됩니다.
    ///   사용자가 시도했으나 권한을 부여하지 않은 경우 `.needsAction` → `.denied` 전환을 보장합니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: fullDiskAccessStatus == `.denied`, isComplete == false.
    func testFullDiskAccessDeniedAfterAttempt() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        var initialState = PermissionsFeature.State()
        initialState.pendingFullDiskAccessOperationID = operationID
        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(operationID, true)) { state in
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

    /// ONB-003-request_onboarding_permission_access: 시스템 설정 열기가 실패할 때 FDA action을 실행하면 retry 가능한 error를 표시한다.
    /// 시스템 설정 열기 실패 시 에러 메시지가 표시되는지 검증합니다.
    ///
    /// - 검증 내용: systemSettingsOpenResult(operationID, false)가 반환되면 systemSettingsError에
    ///   "We couldn't open System Settings. Please open it manually." 메시지가 설정되고,
    ///   hasAttemptedFullDiskAccessEnable는 false로 유지됩니다.
    ///   시스템 설정 URL 열기 실패는 사용자 환경에서 발생할 수 있는 예외 상황입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: systemSettingsError != nil, hasAttemptedFullDiskAccessEnable == false.
    func testOpenSystemSettingsFailureShowsError() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        var initialState = PermissionsFeature.State()
        initialState.pendingFullDiskAccessOperationID = operationID
        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(operationID, false)) { state in
            state.systemSettingsError = "We couldn't open System Settings. Please open it manually."
            state.hasAttemptedFullDiskAccessEnable = false
        }

        await store.finish()
    }

    /// ONB-003-request_onboarding_permission_access: launch-at-login 토글 요청이 성공할 때 action을 실행하면 non-gate 설정 상태만 갱신한다.
    /// 로그인 시 실행 토글이 성공적으로 상태를 갱신하는지 검증합니다 (비게이팅 권한).
    ///
    /// - 검증 내용: launchAtLoginToggled(true)가 launchAtLoginEnabled를 true로 설정하고
    ///   launchAtLoginUpdateSucceeded를 수신합니다. 로그인 시 실행은 필수 권한이 아니므로
    ///   토글 결과가 isComplete에 영향을 주지 않습니다.
    /// - 사전 조건: launchAtLoginClient isEnabled = false, setEnabled 성공.
    /// - 기대 결과: launchAtLoginEnabled == true, launchAtLoginError == nil.
    func testLaunchAtLoginToggleSuccess() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = PermissionClients.disabledLaunchAtLogin
        }

        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
            state.launchAtLoginError = nil
        }

        await store.receive(\.launchAtLoginUpdateSucceeded)

        XCTAssertNil(store.state.launchAtLoginError)
        await store.finish()
    }

    /// ONB-003-request_onboarding_permission_access: launch-at-login 토글 요청이 실패할 때 action을 실행하면 필수 권한 completion과 분리된
    /// error를 표시한다.
    /// 로그인 시 실행 토글 실패 시 에러 복구 동작을 검증합니다 (비게이팅 권한).
    ///
    /// - 검증 내용: setEnabled가 TestError를 throw하면 launchAtLoginUpdateFailed를 수신하고,
    ///   launchAtLoginEnabled가 false로 롤백되며, launchAtLoginError에 안내 메시지가 설정됩니다.
    ///   실패 시 상태 롤백은 사용자에게 일관된 UI를 제공하기 위해 중요합니다.
    /// - 사전 조건: launchAtLoginClient setEnabled가 TestError()를 throw.
    /// - 기대 결과: launchAtLoginEnabled == false, launchAtLoginError != nil.
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

    /// ONB-003-request_onboarding_permission_access: 사용자가 FDA 설정 열기를 선택할 때 action을 실행하면 system settings client 호출을
    /// 보장한다.
    /// openSystemSettingsTapped이 systemSettingsClient를 호출하는지 검증합니다.
    ///
    /// - 검증 내용: openSystemSettingsTapped 액션이 systemSettingsClient.openFullDiskAccess를
    ///   호출하고, 성공 결과로 systemSettingsOpenResult를 수신하며
    ///   hasAttemptedFullDiskAccessEnable가 true로 설정됩니다.
    /// - 사전 조건: systemSettingsClient openFullDiskAccess가 true 반환.
    /// - 기대 결과: hasAttemptedFullDiskAccessEnable == true.
    func testOpenSystemSettingsTappedCallsSystemSettingsClient() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: { true })
            $0.uuid = .constant(operationID)
        }

        await store.send(.openSystemSettingsTapped)
        await store.receive(\.systemSettingsOpenResult) { state in
            state.pendingFullDiskAccessOperationID = operationID
            state.hasAttemptedFullDiskAccessEnable = true
        }
        await store.finish()
    }

    /// ONB-003-request_onboarding_permission_access: FDA 설정 열기 요청이 pending일 때 두 번째 탭을 보내도 첫 요청만 유지한다.
    /// 중복 탭이 시스템 설정 열기 client를 재호출하거나 첫 correlation ID를 덮어쓰지 않는지 검증합니다.
    ///
    /// - 검증 내용: 첫 요청의 UUID를 주입하고 성공 결과를 받은 뒤 두 번째 탭을 전송합니다.
    /// - 사전 조건: 첫 FDA 설정 열기 요청이 성공했고 성공 결과가 pending 상태를 유지합니다.
    /// - 기대 결과: client 호출은 1회이고 pending ID는 첫 요청 UUID입니다.
    func testOpenSystemSettingsTappedIgnoresSecondTapWhilePending() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let openCount = LockIsolated(0)
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: {
                openCount.withValue { $0 += 1 }
                return true
            })
        }

        await store.send(.openSystemSettingsTapped)
        await store.receive(\.systemSettingsOpenResult) { state in
            state.hasAttemptedFullDiskAccessEnable = true
        }
        await store.send(.openSystemSettingsTapped)

        XCTAssertEqual(openCount.value, 1)
        XCTAssertEqual(store.state.pendingFullDiskAccessOperationID, operationID)
        await store.finish()
    }

    /// ONB-003-request_onboarding_permission_access: helper folder 요청이 성공할 때 request action을 실행하면 helper access를
    /// granted로 저장하고 completion을 갱신한다.
    /// 헬퍼 폴더 접근 요청이 성공하여 isComplete가 true가 되는 흐름을 검증합니다.
    ///
    /// - 검증 내용: FDA가 이미 `.granted`인 상태에서 requestHelperFolderAccessTapped이
    ///   `kGrantedHelperAccess`를 반환하면, isRequestingHelperFolderAccess가 false로 돌아가고
    ///   isComplete가 true가 됩니다.
    /// - 사전 조건: initialState.fullDiskAccessStatus = `.granted`,
    ///   헬퍼 폴더 `kGrantedHelperAccess`.
    /// - 기대 결과: isRequestingHelperFolderAccess == false, isComplete == true,
    ///   helperFolderAccessError == nil.
    func testRequestHelperFolderAccessTappedSucceeds() async {
        var initialState = PermissionsFeature.State()
        initialState.fullDiskAccessStatus = .granted

        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
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

    /// ONB-003-request_onboarding_permission_access: helper folder 요청이 partial을 반환할 때 응답을 처리하면 partial 상태와 blocking을
    /// 유지한다.
    /// 헬퍼 폴더 접근 요청이 부분 허용 결과를 반환하는 경우 에러 메시지와 isComplete를 검증합니다.
    ///
    /// - 검증 내용: desktop만 `.granted`이고 documents·downloads는 `.notGranted`인 부분 접근에서
    ///   helperFolderAccessError에 "VoyagerHelper still needs Desktop, Documents, and Downloads access."
    ///   메시지가 설정되고, isComplete는 false입니다.
    ///   부분 접근은 전체 허용으로 간주되지 않아 사용자에게 추가 조치가 필요합니다.
    /// - 사전 조건: 헬퍼 폴더 desktop=`.granted`, documents=`.notGranted`, downloads=`.notGranted`.
    /// - 기대 결과: isComplete == false, helperFolderAccessError != nil.
    func testRequestHelperFolderAccessTappedReturnsPartial() async {
        let partialAccess = FolderAccessResult(
            desktop: .granted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.helperFolderAccessClient = PermissionClients.deniedHelper(partialAccess)
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

    /// ONB-003-request_onboarding_permission_access: FDA가 denied일 때 Next 가능 여부를 계산하면 progression을 차단한다.
    /// FDA가 명시적으로 `.denied`일 때 Next 버튼이 비활성화됨을 검증합니다.
    ///
    /// - 검증 내용: fullDiskAccessStatusResponse(.denied)를 보내면
    ///   nextDisabledMessage가 "Turn on Full Disk Access to continue."이고
    ///   isComplete가 false입니다. `.denied`는 사용자가 의도적으로 권한을 거부한 상태입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: nextDisabledMessage != nil, isComplete == false.
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

    /// ONB-003-request_onboarding_permission_access: helper access가 notGranted일 때 Next 가능 여부를 계산하면 progression을 차단한다.
    /// 헬퍼 폴더 접근이 미허용일 때 FDA가 허용되더라도 Next가 비활성화됨을 검증합니다.
    ///
    /// - 검증 내용: FDA가 `.granted`이더라도 헬퍼 폴더가 전체 `.notGranted`이면
    ///   nextDisabledMessage가 "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue."
    ///   이고 isComplete == false입니다. 헬퍼 접근은 FDA와 별개의 필수 권한입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: nextDisabledMessage에 헬퍼 접근 안내 메시지, isComplete == false.
    func testHelperAccessBlocksNextWhenNotGranted() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.send(.helperFolderAccessStatusLoaded(kDeniedHelperAccess))

        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue.",
        )
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ONB-003-request_onboarding_permission_access: 필수 권한은 충족되고 launch-at-login만 disabled일 때 progression을 계산하면 Next를
    /// 차단하지 않는다.
    /// 로그인 시 실행이 비활성화되어도 Next를 차단하지 않음을 검증합니다.
    ///
    /// - 검증 내용: FDA `.granted` + 헬퍼 `kGrantedHelperAccess` + 로그인 시 실행 false 조합에서
    ///   isComplete가 true이고 nextDisabledMessage가 nil입니다.
    ///   로그인 시 실행은 권장 사항이며 필수 권한이 아닙니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: isComplete == true, nextDisabledMessage == nil.
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

    /// ONB-003-request_onboarding_permission_access: FDA가 denied였다가 granted로 바뀔 때 사용자가 retry/refresh하면 completion을
    /// 회복한다.
    /// FDA 권한이 거부에서 허용으로 전환되는 재시도 성공 시나리오를 검증합니다.
    ///
    /// - 검증 내용: systemSettingsOpenResult(operationID, true)로 시도 기록 후
    ///   fullDiskAccessStatusResponse(.needsAction)에서 `.denied`로 처리되고,
    ///   이후 fullDiskAccessStatusResponse(.granted)에서 권한이 허용으로 전환됩니다.
    ///   단, 헬퍼 접근 상태가 아직 로드되지 않았으므로 nextDisabledMessage는 여전히 존재합니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: 최종 fullDiskAccessStatus == `.granted`, nextDisabledMessage != nil
    ///   (헬퍼 상태 미확정으로 인해).
    func testFDARetryFromDeniedToGranted() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        var initialState = PermissionsFeature.State()
        initialState.pendingFullDiskAccessOperationID = operationID
        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(operationID, true)) { state in
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

    /// ONB-003-request_onboarding_permission_access: launch-at-login 상태가 false일 때 필수 권한이 충족되면 completion gate에 영향을 주지
    /// 않는다.
    /// 로그인 시 실행 토글이 isComplete에 영향을 주지 않음을 검증합니다.
    ///
    /// - 검증 내용: FDA `.granted` + 헬퍼 `kGrantedHelperAccess`로 isComplete가 true가 된 후,
    ///   launchAtLoginToggled을 켜고 꺼도 isComplete가 true로 유지됩니다.
    ///   로그인 시 실행은 필수 권한이 아니므로 온보딩 완료 여부와 무관합니다.
    /// - 사전 조건: launchAtLoginClient isEnabled = false, setEnabled 성공.
    /// - 기대 결과: 토글 on/off 후에도 isComplete == true 유지.
    func testLaunchAtLoginDoesNotGateCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = PermissionClients.disabledLaunchAtLogin
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

        // 로그인 시 실행 토글 on/off → isComplete true 유지 (비게이팅 권한이므로 영향 없음)
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

    /// ONB-003-request_onboarding_permission_access: launch-at-login만 미충족/disabled일 때 FDA/helper가 충족되면 completion을
    /// 허용한다.
    /// 필수 권한(FDA + 헬퍼) 충족 시 로그인 시 실행이 비활성화되어도 isComplete == true임을 검증합니다.
    ///
    /// - 검증 내용: onAppear가 FDA `.granted` + 헬퍼 `kGrantedHelperAccess` + 로그인 시 실행 false를
    ///   로드하면 isComplete == true, nextDisabledMessage == nil, launchAtLoginEnabled == false입니다.
    ///   이는 로그인 시 실행이 온보딩 완료를 차단하지 않음을 종단 간(end-to-end)으로 보여줍니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 `kGrantedHelperAccess`, 로그인 시 실행 비활성화.
    /// - 기대 결과: isComplete == true, launchAtLoginEnabled == false, nextDisabledMessage == nil.
    func testLaunchAtLoginNonGateDoesNotBlockCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            PermissionClients.allGranted(&$0)
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

        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.launchAtLoginEnabled)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }
}
