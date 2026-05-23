import Foundation

import ComposableArchitecture
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import XCTest

// MARK: - ONB-003 Test Fixtures

private let kGrantedHelperAccess = FolderAccessResult(
    desktop: .granted,
    documents: .granted,
    downloads: .granted,
)

@MainActor
final class ONB003ConfigureRequiredPermissionsFeatureTests: XCTestCase {
    // MARK: - ONB-003-show_onboarding_permission_status

    // 온보딩 권한 구성 화면(ONB-003)의 첫 번째 스펙 인터랙션입니다.
    // 사용자가 권한 설정 화면에 진입(onAppear)했을 때 리듀서가 세 가지 권한의 현재 상태를
    // 병렬로 수집하여 State에 반영하는 흐름을 검증합니다.
    // 대상 권한: Full Disk Access(FDA), 헬퍼 폴더 접근(Desktop/Documents/Downloads),
    // 로그인 시 실행(LaunchAtLogin).

    /// ONB-003:show_onboarding_permission_status — 권한 step이 표시될 때 onAppear가 실행되면 FDA/helper/launch 상태를 수집하고 필수 권한 완료
    /// 여부를 계산한다.
    /// ONB-003-show_onboarding_permission_status 스펙에서 onAppear 시 권한 상태를 병렬로 수집하는 흐름을 검증합니다.
    ///
    /// 리듀서가 onAppear를 받으면 세 개의 이펙트(FDA 상태, 헬퍼 폴더 접근 상태, 로그인 항목 상태)를
    /// 동시에 시작하고, 각 결과 액션을 순차적으로 수신하여 State를 갱신합니다.
    ///
    /// - 사전 조건: FDA는 `.granted`(허용됨), 헬퍼 폴더 접근은 `kGrantedHelperAccess`
    ///   (Desktop·Documents·Downloads 모두 허용), 로그인 시 실행은 비활성화(`false`).
    ///   로그인 항목은 비게이팅 권한이므로 FDA와 헬퍼 접근만으로 완료 판정이 납니다.
    /// - 검증 액션: `onAppear` → FDA 응답 → 헬퍼 응답 → 로그인 항목 응답 순으로 수신.
    /// - 기대 결과: `fullDiskAccessStatusResponse(.granted)` 수신 후 `isComplete`는 여전히 `false`
    ///   (헬퍼 접근 결과 미수신). `helperFolderAccessStatusLoaded` 수신 후 `helperFolderAccessError`는
    ///   `nil`이 되고 `isComplete == true`. `launchAtLoginStateLoaded`는 추가로 수신되지만
    ///   `isComplete`에는 영향을 주지 않습니다.
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

    /// ONB-003:show_onboarding_permission_status — FDA가 unknown일 때 권한 상태를 표시하면 Next를 차단하고 사용자 조치를 요구한다.
    /// ONB-003-show_onboarding_permission_status: FDA가 `.unknown`일 때 온보딩 완료가 차단되는지 검증합니다.
    ///
    /// macOS는 FDA 권한을 허용/거부/미확인 세 가지로 보고합니다. `.unknown`은 사용자가 아직
    /// 시스템 설정에서 권한을 부여하지 않은 초기 상태로, 리듀서는 이를 사실상 거부와 동일하게
    /// 취급하여 Next 버튼을 비활성화합니다.
    ///
    /// - 사전 조건: FDA는 `.unknown`(미확인), 헬퍼 폴더 접근은 `kGrantedHelperAccess`(모두 허용),
    ///   로그인 시 실행은 비활성화. 헬퍼 접근만으로는 완료 판정이 나지 않습니다.
    /// - 검증 액션: `onAppear` → 세 응답 순차 수신. FDA 응답은 상태 변경 없이
    ///   `fullDiskAccessStatus`가 `.unknown`으로 유지됩니다.
    /// - 기대 결과: `nextDisabledMessage`가 non-nil이 되어 Next 버튼이 비활성화.
    ///   `fullDiskAccessStatus == .unknown` 유지. `isComplete`는 헬퍼 접근이 허용되었더라도
    ///   FDA 미확정으로 인해 최종 완료가 아닙니다.
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

