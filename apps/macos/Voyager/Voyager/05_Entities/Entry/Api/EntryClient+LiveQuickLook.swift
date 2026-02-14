import AppKit
import Foundation

extension EntrySystemPrimitives {
    nonisolated static var liveOpen: @Sendable (URL, OpenKind) async throws -> Void {
        { url, kind in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

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

    nonisolated static var liveQuickLook: @Sendable (URL) async throws -> Void {
        { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let token = await MainActor.run { EntryQuickLookSecurityScopedURLToken(url: url) }
            await EntryQuickLookController.shared.present(url: url, scopeToken: token)
        }
    }

    nonisolated static var liveQuickLookFiles: @Sendable ([URL]) async throws -> Void {
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

    nonisolated static var liveOpenFinderInfo: @Sendable ([URL]) async throws -> Void {
        { urls in
            guard !urls.isEmpty else { return }
            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
            defer {
                for (url, isScoped) in zip(urls, scoped) where isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let error = await MainActor.run { () -> FileOpError? in
                // Use NSPerformService instead of AppleScript to avoid requiring
                // NSAppleEventsUsageDescription and Automation permissions
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerGetInfo-\(UUID().uuidString)"))
                pasteboard.clearContents()

                // Set file paths to pasteboard
                let paths = urls.map(\.path)
                pasteboard.setPropertyList(paths, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))

                // Invoke Finder's "Show Info" service
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

    nonisolated static var liveShareItems: @Sendable ([URL], CGPoint?) async throws -> Void {
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

    nonisolated static var livePerformService: @Sendable (String, [URL]) async throws -> Void {
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

    nonisolated static var liveRevealInFinder: @Sendable ([URL]) async throws -> Void {
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

    nonisolated static var liveSaveDragPaths: @Sendable ([String]) -> Void {
        { paths in
            // 커스텀 Pasteboard 사용 (drag는 시스템 전용)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            pasteboard.clearContents()
            let pathString = paths.joined(separator: "\n")
            pasteboard.setString(pathString, forType: .string)
        }
    }

    nonisolated static var liveLoadDragPaths: @Sendable () -> [String] {
        {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            guard let pathString = pasteboard.string(forType: .string),
                  !pathString.isEmpty
            else {
                return []
            }
            return pathString.split(separator: "\n").map(String.init)
        }
    }

    nonisolated static var liveSaveDragWithOption: @Sendable (Bool) -> Void {
        { isOptionPressed in
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            pasteboard.setString(
                isOptionPressed ? "true" : "false",
                forType: NSPasteboard.PasteboardType("VoyagerDragOption"),
            )
        }
    }

    nonisolated static var liveLoadDragWithOption: @Sendable () -> Bool {
        {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            let optionString = pasteboard.string(forType: NSPasteboard.PasteboardType("VoyagerDragOption"))
            return optionString == "true"
        }
    }

    nonisolated static var liveLoadClipboardPaths: @Sendable () -> ([String], ClipboardOperation) {
        {
            let pasteboard = NSPasteboard.general

            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
                return ([], .copy)
            }

            let paths = urls.map(\.path)

            let opString = pasteboard
                .string(forType: NSPasteboard.PasteboardType("com.voyager.clipboard.operation"))
            let operation: ClipboardOperation = opString == "cut" ? .cut : .copy

            return (paths, operation)
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
    // TODO: 좌표 기반 앵커링을 엔트리(셀/행) 프레임 기준으로 전환해야 함
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
