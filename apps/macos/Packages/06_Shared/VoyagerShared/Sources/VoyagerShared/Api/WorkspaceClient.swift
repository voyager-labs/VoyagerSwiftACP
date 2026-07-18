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

    nonisolated public init(
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

private struct SendableWorkspaceImage: @unchecked Sendable {
    let value: NSImage
}

public extension WorkspaceClient {
    func iconForFileAsync(_ path: String) async -> NSImage {
        let image = await Task.detached(priority: .userInitiated) {
            SendableWorkspaceImage(value: iconForFile(path))
        }.value
        return image.value
    }
}

extension WorkspaceClient: DependencyKey {
    private static let iCloudDriveIconPath =
        "/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Resources/iCloudDrive.icns"

    nonisolated private static func resolvedIcon(
        forFile path: String,
        workspace: NSWorkspace,
        cloudStorageIconIndex: CloudStorageApplicationIconIndex,
    ) -> NSImage {
        let url = URL(fileURLWithPath: path)

        if url.lastPathComponent == ".Trash",
           let trashIcon = NSImage(named: NSImage.trashEmptyName)
        {
            return trashIcon
        }

        if isICloudDriveURL(url) {
            if let iCloudIcon = NSImage(contentsOfFile: iCloudDriveIconPath) {
                iCloudIcon.isTemplate = false
                return iCloudIcon
            }
        }

        if let cloudStorageIcon = cloudStorageIconIndex.icon(forProviderRoot: url) {
            return cloudStorageIcon
        }

        if let resourceValues = try? url.resourceValues(forKeys: [.effectiveIconKey]),
           let effectiveIcon = resourceValues.effectiveIcon as? NSImage,
           effectiveIcon.size.width > 0,
           effectiveIcon.size.height > 0
        {
            return effectiveIcon
        }

        return workspace.icon(forFile: path)
    }

    nonisolated private static func isICloudDriveURL(_ url: URL) -> Bool {
        url.lastPathComponent == "com~apple~CloudDocs"
            && url.deletingLastPathComponent().lastPathComponent == "Mobile Documents"
    }

    nonisolated public static var liveValue: WorkspaceClient {
        nonisolated(unsafe) let workspace = NSWorkspace.shared
        let cloudStorageIconIndex = CloudStorageApplicationIconIndex(
            fileManager: FileManager.default,
            workspace: workspace,
        )
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
                resolvedIcon(
                    forFile: path,
                    workspace: workspace,
                    cloudStorageIconIndex: cloudStorageIconIndex,
                )
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

    nonisolated public static var testValue: WorkspaceClient {
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

    nonisolated public static var previewValue: WorkspaceClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var workspaceClient: WorkspaceClient {
        get { self[WorkspaceClient.self] }
        set { self[WorkspaceClient.self] = newValue }
    }
}
