import AppKit
import ComposableArchitecture
import Foundation

public enum FolderAccessPermission: String, Equatable, Sendable, Codable {
    case granted = "Granted"
    case notGranted = "Not Granted"
}

public enum FilesAndFoldersStatus: Equatable, Sendable {
    case idle
    case granted
    case partial
    case notGranted

    public var message: String {
        switch self {
        case .idle:
            "Tap Grant Access when you're ready."
        case .granted:
            "Access granted for the requested folders."
        case .partial:
            "Some folders are still off. You can enable them later in System Settings."
        case .notGranted:
            "No folders were granted. You can enable them later in System Settings."
        }
    }
}

public struct FolderAccessResult: Equatable, Sendable, Codable {
    public var desktop: FolderAccessPermission
    public var documents: FolderAccessPermission
    public var downloads: FolderAccessPermission

    public init(desktop: FolderAccessPermission, documents: FolderAccessPermission, downloads: FolderAccessPermission) {
        self.desktop = desktop
        self.documents = documents
        self.downloads = downloads
    }

    public var status: FilesAndFoldersStatus {
        let grantedCount = [desktop, documents, downloads].count(where: { $0 == .granted })
        switch grantedCount {
        case 3:
            return .granted
        case 0:
            return .notGranted
        default:
            return .partial
        }
    }
}

public struct FolderAccessClient: Sendable {
    public var requestAccess: @Sendable () async -> FolderAccessResult

    public nonisolated init(requestAccess: @escaping @Sendable () async -> FolderAccessResult) {
        self.requestAccess = requestAccess
    }
}

extension FolderAccessClient: DependencyKey {
    public nonisolated static var liveValue: FolderAccessClient {
        FolderAccessClient(requestAccess: {
            await MainActor.run {
                let fileManager = FileManager.default
                let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first

                let desktopStatus = requestFolderAccess(desktopURL)
                let documentsStatus = requestFolderAccess(documentsURL)
                let downloadsStatus = requestFolderAccess(downloadsURL)

                return FolderAccessResult(
                    desktop: desktopStatus,
                    documents: documentsStatus,
                    downloads: downloadsStatus,
                )
            }
        })
    }

    public nonisolated static var testValue: FolderAccessClient {
        FolderAccessClient(requestAccess: {
            FolderAccessResult(
                desktop: .notGranted,
                documents: .notGranted,
                downloads: .notGranted,
            )
        })
    }

    public nonisolated static var previewValue: FolderAccessClient {
        FolderAccessClient(requestAccess: {
            FolderAccessResult(
                desktop: .notGranted,
                documents: .notGranted,
                downloads: .notGranted,
            )
        })
    }
}

public extension DependencyValues {
    nonisolated var folderAccessClient: FolderAccessClient {
        get { self[FolderAccessClient.self] }
        set { self[FolderAccessClient.self] = newValue }
    }
}

private func requestFolderAccess(_ url: URL?) -> FolderAccessPermission {
    guard let url else { return .notGranted }
    do {
        _ = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        return .granted
    } catch {
        return .notGranted
    }
}
