import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences

@ObservableState
struct PermissionsState: Equatable {
    var isComplete: Bool = false
    var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    var helperFolderAccess: FolderAccessResult = .init(
        desktop: .notGranted,
        documents: .notGranted,
        downloads: .notGranted,
    )
    var systemSettingsError: String?
    var helperFolderAccessError: String?
    var isRequestingHelperFolderAccess: Bool = false
    var launchAtLoginEnabled: Bool = false
    var launchAtLoginError: String?
    var hasAttemptedFullDiskAccessEnable: Bool = false
    var latestAppActiveRefreshGeneration: Int = 0
    @ObservationStateIgnored var pendingHelperFolderOperationID: UUID?
    @ObservationStateIgnored var pendingFullDiskAccessOperationID: UUID?
    @ObservationStateIgnored var pendingFullDiskAccessGeneration: Int?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isComplete == rhs.isComplete
            && lhs.fullDiskAccessStatus == rhs.fullDiskAccessStatus
            && lhs.helperFolderAccess == rhs.helperFolderAccess
            && lhs.systemSettingsError == rhs.systemSettingsError
            && lhs.helperFolderAccessError == rhs.helperFolderAccessError
            && lhs.isRequestingHelperFolderAccess == rhs.isRequestingHelperFolderAccess
            && lhs.launchAtLoginEnabled == rhs.launchAtLoginEnabled
            && lhs.launchAtLoginError == rhs.launchAtLoginError
            && lhs.hasAttemptedFullDiskAccessEnable == rhs.hasAttemptedFullDiskAccessEnable
            && lhs.latestAppActiveRefreshGeneration == rhs.latestAppActiveRefreshGeneration
    }

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

    var helperFolderAccessStatus: FilesAndFoldersStatus {
        helperFolderAccess.status
    }

    var showsHelperFolderAccessAction: Bool {
        !allHelperFilesAndFoldersGranted
    }

    var allHelperFilesAndFoldersGranted: Bool {
        helperFolderAccessStatus == .granted
    }

    var helperFilesAndFoldersMessage: String {
        if isRequestingHelperFolderAccess {
            return "Requesting access…"
        }
        if allHelperFilesAndFoldersGranted {
            return "Access granted for Voyager Helper (Desktop, Documents, Downloads)."
        }

        switch helperFolderAccessStatus {
        case .idle:
            return "Tap Grant Access when you're ready."
        case .notGranted:
            return "No folders were granted for Voyager Helper. You can enable them later in System Settings."
        case .partial:
            return "Some folders are still off for Voyager Helper. You can enable them later in System Settings."
        case .granted:
            return "Access granted for Voyager Helper (Desktop, Documents, Downloads)."
        }
    }

    var helperFolderAccessItems: [FolderAccessItem] {
        [
            .init(id: "helper-desktop", title: "Desktop", status: helperFolderAccess.desktop),
            .init(id: "helper-documents", title: "Documents", status: helperFolderAccess.documents),
            .init(id: "helper-downloads", title: "Downloads", status: helperFolderAccess.downloads),
        ]
    }

    var nextDisabledMessage: String? {
        if fullDiskAccessStatus != .granted {
            return "Turn on Full Disk Access to continue."
        }
        if helperFolderAccessStatus != .granted {
            return "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue."
        }
        return nil
    }
}

struct FolderAccessItem: Equatable, Identifiable {
    let id: String
    let title: String
    let status: FolderAccessPermission
}
