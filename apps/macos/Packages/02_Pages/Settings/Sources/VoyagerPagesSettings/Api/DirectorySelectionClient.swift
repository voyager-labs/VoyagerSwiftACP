import AppKit
import ComposableArchitecture
import Foundation

struct DirectorySelectionClient {
    var pickDirectory: @Sendable () async -> String?
    var pathExists: @Sendable (_ path: String) -> Bool
    var isDirectory: @Sendable (_ path: String) -> Bool
    var defaultHomePath: @Sendable () -> String
}

extension DirectorySelectionClient: DependencyKey {
    nonisolated static var liveValue: DirectorySelectionClient {
        DirectorySelectionClient(
            pickDirectory: {
                await MainActor.run {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.title = "Select Starting Directory"

                    let response = panel.runModal()
                    if response == .OK, let url = panel.url {
                        return url.path
                    }
                    return nil
                }
            },
            pathExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            isDirectory: { path in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            },
            defaultHomePath: {
                FileManager.default.homeDirectoryForCurrentUser.path
            },
        )
    }

    nonisolated static var testValue: DirectorySelectionClient {
        DirectorySelectionClient(
            pickDirectory: { nil },
            pathExists: { _ in false },
            isDirectory: { _ in false },
            defaultHomePath: { "/" },
        )
    }
}

extension DependencyValues {
    var directorySelectionClient: DirectorySelectionClient {
        get { self[DirectorySelectionClient.self] }
        set { self[DirectorySelectionClient.self] = newValue }
    }
}
