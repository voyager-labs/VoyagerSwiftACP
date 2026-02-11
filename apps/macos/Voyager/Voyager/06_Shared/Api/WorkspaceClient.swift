import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

/// NSWorkspace 관련 기능을 제공하는 Client
public struct WorkspaceClient: Sendable {
    public var urlForApplication: @Sendable (String) -> URL?
    public var urlForApplicationToOpen: @Sendable (URL) -> URL?
    public var urlsForApplications: @Sendable (URL) -> [URL]
    public var iconForFile: @Sendable (String) -> NSImage
    public var iconForType: @Sendable (UTType) -> NSImage
    public var openApplication: @Sendable (URL) async throws -> Void
    public var openURL: @Sendable (URL) -> Bool
    public var currentEvent: @Sendable () -> NSEvent?

    public nonisolated init(
        urlForApplication: @escaping @Sendable (String) -> URL?,
        urlForApplicationToOpen: @escaping @Sendable (URL) -> URL?,
        urlsForApplications: @escaping @Sendable (URL) -> [URL],
        iconForFile: @escaping @Sendable (String) -> NSImage,
        iconForType: @escaping @Sendable (UTType) -> NSImage,
        openApplication: @escaping @Sendable (URL) async throws -> Void,
        openURL: @escaping @Sendable (URL) -> Bool,
        currentEvent: @escaping @Sendable () -> NSEvent?,
    ) {
        self.urlForApplication = urlForApplication
        self.urlForApplicationToOpen = urlForApplicationToOpen
        self.urlsForApplications = urlsForApplications
        self.iconForFile = iconForFile
        self.iconForType = iconForType
        self.openApplication = openApplication
        self.openURL = openURL
        self.currentEvent = currentEvent
    }
}

extension WorkspaceClient: DependencyKey {
    public nonisolated static var liveValue: WorkspaceClient {
        nonisolated(unsafe) let workspace = NSWorkspace.shared
        return WorkspaceClient(
            urlForApplication: { bundleID in
                workspace.urlForApplication(withBundleIdentifier: bundleID)
            },
            urlForApplicationToOpen: { url in
                workspace.urlForApplication(toOpen: url)
            },
            urlsForApplications: { url in
                workspace.urlsForApplications(toOpen: url)
            },
            iconForFile: { path in
                workspace.icon(forFile: path)
            },
            iconForType: { type in
                workspace.icon(for: type)
            },
            openApplication: { url in
                let config = NSWorkspace.OpenConfiguration()
                try await workspace.openApplication(at: url, configuration: config)
            },
            openURL: { url in
                workspace.open(url)
            },
            currentEvent: {
                NSApplication.shared.currentEvent
            },
        )
    }

    public nonisolated static var testValue: WorkspaceClient {
        WorkspaceClient(
            urlForApplication: { _ in nil },
            urlForApplicationToOpen: { _ in nil },
            urlsForApplications: { _ in [] },
            iconForFile: { _ in NSImage() },
            iconForType: { _ in NSImage() },
            openApplication: { _ in },
            openURL: { _ in false },
            currentEvent: { nil },
        )
    }

    public nonisolated static var previewValue: WorkspaceClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var workspaceClient: WorkspaceClient {
        get { self[WorkspaceClient.self] }
        set { self[WorkspaceClient.self] = newValue }
    }
}
