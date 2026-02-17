import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

enum EntryOpenLive {
    nonisolated static var open: @Sendable (URL, OpenKind) async throws -> Void {
        { url, kind in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

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
    }

    nonisolated static var quickLook: @Sendable (URL) async throws -> Void {
        { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let token = await MainActor.run { EntryQuickLookSecurityScopedURLToken(url: url) }
            await EntryQuickLookController.shared.present(url: url, scopeToken: token)
        }
    }

    nonisolated static var quickLookFiles: @Sendable ([URL]) async throws -> Void {
        { urls in
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, isScoped) in zip(urls, scoped) where isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let tokens = await MainActor.run { urls.map(EntryQuickLookSecurityScopedURLToken.init) }
            await EntryQuickLookController.shared.present(urls: urls, scopeTokens: tokens, initialIndex: 0)
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

            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
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
        { url in
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
                    if let app {
                        apps.append(app)
                    }
                }
            }

            return apps
        }
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
                ApplicationInfo(id: bundleID, name: name, bundleID: bundleID)
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