    /// ONB-003:show_onboarding_permission_status — helper folder access가 부분 허용일 때 상태를 표시하면 partial 상태와 추가 action 필요성을
    /// 노출한다.
    /// 헬퍼 폴더 접근이 부분적으로 허용된 상태에서 isComplete가 false임을 검증합니다.
    ///
    /// - 검증 내용: Desktop·Documents는 허용, Downloads는 미허용인 부분 접근 상태에서
    ///   helperFolderAccessStatus가 `.partial`로 분류되고, isComplete가 false가 됩니다.
    ///   부분 접근은 전체 허용과 동일하게 취급되지 않으며, 사용자에게 추가 조치를 안내해야 합니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 desktop=`.granted`, documents=`.granted`,
    ///   downloads=`.notGranted`, 로그인 시 실행 비활성화.
    /// - 기대 결과: helperFolderAccessStatus == `.partial`, showsHelperFolderAccessAction == true,
    ///   isComplete == false. 세 폴더 모두 허용되어야만 완료 처리됩니다.
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

    /// ONB-003:show_onboarding_permission_status — FDA/helper가 모두 미충족일 때 상태를 표시하면 denied/notGranted 상태와 progression
    /// blocking을 노출한다.
    /// 모든 권한이 거부된 최악의 시나리오에서 올바른 상태 표시를 검증합니다.
    ///
    /// - 검증 내용: FDA `.denied` + 헬퍼 폴더 전체 `.notGranted` 조합에서
    ///   모든 권한이 미충족되었음을 정확히 반영하는지 확인합니다.
    ///   이 상태는 사용자가 처음 온보딩을 시작하면서 아무런 시스템 권한도 부여하지 않은 경우에 해당합니다.
    /// - 사전 조건: FDA `.denied`, 헬퍼 폴더 desktop·documents·downloads 모두 `.notGranted`,
    ///   로그인 시 실행 비활성화.
    /// - 기대 결과: fullDiskAccessStatus == `.denied`, helperFolderAccessStatus == `.notGranted`,
    ///   isComplete == false, nextDisabledMessage가 non-nil (Next 버튼 비활성화).
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

    /// ONB-003:show_onboarding_permission_status — 필수 권한 중 하나라도 미충족일 때 초기 상태를 계산하면 isComplete를 false로 유지한다.
    /// FDA 미허용 상태에서는 헬퍼 접근이 허용되더라도 isComplete가 false임을 검증합니다.
    ///
    /// - 검증 내용: 헬퍼 폴더 접근은 `kGrantedHelperAccess`로 통과하더라도
    ///   FDA가 `.needsAction`이면 isComplete는 false여야 합니다.
    ///   FDA는 선행 필수 권한이므로, FDA 없이는 다른 권한 통과가 의미 없습니다.
    /// - 사전 조건: FDA `.needsAction`, 헬퍼 폴더 `kGrantedHelperAccess`, 로그인 시 실행 비활성화.
    /// - 기대 결과: fullDiskAccessStatusResponse 수신 후 isComplete == false,
    ///   helperFolderAccessStatusLoaded 수신 후에도 isComplete == false 유지.
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

        // FDA가 needsAction이므로 헬퍼가 허용 상태여도 isComplete는 false여야 함
        XCTAssertFalse(store.state.isComplete)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// ONB-003:show_onboarding_permission_status — FDA는 허용됐지만 helper 접근이 거부됐을 때 상태를 계산하면 completion을 차단한다.
    /// FDA 허용 상태에서 헬퍼 폴더 접근 거부 시 isComplete가 차단됨을 검증합니다.
    ///
    /// - 검증 내용: FDA는 `.granted`이더라도 헬퍼 폴더 접근이 전체 거부되면
    ///   isComplete는 false이고 nextDisabledMessage가 존재합니다.
    ///   두 필수 권한(FDA + 헬퍼)이 모두 충족되어야만 완료 처리됩니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 desktop·documents·downloads 모두 `.notGranted`,
    ///   로그인 시 실행 비활성화.
    /// - 기대 결과: isComplete == false, nextDisabledMessage가 non-nil.
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

