import AppKit
import ComposableArchitecture
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

public struct FileSystemClient: Sendable {
    public var open: @Sendable (URL, OpenKind) async throws -> Void
    public var setDefaultApp: @Sendable (UTType, String) async throws -> Void
    public var quickLook: @Sendable (URL) async throws -> Void

    public init(
        open: @escaping @Sendable (URL, OpenKind) async throws -> Void,
        setDefaultApp: @escaping @Sendable (UTType, String) async throws -> Void,
        quickLook: @escaping @Sendable (URL) async throws -> Void
    ) {
        self.open = open
        self.setDefaultApp = setDefaultApp
        self.quickLook = quickLook
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
    public static var liveValue: FileSystemClient {
        let workspace = NSWorkspace.shared

        return FileSystemClient(
            open: { url, kind in
                try await withScopedAccess(url) {
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
                let status = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, bundleID as CFString)
                guard status == noErr else {
                    throw FileOpError.system(message: "Failed to set default app.")
                }
            },
            quickLook: { url in
                try await withScopedAccess(url) {
                    let token = SecurityScopedURLToken(url: url)
                    await FSItemQuickLookCoordinator.shared.present(url: url, scopeToken: token)
                }
            }
        )
    }

    public static var testValue: FileSystemClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in fatalError("FileSystemClient test dependency not set.") }
        return FileSystemClient(
            open: { _, _ in unimplemented() },
            setDefaultApp: { _, _ in unimplemented() },
            quickLook: { _ in unimplemented() }
        )
    }

    public static var previewValue: FileSystemClient {
        FileSystemClient(
            open: { _, _ in },
            setDefaultApp: { _, _ in },
            quickLook: { _ in }
        )
    }
}

public extension DependencyValues {
    var fileSystemClient: FileSystemClient {
        get { self[FileSystemClient.self] }
        set { self[FileSystemClient.self] = newValue }
    }
}

func withScopedAccess<T>(_ url: URL, perform: @escaping () async throws -> T) async throws -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try await perform()
}
