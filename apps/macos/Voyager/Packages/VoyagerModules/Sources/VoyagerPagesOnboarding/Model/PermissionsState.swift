import ComposableArchitecture
import Foundation
import VoyagerEntitiesSettings

@ObservableState
struct PermissionsState: Equatable, Sendable {
    var isComplete: Bool = false
    var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    var helperFolderAccess = FolderAccessResult(desktop: .notGranted, documents: .notGranted, downloads: .notGranted)
    var systemSettingsError: String?
    var helperFolderAccessError: String?
    var isRequestingHelperFolderAccess: Bool = false
    var launchAtLoginEnabled: Bool = false
    var launchAtLoginError: String?
    var hasAttemptedFullDiskAccessEnable: Bool = false

    var fullDiskAccessStatusMessage: String {
        fullDiskAccessStatus.message
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
            FolderAccessItem(id: "helper-desktop", title: "Desktop", status: helperFolderAccess.desktop),
            FolderAccessItem(id: "helper-documents", title: "Documents", status: helperFolderAccess.documents),
            FolderAccessItem(id: "helper-downloads", title: "Downloads", status: helperFolderAccess.downloads),
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

struct FolderAccessItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: FolderAccessPermission
}
