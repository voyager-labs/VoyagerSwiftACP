import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

public struct WorkspaceClient: Sendable {
    public var urlForApplication: @Sendable (String) -> URL?
    public var urlForApplicationToOpen: @Sendable (URL) -> URL?
    public var urlsForApplications: @Sendable (URL) -> [URL]
    public var iconForFile: @Sendable (String) -> NSImage
    public var iconForType: @Sendable (UTType) -> NSImage
    public var openApplication: @Sendable (URL) async throws -> Void
    public var openURL: @Sendable (URL) -> Bool
    public var currentEvent: @Sendable () -> NSEvent?
    public var runningApplications: @Sendable () -> [NSRunningApplication]
    public var activateFileViewerSelecting: @Sendable ([URL]) -> Void
    public var openURLsWithApplication: @Sendable ([URL], URL, Bool, [String: String]?) async throws -> Void
    public var openApplicationAtURL: @Sendable (URL, Bool, [String: String]?) async throws -> Void
    public var addWorkspaceNotificationObserver: @Sendable (
        NSNotification.Name?,
        Any?,
        OperationQueue?,
        @escaping (Notification) -> Void,
    ) -> NSObjectProtocol
    public var removeWorkspaceNotificationObserver: @Sendable (NSObjectProtocol) -> Void

    public nonisolated init(
        urlForApplication: @escaping @Sendable (String) -> URL?,
        urlForApplicationToOpen: @escaping @Sendable (URL) -> URL?,
        urlsForApplications: @escaping @Sendable (URL) -> [URL],
        iconForFile: @escaping @Sendable (String) -> NSImage,
        iconForType: @escaping @Sendable (UTType) -> NSImage,
        openApplication: @escaping @Sendable (URL) async throws -> Void,
        openURL: @escaping @Sendable (URL) -> Bool,
        currentEvent: @escaping @Sendable () -> NSEvent?,
        runningApplications: @escaping @Sendable () -> [NSRunningApplication],
        activateFileViewerSelecting: @escaping @Sendable ([URL]) -> Void,
        openURLsWithApplication: @escaping @Sendable ([URL], URL, Bool, [String: String]?) async throws -> Void,
        openApplicationAtURL: @escaping @Sendable (URL, Bool, [String: String]?) async throws -> Void,
        addWorkspaceNotificationObserver: @escaping @Sendable (
            NSNotification.Name?,
            Any?,
            OperationQueue?,
            @escaping (Notification) -> Void,
        ) -> NSObjectProtocol,
        removeWorkspaceNotificationObserver: @escaping @Sendable (NSObjectProtocol) -> Void,
    ) {
        self.urlForApplication = urlForApplication
        self.urlForApplicationToOpen = urlForApplicationToOpen
        self.urlsForApplications = urlsForApplications
        self.iconForFile = iconForFile
        self.iconForType = iconForType
        self.openApplication = openApplication
        self.openURL = openURL
        self.currentEvent = currentEvent
        self.runningApplications = runningApplications
        self.activateFileViewerSelecting = activateFileViewerSelecting
        self.openURLsWithApplication = openURLsWithApplication
        self.openApplicationAtURL = openApplicationAtURL
        self.addWorkspaceNotificationObserver = addWorkspaceNotificationObserver
        self.removeWorkspaceNotificationObserver = removeWorkspaceNotificationObserver
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
                nil
            },
            runningApplications: {
                workspace.runningApplications
            },
            activateFileViewerSelecting: { urls in
                workspace.activateFileViewerSelecting(urls)
            },
            openURLsWithApplication: { urls, appURL, createsNewInstance, environment in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = createsNewInstance
                if let environment {
                    configuration.environment = environment
                }
                try await workspace.open(urls, withApplicationAt: appURL, configuration: configuration)
            },
            openApplicationAtURL: { url, activates, environment in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = activates
                if let environment {
                    configuration.environment = environment
                }
                try await workspace.openApplication(at: url, configuration: configuration)
            },
            addWorkspaceNotificationObserver: { name, object, queue, handler in
                workspace.notificationCenter.addObserver(forName: name, object: object, queue: queue, using: handler)
            },
            removeWorkspaceNotificationObserver: { observer in
                workspace.notificationCenter.removeObserver(observer)
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
            runningApplications: { [] },
            activateFileViewerSelecting: { _ in },
            openURLsWithApplication: { _, _, _, _ in },
            openApplicationAtURL: { _, _, _ in },
            addWorkspaceNotificationObserver: { _, _, _, _ in NSObject() },
            removeWorkspaceNotificationObserver: { _ in },
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
