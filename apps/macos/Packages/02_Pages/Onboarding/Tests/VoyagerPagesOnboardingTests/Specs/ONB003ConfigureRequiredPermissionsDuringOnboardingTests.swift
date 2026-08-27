import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB003ConfigureRequiredPermissionsDuringOnboardingTests: XCTestCase {
    func testPermissionMetricsIgnoreCancelledAndEmitHelperResponseOnce() async {
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = Self.metricsClient(metrics)
            $0.helperFolderAccessClient.requestAccess = { kGrantedHelperAccess }
        }

        await store.send(.requestHelperFolderAccessTapped) { state in
            state.isRequestingHelperFolderAccess = true
        }
        await store.receive(\.helperFolderAccessResponse) { state in
            state.isRequestingHelperFolderAccess = false
            state.helperFolderAccess = kGrantedHelperAccess
        }
        await store.send(.helperFolderAccessResponse(kGrantedHelperAccess))
        await store.send(.onDisappear)

        XCTAssertEqual(metrics.value.count, 1)
        guard case let .helperFolderAccess(_, result) = metrics.value.first else {
            return XCTFail("Expected helper access metric")
        }
        XCTAssertEqual(result, .success)
    }

    /// ONB-003-refresh_onboarding_permission_status: 진행 중인 helper 요청에서 화면을 떠나면 요청을 취소하고 unavailable로 종결한다.
    /// 동일 lifecycle 종료와 늦은 응답이 원래 operation을 다시 종결하지 않는지 검증합니다.
    /// - 검증 내용: 원 operation ID의 unavailable 1회, requesting reset, task cancellation, late response 무시를 확인합니다.
    /// - 사전 조건: helper 접근 요청 effect가 완료되지 않은 상태입니다.
    /// - 기대 결과: 첫 onDisappear만 terminal을 기록하고 반복 onDisappear와 late response는 조용히 무시됩니다.
    func testOnDisappearTerminalizesAndCancelsPendingHelperOperationOnce() async throws {
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let requestStarted = LockIsolated(false)
        let requestCancelled = LockIsolated(false)
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = Self.metricsClient(metrics)
            $0.helperFolderAccessClient.requestAccess = {
                requestStarted.setValue(true)
                return await withTaskCancellationHandler {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    return kGrantedHelperAccess
                } onCancel: {
                    requestCancelled.setValue(true)
                }
            }
        }

        await store.send(.requestHelperFolderAccessTapped) { state in
            state.isRequestingHelperFolderAccess = true
        }
        await Self.waitUntil { requestStarted.value }
        let operationID = store.state.pendingHelperFolderOperationID

        await store.send(.onDisappear) { state in
            state.isRequestingHelperFolderAccess = false
        }
        await Self.waitUntil { requestCancelled.value }
        await store.send(.onDisappear)
        await store.send(.helperFolderAccessResponse(kGrantedHelperAccess))
        await store.finish()

        XCTAssertEqual(metrics.value, try [
            .helperFolderAccess(operationID: XCTUnwrap(operationID), result: .unavailable),
        ])
    }

    /// ONB-003-refresh_onboarding_permission_status: 진행 중인 FDA operation에서 화면을 떠나면 원 ID로 unavailable 종결한다.
    /// FDA refresh correlation을 지우기 전에 유한 terminal이 기록되는지 검증합니다.
    /// - 검증 내용: 원 operation ID의 unavailable 1회를 확인합니다.
    /// - 사전 조건: FDA operation과 app-active generation correlation이 pending입니다.
    /// - 기대 결과: 두 pending FDA 필드가 지워지고 terminal은 정확히 한 번 기록됩니다.
    func testOnDisappearTerminalizesPendingFullDiskAccessOperation() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        var initialState = PermissionsFeature.State()
        initialState.pendingFullDiskAccessOperationID = operationID
        initialState.pendingFullDiskAccessGeneration = 7
        initialState.latestAppActiveRefreshGeneration = 7
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = Self.metricsClient(metrics)
        }

        await store.send(.onDisappear)
        await store.send(.fullDiskAccessRefreshResponse(6, .granted))

        XCTAssertNil(store.state.pendingFullDiskAccessOperationID)
        XCTAssertNil(store.state.pendingFullDiskAccessGeneration)
        XCTAssertEqual(metrics.value, [
            .fullDiskAccess(operationID: operationID, result: .unavailable),
        ])
    }

    /// ONB-003-refresh_onboarding_permission_status: helper와 FDA operation이 함께 pending일 때 화면을 떠나면 각각 종결한다.
    /// 서로 다른 correlation ID가 손실되거나 합쳐지지 않는지 검증합니다.
    /// - 검증 내용: helper와 FDA 각각 원 ID를 가진 unavailable terminal 1회를 확인합니다.
    /// - 사전 조건: 두 permission operation이 동시에 pending입니다.
    /// - 기대 결과: 두 terminal이 기록되고 모든 pending/requesting 상태가 초기화됩니다.
    func testOnDisappearTerminalizesBothPendingPermissionOperations() async throws {
        let helperID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let fullDiskAccessID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        var initialState = PermissionsFeature.State()
        initialState.pendingHelperFolderOperationID = helperID
        initialState.pendingFullDiskAccessOperationID = fullDiskAccessID
        initialState.isRequestingHelperFolderAccess = true
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = Self.metricsClient(metrics)
        }

        await store.send(.onDisappear) { state in
            state.isRequestingHelperFolderAccess = false
        }

        XCTAssertEqual(metrics.value, [
            .helperFolderAccess(operationID: helperID, result: .unavailable),
            .fullDiskAccess(operationID: fullDiskAccessID, result: .unavailable),
        ])
    }

    /// ONB-003-refresh_onboarding_permission_status: pending permission operation 없이 화면을 떠나면 metric을 기록하지 않는다.
    /// lifecycle 종료 자체가 가짜 terminal을 만들지 않는지 검증합니다.
    /// - 검증 내용: 빈 metric 기록을 확인합니다.
    /// - 사전 조건: helper/FDA pending ID가 모두 nil입니다.
    /// - 기대 결과: onDisappear는 조용히 observation 정리만 수행합니다.
    func testOnDisappearWithoutPendingPermissionOperationIsSilent() async {
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = Self.metricsClient(metrics)
        }

        await store.send(.onDisappear)

        XCTAssertTrue(metrics.value.isEmpty)
    }

    // MARK: - ONB-003-show_onboarding_permission_status

    // 온보딩 권한 구성 화면(ONB-003)의 첫 번째 스펙 인터랙션입니다.
    // 사용자가 권한 설정 화면에 진입(onAppear)했을 때 리듀서가 세 가지 권한의 현재 상태를
    // 병렬로 수집하여 State에 반영하는 흐름을 검증합니다.
    // 대상 권한: Full Disk Access(FDA), 헬퍼 폴더 접근(Desktop/Documents/Downloads),
    // 로그인 시 실행(LaunchAtLogin).

    /// ONB-003-show_onboarding_permission_status: 권한 step이 표시될 때 onAppear가 실행되면 FDA/helper/launch 상태를 수집하고 필수 권한 완료
    /// 여부를 계산한다.
    /// ONB-003-show_onboarding_permission_status 스펙에서 onAppear 시 권한 상태를 병렬로 수집하는 흐름을 검증합니다.
    ///
    /// 리듀서가 onAppear를 받으면 세 개의 이펙트(FDA 상태, 헬퍼 폴더 접근 상태, 로그인 항목 상태)를
    /// 동시에 시작하고, 각 결과 액션을 순차적으로 수신하여 State를 갱신합니다.
    ///
    /// - 검증 내용: `onAppear` 이후 FDA, helper folder, launch-at-login 상태 응답이 state에 반영되는 흐름입니다.
    /// - 사전 조건: FDA는 `.granted`(허용됨), 헬퍼 폴더 접근은 `kGrantedHelperAccess`
    ///   (Desktop·Documents·Downloads 모두 허용), 로그인 시 실행은 비활성화(`false`).
    ///   로그인 항목은 비게이팅 권한이므로 FDA와 헬퍼 접근만으로 완료 판정이 납니다.
    /// - 기대 결과: `fullDiskAccessStatusResponse(.granted)` 수신 후 `isComplete`는 여전히 `false`
    ///   (헬퍼 접근 결과 미수신). `helperFolderAccessStatusLoaded` 수신 후 `helperFolderAccessError`는
    ///   `nil`이 되고 `isComplete == true`. `launchAtLoginStateLoaded`는 추가로 수신되지만
    ///   `isComplete`에는 영향을 주지 않습니다.
    func testOnAppearLoadsHelperFolderAccessStatus() async {
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

        await store.send(.onDisappear)
        await store.finish()
    }

    /// ONB-003-show_onboarding_permission_status: FDA가 `.unknown`일 때 온보딩 완료가 차단되는지 검증합니다.
    ///
    /// macOS는 FDA 권한을 허용/거부/미확인 세 가지로 보고합니다. `.unknown`은 사용자가 아직
    /// 시스템 설정에서 권한을 부여하지 않은 초기 상태로, 리듀서는 이를 사실상 거부와 동일하게
    /// 취급하여 Next 버튼을 비활성화합니다.
    ///
    /// - 검증 내용: FDA `.unknown` 상태에서 권한 step이 완료되지 않고 Next 차단 사유를 노출하는 흐름입니다.
    /// - 사전 조건: FDA는 `.unknown`(미확인), 헬퍼 폴더 접근은 `kGrantedHelperAccess`(모두 허용),
    ///   로그인 시 실행은 비활성화. 헬퍼 접근만으로는 완료 판정이 나지 않습니다.
    /// - 기대 결과: `nextDisabledMessage`가 non-nil이 되어 Next 버튼이 비활성화.
    ///   `fullDiskAccessStatus == .unknown` 유지. `isComplete`는 헬퍼 접근이 허용되었더라도
    ///   FDA 미확정으로 인해 최종 완료가 아닙니다.
    func testOnAppearWithFDAUnknownShowsNeedsAction() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            PermissionClients.fdaUnknown(&$0)
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

    /// ONB-003-show_onboarding_permission_status: helper folder access가 부분 허용일 때 상태를 표시하면 partial 상태와 추가 action 필요성을
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
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = PermissionClients.grantedFDA
            $0.helperFolderAccessClient = PermissionClients.deniedHelper(kPartialHelperAccess)
            $0.launchAtLoginClient = PermissionClients.disabledLaunchAtLogin
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kPartialHelperAccess
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

    /// ONB-003-show_onboarding_permission_status: FDA/helper가 모두 미충족일 때 상태를 표시하면 denied/notGranted 상태와 progression
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
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            PermissionClients.allDenied(&$0)
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

    /// ONB-003-show_onboarding_permission_status: 필수 권한 중 하나라도 미충족일 때 초기 상태를 계산하면 isComplete를 false로 유지한다.
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
            $0.fullDiskAccessClient = PermissionClients.needsActionFDA
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
            $0.launchAtLoginClient = PermissionClients.disabledLaunchAtLogin
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

    /// ONB-003-show_onboarding_permission_status: FDA는 허용됐지만 helper 접근이 거부됐을 때 상태를 계산하면 completion을 차단한다.
    /// FDA 허용 상태에서 헬퍼 폴더 접근 거부 시 isComplete가 차단됨을 검증합니다.
    ///
    /// - 검증 내용: FDA는 `.granted`이더라도 헬퍼 폴더 접근이 전체 거부되면
    ///   isComplete는 false이고 nextDisabledMessage가 존재합니다.
    ///   두 필수 권한(FDA + 헬퍼)이 모두 충족되어야만 완료 처리됩니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 desktop·documents·downloads 모두 `.notGranted`,
    ///   로그인 시 실행 비활성화.
    /// - 기대 결과: isComplete == false, nextDisabledMessage가 non-nil.
    func testHelperFolderAccessDeniedBlocksCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            PermissionClients.helperDenied(&$0)
            $0.launchAtLoginClient = PermissionClients.disabledLaunchAtLogin
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

    /// ONB-003-refresh_onboarding_permission_status: 권한 step을 떠날 때 onDisappear가 실행되면 app-active refresh observation을
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
            PermissionClients.fdaUnknown(&$0)
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

    /// ONB-003-refresh_onboarding_permission_status: 화면 이탈은 진행 중인 초기 권한 로드를 취소한다.
    /// lifecycle 종료가 초기 helper 상태 조회 Effect를 정리하는지 검증합니다.
    ///
    /// - 검증 내용: onAppear의 초기 helper 조회가 대기 중일 때 onDisappear를 전송합니다.
    /// - 사전 조건: FDA 초기 상태 응답 이후 helper 조회가 아직 완료되지 않았습니다.
    /// - 기대 결과: 초기 로드 task가 취소되고 늦은 helper/login 응답을 보내지 않습니다.
    func testOnDisappearCancelsInitialPermissionLoad() async {
        let loadStarted = LockIsolated(false)
        let loadCancelled = LockIsolated(false)
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            PermissionClients.fdaUnknown(&$0)
            $0.helperFolderAccessClient.checkAccess = {
                loadStarted.setValue(true)
                return await withTaskCancellationHandler {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    return kGrantedHelperAccess
                } onCancel: {
                    loadCancelled.setValue(true)
                }
            }
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse)
        await Self.waitUntil { loadStarted.value }
        await store.send(.onDisappear)
        await Self.waitUntil { loadCancelled.value }
        await store.finish()
    }

    /// ONB-003-refresh_onboarding_permission_status: 앱이 다시 active가 될 때 refresh가 실행되면 FDA/helper 상태를 다시 읽어 completion을
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
            $0.fullDiskAccessClient = PermissionClients.grantedFDA
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
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

    /// ONB-003-refresh_onboarding_permission_status: FDA가 새로 허용됐을 때 refresh 결과를 받으면 completion이 true로 전환된다.
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
            $0.fullDiskAccessClient = PermissionClients.grantedFDA
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
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

    /// ONB-003-refresh_onboarding_permission_status: helper folder 권한이 변경됐을 때 refresh 결과를 받으면 helper status와
    /// completion을 최신 값으로 갱신한다.
    /// 새로고침 시 헬퍼 폴더 접근이 거부로 변경되면 상태가 올바르게 갱신됨을 검증합니다.
    ///
    /// - 검증 내용: appDidBecomeActive가 헬퍼 폴더 전체 `.notGranted`를 반환할 때
    ///   isComplete가 false이고 helperFolderAccessStatus가 `.notGranted`가 됩니다.
    ///   사용자가 시스템 설정에서 권한을 철회한 시나리오를 재현합니다.
    /// - 사전 조건: FDA `.granted`, 헬퍼 폴더 desktop·documents·downloads 모두 `.notGranted`.
    /// - 기대 결과: isComplete == false, helperFolderAccessStatus == `.notGranted`.
    func testRefreshAfterHelperFolderAccessChangeUpdatesStatus() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            PermissionClients.helperDenied(&$0)
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

    /// ONB-003-refresh_onboarding_permission_status: launch-at-login은 non-gate일 때 permission refresh가 실행되면 launch
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
            $0.fullDiskAccessClient = PermissionClients.grantedFDA
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
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

    /// ONB-003-refresh_onboarding_permission_status: FDA 오류/미충족 상태 후 권한이 허용됐을 때 refresh가 성공하면 error를 지우고 completion을
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
            $0.fullDiskAccessClient = PermissionClients.grantedFDA
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
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

    /// ONB-003-refresh_onboarding_permission_status: 중복 app-active refresh가 겹칠 때 오래된 helper 응답이 늦게 도착하면 최신 generation
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
            $0.fullDiskAccessClient = PermissionClients.grantedFDA
            $0.helperFolderAccessClient = PermissionClients.grantedHelper
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
        await store.send(.helperFolderAccessRefreshLoaded(1, kDeniedHelperAccess))
        // State should NOT change - stale generation is ignored
        XCTAssertEqual(store.state.helperFolderAccessStatus, .granted)
        XCTAssertTrue(store.state.isComplete)

        await store.finish()
    }
}

private extension ONB003ConfigureRequiredPermissionsDuringOnboardingTests {
    static func metricsClient(
        _ metrics: LockIsolated<[OnboardingProductMetric]>,
    ) -> OnboardingProductMetricsClient {
        OnboardingProductMetricsClient(record: { metric in
            metrics.withValue { $0.append(metric) }
        })
    }

    static func waitUntil(
        _ condition: @escaping @Sendable () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        for _ in 0 ..< 100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition was not met in time", file: file, line: line)
    }
}
