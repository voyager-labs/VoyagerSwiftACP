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
        ) { [weak self] notification in
            let mode = Self.parseMode(notification.userInfo) ?? .check
            Task { @MainActor in
                self?.postCurrentFolderAccess(mode: mode)
            }
        }
        observer = token
    }

    private func postCurrentFolderAccess(mode: HelperFolderAccessMode) {
        let payload: [String: Any] = [
            HelperFolderAccessUserInfoKey.schemaVersion: 1,
            HelperFolderAccessUserInfoKey.mode: mode.rawValue,
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

    private nonisolated static func parseMode(_ userInfo: [AnyHashable: Any]?) -> HelperFolderAccessMode? {
        guard let raw = userInfo?[HelperFolderAccessUserInfoKey.mode] as? String else { return nil }
        return HelperFolderAccessMode(rawValue: raw)
    }
}
