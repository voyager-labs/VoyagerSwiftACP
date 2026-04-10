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
        switch fullDiskAccessStatus {
        case .granted:
            "You're all set for Full Disk Access."
        case .needsAction:
            "Turn on Full Disk Access to keep going."
        case .denied:
            "Full Disk Access is off. You can enable it anytime."
        case .unknown:
            "Check Full Disk Access in System Settings."
        }
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
