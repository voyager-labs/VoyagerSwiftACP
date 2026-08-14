import AppKit
import ComposableArchitecture
import CoreServices
import Foundation
import UniformTypeIdentifiers
import VoyagerShared

public struct EntryOpenClient: Sendable {
    public var open: @Sendable (URL, OpenKind) async throws -> Void
    public var setDefaultApp: @Sendable (UTType, String) async throws -> Void
    public var openFinderInfo: @Sendable ([URL]) async throws -> Void
    public var shareItems: @Sendable ([URL], CGPoint?) async throws -> Void
    public var performService: @Sendable (String, [URL]) async throws -> Void
    public var revealInFinder: @Sendable ([URL]) async throws -> Void
    public var applicationsForFile: @Sendable (URL) async -> [ApplicationInfo]
    public var applicationsForType: @Sendable (UTType, URL) async -> [ApplicationInfo]
    public var invalidateApplicationsForType: @Sendable (String) async -> Void
    public var defaultApplication: @Sendable (UTType) async -> ApplicationInfo?
    public var trashDirectoryPath: @Sendable () -> String?

    nonisolated public init(
        open: @escaping @Sendable (URL, OpenKind) async throws -> Void,
        setDefaultApp: @escaping @Sendable (UTType, String) async throws -> Void,
        openFinderInfo: @escaping @Sendable ([URL]) async throws -> Void,
        shareItems: @escaping @Sendable ([URL], CGPoint?) async throws -> Void,
        performService: @escaping @Sendable (String, [URL]) async throws -> Void,
        revealInFinder: @escaping @Sendable ([URL]) async throws -> Void,
        applicationsForFile: @escaping @Sendable (URL) async -> [ApplicationInfo],
        applicationsForType: @escaping @Sendable (UTType, URL) async -> [ApplicationInfo],
        invalidateApplicationsForType: @escaping @Sendable (String) async -> Void,
        defaultApplication: @escaping @Sendable (UTType) async -> ApplicationInfo?,
        trashDirectoryPath: @escaping @Sendable () -> String?,
    ) {
        self.open = open
        self.setDefaultApp = setDefaultApp
        self.openFinderInfo = openFinderInfo
        self.shareItems = shareItems
        self.performService = performService
        self.revealInFinder = revealInFinder
        self.applicationsForFile = applicationsForFile
        self.applicationsForType = applicationsForType
        self.invalidateApplicationsForType = invalidateApplicationsForType
        self.defaultApplication = defaultApplication
        self.trashDirectoryPath = trashDirectoryPath
    }
}

actor ApplicationDiscoveryCache {
    private var cached: [String: [ApplicationInfo]] = [:]
    private var inFlight: [String: Task<[ApplicationInfo], Never>] = [:]
    private var generations: [String: Int] = [:]

    func applications(
        for typeID: String,
        load: @escaping @Sendable () async -> [ApplicationInfo],
    ) async -> [ApplicationInfo] {
        if let cached = cached[typeID] { return cached }
        if let task = inFlight[typeID] { return await task.value }
        let generation = generations[typeID, default: 0]
        let task = Task { await load() }
        inFlight[typeID] = task
        let apps = await task.value
        if generations[typeID, default: 0] == generation {
            cached[typeID] = apps
            inFlight[typeID] = nil
        }
        return apps
    }

    func invalidate(_ typeID: String) {
        cached[typeID] = nil
        generations[typeID, default: 0] += 1
        inFlight[typeID]?.cancel()
        inFlight[typeID] = nil
    }
}

extension EntryOpenClient: DependencyKey {
    fileprivate static let applicationDiscoveryCache = ApplicationDiscoveryCache()
    nonisolated public static var liveValue: EntryOpenClient {
        EntryOpenClient(
            open: EntryOpenLive.open,
            setDefaultApp: EntryOpenLive.setDefaultApp,
            openFinderInfo: EntryOpenLive.openFinderInfo,
            shareItems: EntryOpenLive.shareItems,
            performService: EntryOpenLive.performService,
            revealInFinder: EntryOpenLive.revealInFinder,
            applicationsForFile: EntryOpenLive.applicationsForFile,
            applicationsForType: EntryOpenLive.applicationsForType,
            invalidateApplicationsForType: EntryOpenLive.invalidateApplicationsForType,
            defaultApplication: EntryOpenLive.defaultApplication,
            trashDirectoryPath: EntryLoadingLive.trashDirectoryPath,
        )
    }

