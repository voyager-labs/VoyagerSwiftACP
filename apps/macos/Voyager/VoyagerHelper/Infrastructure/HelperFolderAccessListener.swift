import Foundation

@MainActor
final class HelperFolderAccessListener {
    private enum AccessValue: String {
        case granted = "Granted"
        case notGranted = "Not Granted"
    }

    private nonisolated(unsafe) var observer: NSObjectProtocol?

    deinit {
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func startObservingRequests() {
        guard observer == nil else { return }
        let token = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperFolderAccessRequest,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.postCurrentFolderAccess()
            }
        }
        observer = token
    }

    private func postCurrentFolderAccess() {
        let payload: [String: Any] = [
            HelperFolderAccessUserInfoKey.schemaVersion: 1,
            HelperFolderAccessUserInfoKey.desktop: folderAccess(for: .desktopDirectory).rawValue,
            HelperFolderAccessUserInfoKey.documents: folderAccess(for: .documentDirectory).rawValue,
            HelperFolderAccessUserInfoKey.downloads: folderAccess(for: .downloadsDirectory).rawValue,
        ]

        DistributedNotificationCenter.default().post(
            name: .voyagerHelperFolderAccessDidUpdate,
            object: nil,
            userInfo: payload,
        )
    }

    private func folderAccess(for directory: FileManager.SearchPathDirectory) -> AccessValue {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
            return .notGranted
        }

        do {
            _ = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
            return .granted
        } catch {
            return .notGranted
        }
    }
}
