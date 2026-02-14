import ComposableArchitecture
import Foundation

@ObservableState
struct PermissionsState: Equatable, Sendable {
    var isComplete: Bool = false
    var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    var systemSettingsError: String?
    var filesAndFoldersStatus: FilesAndFoldersStatus = .idle
    var folderAccessResult: FolderAccessResult?
    var helperFilesAndFoldersStatus: FilesAndFoldersStatus = .idle
    var helperFolderAccessResult: FolderAccessResult?
    var isRequestingFilesAndFolders: Bool = false
    var isIndexingInBackground: Bool = false
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
        return allFilesAndFoldersGranted
            ? nil
            : "Allow Desktop, Documents, and Downloads for Voyager and Voyager Helper to continue."
    }

    var filesAndFoldersMessage: String {
        if isRequestingFilesAndFolders {
            return "Requesting access…"
        }
        if allFilesAndFoldersGranted {
            return "Access granted for Voyager and Voyager Helper (Desktop, Documents, Downloads)."
        }

        switch (filesAndFoldersStatus, helperFilesAndFoldersStatus) {
        case (.idle, .idle):
            return "Tap Grant Access when you're ready."
        case (.notGranted, .notGranted):
            return
                "No folders were granted for Voyager and Voyager Helper. "
                    + "You can enable them later in System Settings."
        default:
            return
                "Some folders are still off for Voyager or Voyager Helper. "
                    + "You can enable them later in System Settings."
        }
    }

    var folderAccessItems: [FolderAccessItem] {
        guard let result = folderAccessResult else { return [] }
        return [
            FolderAccessItem(id: "desktop", title: "Desktop", status: result.desktop),
            FolderAccessItem(id: "documents", title: "Documents", status: result.documents),
            FolderAccessItem(id: "downloads", title: "Downloads", status: result.downloads),
        ]
    }

    var helperFolderAccessItems: [FolderAccessItem] {
        guard let result = helperFolderAccessResult else { return [] }
        return [
            FolderAccessItem(id: "helper-desktop", title: "Desktop", status: result.desktop),
            FolderAccessItem(id: "helper-documents", title: "Documents", status: result.documents),
            FolderAccessItem(id: "helper-downloads", title: "Downloads", status: result.downloads),
        ]
    }

    var allFilesAndFoldersGranted: Bool {
        filesAndFoldersStatus == .granted && helperFilesAndFoldersStatus == .granted
    }
}

struct FolderAccessItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: FolderAccessPermission
}