    nonisolated public static var testValue: EntryOpenClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryOpenClient test dependency not set.")
        }
        return EntryOpenClient(
            open: { _, _ in unimplemented() },
            setDefaultApp: { _, _ in unimplemented() },
            openFinderInfo: { _ in unimplemented() },
            shareItems: { _, _ in unimplemented() },
            performService: { _, _ in unimplemented() },
            revealInFinder: { _ in unimplemented() },
            applicationsForFile: { _ in unimplemented() },
            applicationsForType: { _, _ in unimplemented() },
            invalidateApplicationsForType: { _ in },
            defaultApplication: { _ in unimplemented() },
            trashDirectoryPath: { nil },
        )
    }

    nonisolated public static var previewValue: EntryOpenClient {
        let previewInfo = ApplicationInfo(
            id: "com.apple.preview",
            name: "Preview",
            bundleID: "com.apple.preview",
        )
        let chromeInfo = ApplicationInfo(id: "com.google.Chrome", name: "Google Chrome", bundleID: "com.google.Chrome")

        return EntryOpenClient(
            open: { _, _ in },
            setDefaultApp: { _, _ in },
            openFinderInfo: { _ in },
            shareItems: { _, _ in },
            performService: { _, _ in },
            revealInFinder: { _ in },
            applicationsForFile: { _ async in
                [previewInfo, chromeInfo]
            },
            applicationsForType: { _, _ async in
                [previewInfo, chromeInfo]
            },
            invalidateApplicationsForType: { _ in },
            defaultApplication: { _ async in
                previewInfo
            },
            trashDirectoryPath: { nil },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryOpenClient: EntryOpenClient {
        get { self[EntryOpenClient.self] }
        set { self[EntryOpenClient.self] = newValue }
    }
}

enum EntryOpenLive {
    nonisolated static var open: @Sendable (URL, OpenKind) async throws -> Void {
        let workspaceClient = WorkspaceClient.liveValue
        return { url, kind in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            switch kind {
            case .defaultApp:
                guard workspaceClient.openURL(url) else {
                    throw FileOpError.system(message: "Failed to open item.")
                }
            case let .bundleID(bundleID):
                guard let appURL = workspaceClient.urlForApplication(bundleID) else {
                    throw FileOpError.notFound
                }
                try await workspaceClient.openURLsWithApplication([url], appURL, false, nil)
            }
        }
    }

    nonisolated static var openFinderInfo: @Sendable ([URL]) async throws -> Void {
        { urls in
            guard !urls.isEmpty else { return }
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, isScoped) in zip(urls, scoped) where isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let error = await MainActor.run { () -> FileOpError? in
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerGetInfo-\(UUID().uuidString)"))
                pasteboard.clearContents()

                let paths = urls.map(\.path)
                pasteboard.setPropertyList(paths, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))

                let success = NSPerformService("Finder/Show Info", pasteboard)

                if !success {
                    return .system(message: "Failed to open Get Info window.")
                }

                return nil
            }

            if let error {
                throw error
            }
        }
    }

    nonisolated static var shareItems: @Sendable ([URL], CGPoint?) async throws -> Void {
        { urls, anchor in
            guard !urls.isEmpty else { return }
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, isScoped) in zip(urls, scoped) where isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let error = await MainActor.run { () -> FileOpError? in
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
                      let view = window.contentView
                else {
                    return .system(message: "No active window to share from.")
                }

                let picker = NSSharingServicePicker(items: urls)
                let rect = shareAnchorRect(
                    in: view,
                    window: window,
                    event: NSApp.currentEvent,
                    screenPoint: anchor,
                )
                picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
                return nil
            }

            if let error {
                throw error
            }
        }
    }

    nonisolated static var performService: @Sendable (String, [URL]) async throws -> Void {
        { serviceName, urls in
            guard !urls.isEmpty else { return }
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, isScoped) in zip(urls, scoped) where isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let error = await MainActor.run { () -> FileOpError? in
                NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
                NSApp.servicesMenu?.update()

                let pasteboard = NSPasteboard(
                    name: NSPasteboard.Name("VoyagerServices-\(UUID().uuidString)"),
                )
                pasteboard.clearContents()
                pasteboard.writeObjects(urls as [NSURL])

                let success = NSPerformService(serviceName, pasteboard)
                if !success {
                    return .system(message: "Failed to run service: \(serviceName)")
                }
                return nil
            }

            if let error {
                throw error
            }
        }
    }

    nonisolated static var revealInFinder: @Sendable ([URL]) async throws -> Void {
        { urls in
            guard !urls.isEmpty else { return }
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, isScoped) in zip(urls, scoped) where isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try EntryFinderReveal.reveal(urls)
        }
    }

    nonisolated static var setDefaultApp: @Sendable (UTType, String) async throws -> Void {
        { type, bundleID in
            let status = LSSetDefaultRoleHandlerForContentType(
                type.identifier as CFString,
                .all,
                bundleID as CFString,
            )
            guard status == noErr else {
                throw FileOpError.system(message: "Failed to set default app.")
            }
        }
    }

    nonisolated static var applicationsForFile: @Sendable (URL) async -> [ApplicationInfo] {
        let workspaceClient = WorkspaceClient.liveValue
        return { url in
            let appURLs = workspaceClient.urlsForApplications(url)

            var seen = Set<String>()
            var apps: [ApplicationInfo] = []

            await withTaskGroup(of: ApplicationInfo?.self) { group in
                for appURL in appURLs {
                    guard let bundleID = Bundle(url: appURL)?.bundleIdentifier,
                          seen.insert(bundleID).inserted
                    else { continue }

                    group.addTask { @MainActor in
                        let name = FileManager.default.displayName(atPath: appURL.path)
                        return ApplicationInfo(
                            id: bundleID,
                            name: name,
                            bundleID: bundleID,
                            applicationURL: appURL,
                        )
                    }
                }

                for await app in group {
                    if let app {
                        apps.append(app)
                    }
                }
            }

            return apps
        }
    }

    nonisolated static var applicationsForType: @Sendable (UTType, URL) async -> [ApplicationInfo] {
        let cache = EntryOpenClient.applicationDiscoveryCache
        let loadApplications = applicationsForFile
        return { type, url in
            await cache.applications(for: type.identifier) {
                await loadApplications(url)
            }
        }
    }

    nonisolated static var invalidateApplicationsForType: @Sendable (String) async -> Void {
        let cache = EntryOpenClient.applicationDiscoveryCache
        return { typeID in await cache.invalidate(typeID) }
    }

    nonisolated static var defaultApplication: @Sendable (UTType) async -> ApplicationInfo? {
        { fileType in
            guard #available(macOS 13.0, *) else { return nil }

            guard let defaultAppURL = LSCopyDefaultApplicationURLForContentType(
                fileType.identifier as CFString,
                .all,
                nil,
            )?.takeRetainedValue() as URL?,
                let bundleID = Bundle(url: defaultAppURL)?.bundleIdentifier
            else { return nil }

            let name = await MainActor.run {
                FileManager.default.displayName(atPath: defaultAppURL.path)
            }
            return await MainActor.run {
                ApplicationInfo(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID,
                    applicationURL: defaultAppURL,
                )
            }
        }
    }
}

@MainActor
private func shareAnchorRect(
    in view: NSView,
    window: NSWindow,
    event: NSEvent?,
    screenPoint: CGPoint?,
) -> CGRect {
    if let screenPoint {
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = view.convert(windowPoint, from: nil)
        return CGRect(x: viewPoint.x, y: viewPoint.y, width: 1, height: 1)
    }

    if let event, event.window == window {
        let location = view.convert(event.locationInWindow, from: nil)
        return CGRect(x: location.x, y: location.y, width: 1, height: 1)
    }

    let bounds = view.bounds
    return CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
}
