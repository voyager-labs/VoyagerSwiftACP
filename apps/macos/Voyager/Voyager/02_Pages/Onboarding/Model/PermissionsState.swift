import ComposableArchitecture
import Foundation

@ObservableState
struct PermissionsState: Equatable, Sendable {
    var isComplete: Bool = false
    var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    var systemSettingsError: String?
    var filesAndFoldersStatus: FilesAndFoldersStatus = .idle
    var folderAccessResult: FolderAccessResult?
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
        fullDiskAccessStatus == .granted ? nil : "Turn on Full Disk Access to continue."
    }

    var filesAndFoldersMessage: String {
        if isRequestingFilesAndFolders {
            return "Requesting access…"
        }
        return filesAndFoldersStatus.message
    }

    var folderAccessItems: [FolderAccessItem] {
        guard let result = folderAccessResult else { return [] }
        return [
            FolderAccessItem(id: "desktop", title: "Desktop", status: result.desktop),
            FolderAccessItem(id: "documents", title: "Documents", status: result.documents),
            FolderAccessItem(id: "downloads", title: "Downloads", status: result.downloads),
        ]
    }
}

struct FolderAccessItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: FolderAccessPermission
}
