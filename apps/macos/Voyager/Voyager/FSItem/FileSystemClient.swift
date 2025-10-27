import AppKit
import ComposableArchitecture
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

public struct ApplicationInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String?
    public let isDefault: Bool

    public nonisolated init(id: String, name: String, bundleID: String?, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.isDefault = isDefault
    }
}

public struct FileSystemClient: Sendable {
    public var open: @Sendable (URL, OpenKind) async throws -> Void
    public var setDefaultApp: @Sendable (UTType, String) async throws -> Void
    public var quickLook: @Sendable (URL) async throws -> Void
    public var applicationsForFile: @Sendable (URL) async -> [ApplicationInfo]
    public var defaultApplication: @Sendable (UTType) async -> ApplicationInfo?
    public var createFolder: @Sendable (URL, String) async throws -> Void
    public var pasteFile: @Sendable (URL, URL) async throws -> Void
    public var moveFile: @Sendable (URL, URL) async throws -> Void

    public nonisolated init(
        open: @escaping @Sendable (URL, OpenKind) async throws -> Void,
        setDefaultApp: @escaping @Sendable (UTType, String) async throws -> Void,
        quickLook: @escaping @Sendable (URL) async throws -> Void,
        applicationsForFile: @escaping @Sendable (URL) async -> [ApplicationInfo],
        defaultApplication: @escaping @Sendable (UTType) async -> ApplicationInfo?,
        createFolder: @escaping @Sendable (URL, String) async throws -> Void,
        pasteFile: @escaping @Sendable (URL, URL) async throws -> Void,
        moveFile: @escaping @Sendable (URL, URL) async throws -> Void
    ) {
        self.open = open
        self.setDefaultApp = setDefaultApp
        self.quickLook = quickLook
        self.applicationsForFile = applicationsForFile
        self.defaultApplication = defaultApplication
        self.createFolder = createFolder
        self.pasteFile = pasteFile
        self.moveFile = moveFile
    }
}

public enum OpenKind: Equatable, Sendable {
    case defaultApp
    case bundleID(String)
}

public enum FileOpError: Error, Equatable, Sendable {
    case notFound
    case unsupportedType
    case cancelled
    case system(message: String, suggestion: String? = nil)

    public var message: String {
        switch self {
        case .notFound:
            return "The item could not be found."
        case .unsupportedType:
            return "This item type is not supported."
        case .cancelled:
            return "The operation was cancelled."
        case let .system(message, _):
            return message
        }
    }

    public var suggestion: String? {
        switch self {
        case let .system(_, hint):
            return hint
        default:
            return nil
        }
    }
}

extension FileSystemClient: DependencyKey {
    public nonisolated static var liveValue: FileSystemClient {
        FileSystemClient(
            open: { url, kind in
                try await withScopedAccess(url) {
                    let workspace = NSWorkspace.shared
                    switch kind {
                    case .defaultApp:
                        guard workspace.open(url) else {
                            throw FileOpError.system(message: "Failed to open item.")
                        }
                    case let .bundleID(bundleID):
                        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
                            throw FileOpError.notFound
                        }
                        let configuration = NSWorkspace.OpenConfiguration()
                        try await workspace.open([url], withApplicationAt: appURL, configuration: configuration)
                    }
                }
            },
            setDefaultApp: { type, bundleID in
                let status = LSSetDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    .all,
                    bundleID as CFString
                )
                guard status == noErr else {
                    throw FileOpError.system(message: "Failed to set default app.")
                }
            },
            quickLook: { url in
                try await withScopedAccess(url) {
                    let token = await MainActor.run { SecurityScopedURLToken(url: url) }
                    await FSItemQuickLookCoordinator.shared.present(url: url, scopeToken: token)
                }
            },
            applicationsForFile: { url in
                let workspace = NSWorkspace.shared
                let appURLs = workspace.urlsForApplications(toOpen: url)

                var seen = Set<String>()
                var apps: [ApplicationInfo] = []

                await withTaskGroup(of: ApplicationInfo?.self) { group in
                    for appURL in appURLs {
                        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier,
                              seen.insert(bundleID).inserted
                        else { continue }

                        group.addTask { @MainActor in
                            let name = FileManager.default.displayName(atPath: appURL.path)
                            return ApplicationInfo(id: bundleID, name: name, bundleID: bundleID)
                        }
                    }

                    for await app in group {
                        if let app = app {
                            apps.append(app)
                        }
                    }
                }

                return apps
            },
            defaultApplication: { fileType in
                guard #available(macOS 13.0, *) else { return nil }

                guard let defaultAppURL = LSCopyDefaultApplicationURLForContentType(
                    fileType.identifier as CFString,
                    .viewer,
                    nil
                )?.takeRetainedValue() as URL?,
                    let bundleID = Bundle(url: defaultAppURL)?.bundleIdentifier
                else { return nil }

                let name = await MainActor.run {
                    FileManager.default.displayName(atPath: defaultAppURL.path)
                }

                return await MainActor.run {
                    ApplicationInfo(id: bundleID, name: name, bundleID: bundleID)
                }
            },
            createFolder: { parentURL, folderName in
                let folderURL = parentURL.appendingPathComponent(folderName)
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: false,
                    attributes: nil
                )
            },
            pasteFile: { sourceURL, destinationURL in
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            },
            moveFile: { sourceURL, destinationURL in
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            }
        )
    }

    public nonisolated static var testValue: FileSystemClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("FileSystemClient test dependency not set.")
        }
        return FileSystemClient(
            open: { _, _ in unimplemented() },
            setDefaultApp: { _, _ in unimplemented() },
            quickLook: { _ in unimplemented() },
            applicationsForFile: { _ in unimplemented() },
            defaultApplication: { _ in unimplemented() },
            createFolder: { _, _ in unimplemented() },
            pasteFile: { _, _ in unimplemented() },
            moveFile: { _, _ in unimplemented() }
        )
    }

    public nonisolated static var previewValue: FileSystemClient {
        let previewInfo = ApplicationInfo(
            id: "com.apple.preview",
            name: "Preview",
            bundleID: "com.apple.preview"
        )
        let chromeInfo = ApplicationInfo(id: "com.google.Chrome", name: "Google Chrome", bundleID: "com.google.Chrome")
        let otherInfo = ApplicationInfo(id: "other", name: "Other…", bundleID: nil)

        return FileSystemClient(
            open: { _, _ in },
            setDefaultApp: { _, _ in },
            quickLook: { _ in },
            applicationsForFile: { _ async in
                [previewInfo, chromeInfo, otherInfo]
            },
            defaultApplication: { _ async in
                previewInfo
            },
            createFolder: { _, _ in },
            pasteFile: { _, _ in },
            moveFile: { _, _ in }
        )
    }
}

public extension DependencyValues {
    nonisolated var fileSystemClient: FileSystemClient {
        get { self[FileSystemClient.self] }
        set { self[FileSystemClient.self] = newValue }
    }
}

func withScopedAccess<T>(_ url: URL, perform: @escaping () async throws -> T) async throws -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try await perform()
}
