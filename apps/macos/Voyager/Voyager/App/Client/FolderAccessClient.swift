import AppKit
import ComposableArchitecture
import Foundation

enum FolderAccessPermission: String, Equatable, Sendable {
    case granted = "Granted"
    case notGranted = "Not Granted"
}

enum FilesAndFoldersStatus: Equatable, Sendable {
    case idle
    case granted
    case partial
    case notGranted

    var message: String? {
        switch self {
        case .idle:
            nil
        case .granted:
            "Access granted for Desktop, Documents, and Downloads."
        case .partial:
            "Some folders weren't granted. You can retry or grant them later in System Settings."
        case .notGranted:
            "You can grant access later in System Settings."
        }
    }
}

struct FolderAccessResult: Equatable, Sendable {
    var desktop: FolderAccessPermission
    var documents: FolderAccessPermission
    var downloads: FolderAccessPermission

    var status: FilesAndFoldersStatus {
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

struct FolderAccessClient: Sendable {
    var requestAccess: @Sendable () async -> FolderAccessResult

    nonisolated init(requestAccess: @escaping @Sendable () async -> FolderAccessResult) {
        self.requestAccess = requestAccess
    }
}

extension FolderAccessClient: DependencyKey {
    nonisolated static var liveValue: FolderAccessClient {
        FolderAccessClient(requestAccess: {
            await MainActor.run {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = true
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                panel.message = "Select Desktop, Documents, and Downloads."
                panel.prompt = "Grant Access"

                guard panel.runModal() == .OK else {
                    return FolderAccessResult(
                        desktop: .notGranted,
                        documents: .notGranted,
                        downloads: .notGranted,
                    )
                }

                let selectedPaths = Set(panel.urls.map(\.standardizedFileURL.path))

                let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
                let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path

                let desktopStatus = desktopPath
                    .map {
                        selectedPaths.contains($0)
                            ? FolderAccessPermission.granted
                            : FolderAccessPermission.notGranted
                    } ?? FolderAccessPermission.notGranted
                let documentsStatus = documentsPath
                    .map {
                        selectedPaths.contains($0)
                            ? FolderAccessPermission.granted
                            : FolderAccessPermission.notGranted
                    } ?? FolderAccessPermission.notGranted
                let downloadsStatus = downloadsPath
                    .map {
                        selectedPaths.contains($0)
                            ? FolderAccessPermission.granted
                            : FolderAccessPermission.notGranted
                    } ?? FolderAccessPermission.notGranted

                return FolderAccessResult(
                    desktop: desktopStatus,
                    documents: documentsStatus,
                    downloads: downloadsStatus,
                )
            }
        })
    }

    nonisolated static var testValue: FolderAccessClient {
        FolderAccessClient(requestAccess: {
            FolderAccessResult(
                desktop: .notGranted,
                documents: .notGranted,
                downloads: .notGranted,
            )
        })
    }

    nonisolated static var previewValue: FolderAccessClient {
        FolderAccessClient(requestAccess: {
            FolderAccessResult(
                desktop: .notGranted,
                documents: .notGranted,
                downloads: .notGranted,
            )
        })
    }
}

extension DependencyValues {
    nonisolated var folderAccessClient: FolderAccessClient {
        get { self[FolderAccessClient.self] }
        set { self[FolderAccessClient.self] = newValue }
    }
}
