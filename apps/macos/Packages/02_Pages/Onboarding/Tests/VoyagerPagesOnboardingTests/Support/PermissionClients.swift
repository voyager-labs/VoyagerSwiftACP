import ComposableArchitecture
import VoyagerEntitiesAppPreferences

// 테스트에서 반복 사용하는 권한 클라이언트 의존성 헬퍼.
// 개별 클라이언트(factory)와 여러 클라이언트를 한번에 적용하는 복합 헬퍼(composite)를 제공한다.

enum PermissionClients {
    // MARK: - Individual FDA Clients

    static var grantedFDA: FullDiskAccessClient {
        FullDiskAccessClient(status: { .granted })
    }

    static var deniedFDA: FullDiskAccessClient {
        FullDiskAccessClient(status: { .denied })
    }

    static var unknownFDA: FullDiskAccessClient {
        FullDiskAccessClient(status: { .unknown })
    }

    static var needsActionFDA: FullDiskAccessClient {
        FullDiskAccessClient(status: { .needsAction })
    }

    // MARK: - Individual Helper Clients

    static var grantedHelper: HelperFolderAccessClient {
        HelperFolderAccessClient(
            checkAccess: { kGrantedHelperAccess },
            requestAccess: { kGrantedHelperAccess },
        )
    }

    // MARK: - Individual Launch Clients

    static var disabledLaunchAtLogin: LaunchAtLoginClient {
        LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
    }

    static func deniedHelper(_ access: FolderAccessResult) -> HelperFolderAccessClient {
        HelperFolderAccessClient(
            checkAccess: { access },
            requestAccess: { access },
        )
    }

    // MARK: - Composite Helpers

    /// FDA granted + Helper granted + LaunchAtLogin disabled
    static func allGranted(_ deps: inout DependencyValues) {
        deps.fullDiskAccessClient = grantedFDA
        deps.helperFolderAccessClient = grantedHelper
        deps.launchAtLoginClient = disabledLaunchAtLogin
    }

    /// FDA denied + Helper denied(kDeniedHelperAccess) + LaunchAtLogin disabled
    static func allDenied(_ deps: inout DependencyValues) {
        deps.fullDiskAccessClient = deniedFDA
        deps.helperFolderAccessClient = deniedHelper(kDeniedHelperAccess)
        deps.launchAtLoginClient = disabledLaunchAtLogin
    }

    /// FDA unknown + Helper granted + LaunchAtLogin disabled
    static func fdaUnknown(_ deps: inout DependencyValues) {
        deps.fullDiskAccessClient = unknownFDA
        deps.helperFolderAccessClient = grantedHelper
        deps.launchAtLoginClient = disabledLaunchAtLogin
    }

    /// FDA granted + Helper denied(kDeniedHelperAccess). LaunchAtLogin은 별도 설정.
    static func helperDenied(_ deps: inout DependencyValues) {
        deps.fullDiskAccessClient = grantedFDA
        deps.helperFolderAccessClient = deniedHelper(kDeniedHelperAccess)
    }
}