        // FDA는 허용되었으나 헬퍼 폴더 접근이 거부되어 isComplete는 여전히 false
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }

    // MARK: - ONB-003-refresh_onboarding_permission_status

    // 앱 활성화(appDidBecomeActive) 및 화면 이탈(onDisappear) 시 권한 상태 새로고침과
    // 옵저데이션 수명 주기 정리 동작을 검증합니다. 앱이 포그라운드로 복귀할 때
    // 사용자가 시스템 설정에서 변경한 권한을 즉시 반영하는 것이 핵심 목표입니다.
    // onDisappear는 TCA Effect 취소 및 옵저버 해제를 보장합니다.

    /// ONB-003:refresh_onboarding_permission_status — 권한 step을 떠날 때 onDisappear가 실행되면 app-active refresh observation을
    /// 취소한다.
    /// onDisappear가 권한 관찰 Effect를 정상적으로 취소하는지 검증합니다.
    ///
    /// - 검증 내용: onAppear 후 onDisappear를 보내면 관찰 Effect가 취소되고
    ///   추가 액션 수신 없이 finish()가 완료되어야 합니다.
    ///   이는 화면 이탈 시 불필요한 권한 폴링을 중단하여 리소스 누수를 방지합니다.
    /// - 사전 조건: FDA `.unknown`, 헬퍼 폴더 `kGrantedHelperAccess`, 로그인 시 실행 비활성화.
    /// - 기대 결과: onDisappear 이후 pending effect 없이 store.finish() 성공.
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

    /// ONB-003:refresh_onboarding_permission_status — 앱이 다시 active가 될 때 refresh가 실행되면 FDA/helper 상태를 다시 읽어 completion을
    /// 갱신한다.
    /// 앱이 포그라운드로 복귀할 때 권한 상태를 새로고침하는지 검증합니다.
    ///
    /// - 검증 내용: appDidBecomeActive 액션이 FDA·헬퍼 폴더 접근 상태를 재조회하고
    ///   isComplete를 올바르게 갱신합니다. 사용자가 시스템 설정에서 권한을 변경한 후
    ///   앱으로 복귀하면 즉시 반영되어야 합니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 `kGrantedHelperAccess`.
    /// - 기대 결과: fullDiskAccessStatusResponse·helperFolderAccessStatusLoaded 수신 후
    ///   isComplete == true.
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

        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.fullDiskAccessRefreshResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessRefreshLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = true
        }
        await store.finish()
    }

    /// ONB-003:refresh_onboarding_permission_status — FDA가 새로 허용됐을 때 refresh 결과를 받으면 completion이 true로 전환된다.
    /// 새로고침 후 FDA가 허용되면 isComplete가 true로 전환됨을 검증합니다.
    ///
    /// - 검증 내용: appDidBecomeActive가 FDA `.granted` + 헬퍼 `kGrantedHelperAccess`를
    ///   반환할 때 isComplete가 true가 됩니다. 이는 새로고침이 권한 변화를 정확히 반영함을 보장합니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 `kGrantedHelperAccess`.
    /// - 기대 결과: 새로고침 수신 후 isComplete == true.
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

        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.fullDiskAccessRefreshResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessRefreshLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = true
        }

        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    /// ONB-003:refresh_onboarding_permission_status — helper folder 권한이 변경됐을 때 refresh 결과를 받으면 helper status와
    /// completion을 최신 값으로 갱신한다.
    /// 새로고침 시 헬퍼 폴더 접근이 거부로 변경되면 상태가 올바르게 갱신됨을 검증합니다.
    ///
    /// - 검증 내용: appDidBecomeActive가 헬퍼 폴더 전체 `.notGranted`를 반환할 때
    ///   isComplete가 false이고 helperFolderAccessStatus가 `.notGranted`가 됩니다.
    ///   사용자가 시스템 설정에서 권한을 철회한 시나리오를 재현합니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 desktop·documents·downloads 모두 `.notGranted`.
    /// - 기대 결과: isComplete == false, helperFolderAccessStatus == `.notGranted`.
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

        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.fullDiskAccessRefreshResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.helperFolderAccessRefreshLoaded)

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.helperFolderAccessStatus, .notGranted)
        await store.finish()
    }

    /// ONB-003:refresh_onboarding_permission_status — launch-at-login은 non-gate일 때 permission refresh가 실행되면 launch
    /// state를 불필요하게 초기화하지 않는다.
    /// 새로고침이 로그인 시 실행 상태를 초기화하지 않음을 검증합니다.
    ///
    /// - 검증 내용: launchAtLoginEnabled가 true인 초기 상태에서 appDidBecomeActive를
    ///   보내도 launchAtLoginEnabled가 true로 유지되어야 합니다.
    ///   새로고침은 FDA·헬퍼 상태만 갱신하고, 로그인 시 실행은 독립적으로 보존됩니다.
    /// - 사전 조건: initialState.launchAtLoginEnabled = true, FDA `.granted`,
    ///   헬퍼 폴더 `kGrantedHelperAccess`.
    /// - 기대 결과: 새로고침 후 launchAtLoginEnabled == true 유지.
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

        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.fullDiskAccessRefreshResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.helperFolderAccessRefreshLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = true
        }

        XCTAssertTrue(store.state.launchAtLoginEnabled)
        await store.finish()
    }

    /// ONB-003:refresh_onboarding_permission_status — FDA 오류/미충족 상태 후 권한이 허용됐을 때 refresh가 성공하면 error를 지우고 completion을
    /// true로 만든다.
    /// FDA가 `.needsAction`에서 `.granted`로 전환된 후 새로고침이 isComplete를 true로 만드는지 검증합니다.
    ///
    /// - 검증 내용: 시드 단계에서 FDA를 `.needsAction`으로 설정하여 isComplete를 false로 만든 뒤,
    ///   appDidBecomeActive가 FDA `.granted` + 헬퍼 `kGrantedHelperAccess`를 반환하면
    ///   isComplete가 true로 전환되고 nextDisabledMessage가 nil이 됩니다.
    ///   이는 권한 회복 후 온보딩 진행이 차단 해제됨을 보장합니다.
    /// - 사전 조건: 시드로 FDA `.needsAction` 설정, FDA 클라이언트는 `.granted` 반환,
    ///   헬퍼 폴더 `kGrantedHelperAccess`.
    /// - 기대 결과: 새로고침 후 isComplete == true, nextDisabledMessage == nil.
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

        // 시드: FDA를 needsAction으로 설정, 헬퍼는 granted → 아직 온보딩 미완료 상태
        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }
        XCTAssertFalse(store.state.isComplete)

        // 새로고침: FDA 클라이언트가 이제 .granted를 반환함
        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.fullDiskAccessRefreshResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessRefreshLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = true
        }

        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.finish()
    }

    /// ONB-003:refresh_onboarding_permission_status — 중복 app-active refresh가 겹칠 때 오래된 helper 응답이 늦게 도착하면 최신 generation
    /// 결과만 상태에 반영한다.
    /// 두 번의 appDidBecomeActive 새로고침에서 더 오래된 응답이 나중에 도착해도
    /// 최신 세대의 granted 상태가 보존됨을 검증합니다.
    ///
    /// - 검증 내용: 첫 번째 새로고침(generation 1)과 두 번째 새로고침(generation 2)이
    ///   모두 granted로 해결된 후, 오래된 generation 1의 helper 응답이 notGranted로
    ///   직접 전송되어도 최신 granted 상태를 덮어쓰지 않습니다.
    ///   generation 가드가 세대 불일치 응답을 무시하는지 확인합니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 접근 `kGrantedHelperAccess`.
    /// - 기대 결과: 오래된 helperFolderAccessRefreshLoaded(1, denied) 전송 후에도
    ///   `helperFolderAccessStatus == .granted`, `isComplete == true`.
    func testLatestPermissionRefreshWinsWhenOlderHelperResponseArrivesLast() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        // First appDidBecomeActive (generation 1)
        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.fullDiskAccessRefreshResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessRefreshLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.latestAppActiveRefreshGeneration = 1
            state.isComplete = true
        }

        // Second appDidBecomeActive (generation 2)
        await store.send(.appDidBecomeActive) { state in
            state.latestAppActiveRefreshGeneration = 2
        }
        await store.receive(\.fullDiskAccessRefreshResponse)
        await store.receive(\.helperFolderAccessRefreshLoaded)

        // Stale generation-1 helper response should be ignored
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        await store.send(.helperFolderAccessRefreshLoaded(1, deniedAccess))
        // State should NOT change - stale generation is ignored
        XCTAssertEqual(store.state.helperFolderAccessStatus, .granted)
        XCTAssertTrue(store.state.isComplete)

        await store.finish()
    }

    // MARK: - ONB-003-request_onboarding_permission_access

    // 사용자의 권한 요청 액션(FDA 활성화, 헬퍼 폴더 접근 요청, 로그인 시 실행 토글,
    // 시스템 설정 열기)이 올바른 Effect를 트리거하고, 그 결과가 State에
    // 반영되는지 검증합니다. Next 버튼의 게이팅 로직(FDA + 헬퍼 필수,
    // 로그인 시 실행 선택)도 이 그룹에서 확인합니다.

    /// ONB-003:request_onboarding_permission_access — FDA가 미충족일 때 progression을 평가하면 Next/Complete를 차단한다.
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

    /// ONB-003:request_onboarding_permission_access — FDA 요청 후 거부 상태가 유지될 때 응답을 처리하면 denied 상태와 blocking을 유지한다.
    /// 사용자가 시스템 설정 열기를 시도한 후 FDA가 여전히 거부 상태인 경우를 검증합니다.
    ///
    /// - 검증 내용: systemSettingsOpenResult(true)로 hasAttemptedFullDiskAccessEnable를 true로
    ///   설정한 후, fullDiskAccessStatusResponse(.needsAction)이 오면
    ///   fullDiskAccessStatus가 `.denied`로 처리됩니다.
    ///   사용자가 시도했으나 권한을 부여하지 않은 경우 `.needsAction` → `.denied` 전환을 보장합니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: fullDiskAccessStatus == `.denied`, isComplete == false.
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

    /// ONB-003:request_onboarding_permission_access — 시스템 설정 열기가 실패할 때 FDA action을 실행하면 retry 가능한 error를 표시한다.
    /// 시스템 설정 열기 실패 시 에러 메시지가 표시되는지 검증합니다.
    ///
    /// - 검증 내용: systemSettingsOpenResult(false)가 반환되면 systemSettingsError에
    ///   "We couldn't open System Settings. Please open it manually." 메시지가 설정되고,
    ///   hasAttemptedFullDiskAccessEnable는 false로 유지됩니다.
    ///   시스템 설정 URL 열기 실패는 사용자 환경에서 발생할 수 있는 예외 상황입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: systemSettingsError != nil, hasAttemptedFullDiskAccessEnable == false.
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

    /// ONB-003:request_onboarding_permission_access — launch-at-login 토글 요청이 성공할 때 action을 실행하면 non-gate 설정 상태만 갱신한다.
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

    /// ONB-003:request_onboarding_permission_access — launch-at-login 토글 요청이 실패할 때 action을 실행하면 필수 권한 completion과 분리된
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

    /// ONB-003:request_onboarding_permission_access — 사용자가 FDA 설정 열기를 선택할 때 action을 실행하면 system settings client 호출을
    /// 보장한다.
    /// openSystemSettingsTapped이 systemSettingsClient를 호출하는지 검증합니다.
    ///
    /// - 검증 내용: openSystemSettingsTapped 액션이 systemSettingsClient.openFullDiskAccess를
    ///   호출하고, 성공 결과로 systemSettingsOpenResult를 수신하며
    ///   hasAttemptedFullDiskAccessEnable가 true로 설정됩니다.
    /// - 사전 조건: systemSettingsClient openFullDiskAccess가 true 반환.
    /// - 기대 결과: hasAttemptedFullDiskAccessEnable == true.
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

    /// ONB-003:request_onboarding_permission_access — helper folder 요청이 성공할 때 request action을 실행하면 helper access를
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

    /// ONB-003:request_onboarding_permission_access — helper folder 요청이 partial을 반환할 때 응답을 처리하면 partial 상태와 blocking을
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

    /// ONB-003:request_onboarding_permission_access — FDA가 denied일 때 Next 가능 여부를 계산하면 progression을 차단한다.
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

    /// ONB-003:request_onboarding_permission_access — helper access가 notGranted일 때 Next 가능 여부를 계산하면 progression을 차단한다.
    /// 헬퍼 폴더 접근이 미허용일 때 FDA가 허용되더라도 Next가 비활성화됨을 검증합니다.
    ///
    /// - 검증 내용: FDA가 `.granted`이더라도 헬퍼 폴더가 전체 `.notGranted`이면
    ///   nextDisabledMessage가 "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue."
    ///   이고 isComplete == false입니다. 헬퍼 접근은 FDA와 별개의 필수 권한입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: nextDisabledMessage에 헬퍼 접근 안내 메시지, isComplete == false.
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

    /// ONB-003:request_onboarding_permission_access — 필수 권한은 충족되고 launch-at-login만 disabled일 때 progression을 계산하면 Next를
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

    /// ONB-003:request_onboarding_permission_access — FDA가 denied였다가 granted로 바뀔 때 사용자가 retry/refresh하면 completion을
    /// 회복한다.
    /// FDA 권한이 거부에서 허용으로 전환되는 재시도 성공 시나리오를 검증합니다.
    ///
    /// - 검증 내용: systemSettingsOpenResult(true)로 시도 기록 후
    ///   fullDiskAccessStatusResponse(.needsAction)에서 `.denied`로 처리되고,
    ///   이후 fullDiskAccessStatusResponse(.granted)에서 권한이 허용으로 전환됩니다.
    ///   단, 헬퍼 접근 상태가 아직 로드되지 않았으므로 nextDisabledMessage는 여전히 존재합니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: 최종 fullDiskAccessStatus == `.granted`, nextDisabledMessage != nil
    ///   (헬퍼 상태 미확정으로 인해).
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

    /// ONB-003:request_onboarding_permission_access — launch-at-login 상태가 false일 때 필수 권한이 충족되면 completion gate에 영향을 주지
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

    /// ONB-003:request_onboarding_permission_access — FDA required gate가 미충족일 때 Next 버튼 상태를 계산하면 nextDisabledMessage로
    /// 차단 이유를 제공한다.
    /// FDA가 `.needsAction`일 때 헬퍼가 허용되더라도 Next가 차단됨을 검증합니다.
    ///
    /// - 검증 내용: 헬퍼 폴더 `kGrantedHelperAccess`가 이미 로드되었더라도
    ///   FDA가 `.needsAction`이면 nextDisabledMessage가 "Turn on Full Disk Access to continue."
    ///   이고 isComplete == false입니다. FDA는 선행 필수 권한입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: nextDisabledMessage에 FDA 안내 메시지, isComplete == false.
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

    /// ONB-003:request_onboarding_permission_access — helper folder required gate가 미충족일 때 Next 버튼 상태를 계산하면
    /// nextDisabledMessage로 차단 이유를 제공한다.
    /// 헬퍼 폴더 접근이 미허용이면 FDA가 허용되어도 Next가 차단됨을 검증합니다.
    ///
    /// - 검증 내용: FDA `.granted` + 헬퍼 폴더 전체 `.notGranted` 조합에서
    ///   isComplete == false이고 nextDisabledMessage에 헬퍼 접근 안내 메시지가 표시됩니다.
    ///   헬퍼 폴더 접근은 FDA와 독립적인 필수 권한입니다.
    /// - 사전 조건: 의존성 기본값.
    /// - 기대 결과: isComplete == false, nextDisabledMessage에 헬퍼 안내.
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

    /// ONB-003:request_onboarding_permission_access — launch-at-login만 미충족/disabled일 때 FDA/helper가 충족되면 completion을
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

        // 필수 권한(FDA + 헬퍼) 모두 허용, 로그인 시 실행은 비활성화 → 온보딩 완료 가능
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.launchAtLoginEnabled)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }
}
