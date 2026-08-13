import AppKit
import ComposableArchitecture
import Foundation

public struct StandardDirectories: Equatable, Sendable {
    public let homePath: String
    public let homeDisplayName: String
    public let desktopPath: String?
    public let documentsPath: String?
    public let downloadsPath: String?

    public init(
        homePath: String,
        homeDisplayName: String,
        desktopPath: String?,
        documentsPath: String?,
        downloadsPath: String?,
    ) {
        self.homePath = homePath
        self.homeDisplayName = homeDisplayName
        self.desktopPath = desktopPath
        self.documentsPath = documentsPath
        self.downloadsPath = downloadsPath
    }

    nonisolated static let defaultValue = StandardDirectories(
        homePath: "/",
        homeDisplayName: "Home",
        desktopPath: "/Desktop",
        documentsPath: "/Documents",
        downloadsPath: "/Downloads",
    )
}

public struct DirectorySelectionClient: Sendable {
    public var pickDirectory: @Sendable () async -> String?
    public var pathExists: @Sendable (_ path: String) -> Bool
    public var isDirectory: @Sendable (_ path: String) -> Bool
    public var standardDirectories: @Sendable () -> StandardDirectories

    public init(
        pickDirectory: @escaping @Sendable () async -> String?,
        pathExists: @escaping @Sendable (_ path: String) -> Bool,
        isDirectory: @escaping @Sendable (_ path: String) -> Bool,
        standardDirectories: @escaping @Sendable () -> StandardDirectories,
    ) {
        self.pickDirectory = pickDirectory
        self.pathExists = pathExists
        self.isDirectory = isDirectory
        self.standardDirectories = standardDirectories
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
            standardDirectories: {
                let fileManager = FileManager.default
                let homeDirectory = fileManager.homeDirectoryForCurrentUser
                return StandardDirectories(
                    homePath: homeDirectory.path,
                    homeDisplayName: homeDirectory.lastPathComponent,
                    desktopPath: fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.path,
                    documentsPath: fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path,
                    downloadsPath: fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
                )
            },
        )
    }

    nonisolated public static var testValue: DirectorySelectionClient {
        DirectorySelectionClient(
            pickDirectory: { nil },
            pathExists: { _ in false },
            isDirectory: { _ in false },
            standardDirectories: { .defaultValue },
        )
    }
}

public extension DependencyValues {
    nonisolated var directorySelectionClient: DirectorySelectionClient {
        get { self[DirectorySelectionClient.self] }
        set { self[DirectorySelectionClient.self] = newValue }
    }
}
