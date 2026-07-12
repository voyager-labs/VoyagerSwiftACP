import AppKit
import ComposableArchitecture
import Foundation

public struct DirectorySelectionClient: Sendable {
    public var pickDirectory: @Sendable () async -> String?
    public var pathExists: @Sendable (_ path: String) -> Bool
    public var isDirectory: @Sendable (_ path: String) -> Bool
    public var defaultHomePath: @Sendable () -> String

    public init(
        pickDirectory: @escaping @Sendable () async -> String?,
        pathExists: @escaping @Sendable (_ path: String) -> Bool,
        isDirectory: @escaping @Sendable (_ path: String) -> Bool,
        defaultHomePath: @escaping @Sendable () -> String,
    ) {
        self.pickDirectory = pickDirectory
        self.pathExists = pathExists
        self.isDirectory = isDirectory
        self.defaultHomePath = defaultHomePath
    }
}

extension DirectorySelectionClient: DependencyKey {
    nonisolated public static var liveValue: DirectorySelectionClient {
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

    nonisolated public static var testValue: DirectorySelectionClient {
        DirectorySelectionClient(
            pickDirectory: { nil },
            pathExists: { _ in false },
            isDirectory: { _ in false },
            defaultHomePath: { "/" },
        )
    }
}

public extension DependencyValues {
    nonisolated var directorySelectionClient: DirectorySelectionClient {
        get { self[DirectorySelectionClient.self] }
        set { self[DirectorySelectionClient.self] = newValue }
    }
}
