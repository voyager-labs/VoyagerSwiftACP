import Foundation

@MainActor
final class HelperFolderAccessListener {
    private enum RequestMode: String {
        case check
        case request
    }

    private enum AccessValue: String {
        case granted = "Granted"
        case notGranted = "Not Granted"
    }

    nonisolated(unsafe) private var observer: NSObjectProtocol?

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

    private func postCurrentFolderAccess(mode: RequestMode) {
        let payload: [String: Any] = [
            HelperFolderAccessUserInfoKey.schemaVersion: 1,
            HelperFolderAccessUserInfoKey.mode: mode.rawValue,
            HelperFolderAccessUserInfoKey.desktop: folderAccess(for: .desktopDirectory, mode: mode).rawValue,
            HelperFolderAccessUserInfoKey.documents: folderAccess(for: .documentDirectory, mode: mode).rawValue,
            HelperFolderAccessUserInfoKey.downloads: folderAccess(for: .downloadsDirectory, mode: mode).rawValue,
        ]

        DistributedNotificationCenter.default().post(
            name: .voyagerHelperFolderAccessDidUpdate,
            object: nil,
            userInfo: payload,
        )
    }

    private func folderAccess(for directory: FileManager.SearchPathDirectory, mode: RequestMode) -> AccessValue {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
            return .notGranted
        }

        switch mode {
        case .check:
            return fileManager.isReadableFile(atPath: url.path) ? .granted : .notGranted

        case .request:
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

    nonisolated private static func parseMode(_ userInfo: [AnyHashable: Any]?) -> RequestMode? {
        guard let raw = userInfo?[HelperFolderAccessUserInfoKey.mode] as? String else { return nil }
        return RequestMode(rawValue: raw)
    }
}
