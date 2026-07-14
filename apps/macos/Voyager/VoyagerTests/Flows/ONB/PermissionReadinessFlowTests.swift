// FLOW-ID: onb.permission_readiness
import ComposableArchitecture
import Dependencies
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

@MainActor
final class PermissionReadinessFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// ONB permission_readiness: happy_path
    func testGrantedPermissionsPromoteOnboardingStepAndEnableNext() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { Self.grantedHelperAccess },
                requestAccess: { Self.grantedHelperAccess },
            )
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: { true })
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }
        // store.exhaustivity = .off: 부모-자식 flow의 완료 결과만 검증하고 저장 effect 세부 action은 소유하지 않는다.
        store.exhaustivity = .off

        await store.send(.permissions(.onAppear))
        await store.receive(\.permissions.fullDiskAccessStatusResponse) { state in
            state.permissions.fullDiskAccessStatus = .granted
            state.permissions.isComplete = false
        }
        await store.receive(\.permissions.helperFolderAccessStatusLoaded) { state in
            state.permissions.helperFolderAccess = Self.grantedHelperAccess
            state.permissions.helperFolderAccessError = nil
            state.permissions.isComplete = true
        }
        await store.receive(\.permissions.launchAtLoginStateLoaded)

        XCTAssertTrue(store.state.permissions.isComplete)
        XCTAssertTrue(store.state.canGoNext)

        await store.send(.permissions(.onDisappear))
        await store.finish()
    }

    // FLOW-PATH: permission_request

    /// ONB permission_readiness: permission_request
    func testPermissionRequestRechecksOnActivationAndUsesLiveStatusOverSnapshot() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions
        initialState.permissions.fullDiskAccessStatus = .denied
        initialState.permissions.helperFolderAccess = Self.grantedHelperAccess

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { Self.grantedHelperAccess },
                requestAccess: { Self.grantedHelperAccess },
            )
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: { true })
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }
        // store.exhaustivity = .off: activation refresh의 내부 저장 effect 대신 최신 권한이 부모 Next gate에 반영되는지만 검증한다.
        store.exhaustivity = .off

        await store.send(.permissions(.openSystemSettingsTapped))
        await store.receive(\.permissions.systemSettingsOpenResult) { state in
            state.permissions.hasAttemptedFullDiskAccessEnable = true
        }

        await store.send(.permissions(.appDidBecomeActive)) { state in
            state.permissions.latestAppActiveRefreshGeneration = 1
        }
        await store.receive(\.permissions.fullDiskAccessRefreshResponse) { state in
            state.permissions.fullDiskAccessStatus = .granted
            state.permissions.isComplete = true
        }
        await store.receive(\.permissions.helperFolderAccessRefreshLoaded) { state in
            state.permissions.helperFolderAccess = Self.grantedHelperAccess
            state.permissions.helperFolderAccessError = nil
        }

        XCTAssertEqual(store.state.permissions.fullDiskAccessStatus, .granted)
        XCTAssertTrue(store.state.permissions.isComplete)
        XCTAssertTrue(store.state.canGoNext)

        await store.finish()
    }

    // FLOW-PATH: permission_error

    /// ONB permission_readiness: permission_error
    func testPermissionBoundaryFailureKeepsNextDisabledAndExposesRetry() async {
        let systemSettingsRequests = LockIsolated(0)
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions
        initialState.permissions.fullDiskAccessStatus = .denied
        initialState.permissions.helperFolderAccess = Self.grantedHelperAccess

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .denied })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { Self.grantedHelperAccess },
                requestAccess: { Self.grantedHelperAccess },
            )
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: {
                systemSettingsRequests.withValue { $0 += 1 }
                return false
            })
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }
        // store.exhaustivity = .off: OS 경계 실패가 부모 진행 게이트를 열지 않는 결과와 recorder 호출만 검증한다.
        store.exhaustivity = .off

        await store.send(.permissions(.openSystemSettingsTapped))
        await store.receive(\.permissions.systemSettingsOpenResult) { state in
            state.permissions.systemSettingsError =
                "We couldn't open System Settings. Please open it manually."
        }

        XCTAssertEqual(systemSettingsRequests.withValue { $0 }, 1)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertTrue(store.state.permissions.showsFullDiskAccessAction)
        XCTAssertFalse(store.state.canGoNext)
        XCTAssertNotNil(store.state.permissions.systemSettingsError)

        await store.finish()
    }

    nonisolated private static let grantedHelperAccess = FolderAccessResult(
        desktop: .granted,
        documents: .granted,
        downloads: .granted,
    )
}
