import ComposableArchitecture
import Foundation
import VoyagerEntitiesSettings

@ObservableState
struct PermissionsState: Equatable, Sendable {
    var isComplete: Bool = false
    var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    var systemSettingsError: String?
    var launchAtLoginEnabled: Bool = false
    var launchAtLoginError: String?
    var hasAttemptedFullDiskAccessEnable: Bool = false

    var fullDiskAccessStatusMessage: String {
        fullDiskAccessStatus.message
    }

    var showsFullDiskAccessAction: Bool {
        fullDiskAccessStatus != .granted
    }

    var nextDisabledMessage: String? {
        if fullDiskAccessStatus != .granted {
            return "Turn on Full Disk Access to continue."
        }
        return nil
    }
}
