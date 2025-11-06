// swiftlint:disable file_length
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
    public var renameFile: @Sendable (URL, URL) async throws -> Void
    public var moveToTrash: @Sendable (URL) async throws -> Void
    public var deleteImmediately: @Sendable (URL) async throws -> Void
    public var putBackFromTrash: @Sendable (URL, String) async throws -> Void
    public var compressItems: @Sendable ([URL]) async throws -> URL
    public var loadItems: @Sendable (URL, Bool) async throws -> [FSItem]
    public var fileExists: @Sendable (String) -> Bool
    public var saveDragPaths: @Sendable ([String]) -> Void
    public var loadDragPaths: @Sendable () -> [String]
    public var saveDragWithOption: @Sendable (Bool) -> Void
    public var loadDragWithOption: @Sendable () -> Bool
    public var saveClipboardPaths: @Sendable ([String], ClipboardOperation) -> Void
    public var loadClipboardPaths: @Sendable () -> ([String], ClipboardOperation)
    public var postFileSystemChanged: @Sendable ([String]) -> Void
    public var observeFileSystemChanged: @Sendable () -> AsyncStream<[String]>

    public nonisolated init(
        open: @escaping @Sendable (URL, OpenKind) async throws -> Void,
        setDefaultApp: @escaping @Sendable (UTType, String) async throws -> Void,
        quickLook: @escaping @Sendable (URL) async throws -> Void,
        applicationsForFile: @escaping @Sendable (URL) async -> [ApplicationInfo],
        defaultApplication: @escaping @Sendable (UTType) async -> ApplicationInfo?,
        createFolder: @escaping @Sendable (URL, String) async throws -> Void,
        pasteFile: @escaping @Sendable (URL, URL) async throws -> Void,
        moveFile: @escaping @Sendable (URL, URL) async throws -> Void,
        renameFile: @escaping @Sendable (URL, URL) async throws -> Void,
        moveToTrash: @escaping @Sendable (URL) async throws -> Void,
        deleteImmediately: @escaping @Sendable (URL) async throws -> Void,
        putBackFromTrash: @escaping @Sendable (URL, String) async throws -> Void,
        compressItems: @escaping @Sendable ([URL]) async throws -> URL,
        loadItems: @escaping @Sendable (URL, Bool) async throws -> [FSItem],
        fileExists: @escaping @Sendable (String) -> Bool,
        saveDragPaths: @escaping @Sendable ([String]) -> Void,
        loadDragPaths: @escaping @Sendable () -> [String],
        saveDragWithOption: @escaping @Sendable (Bool) -> Void,
        loadDragWithOption: @escaping @Sendable () -> Bool,
        saveClipboardPaths: @escaping @Sendable ([String], ClipboardOperation) -> Void,
        loadClipboardPaths: @escaping @Sendable () -> ([String], ClipboardOperation),
        postFileSystemChanged: @escaping @Sendable ([String]) -> Void,
        observeFileSystemChanged: @escaping @Sendable () -> AsyncStream<[String]>
    ) {
        self.open = open
        self.setDefaultApp = setDefaultApp
        self.quickLook = quickLook
        self.applicationsForFile = applicationsForFile
        self.defaultApplication = defaultApplication
        self.createFolder = createFolder
        self.pasteFile = pasteFile
        self.moveFile = moveFile
        self.renameFile = renameFile
        self.moveToTrash = moveToTrash
        self.deleteImmediately = deleteImmediately
        self.putBackFromTrash = putBackFromTrash
        self.compressItems = compressItems
        self.loadItems = loadItems
        self.fileExists = fileExists
        self.saveDragPaths = saveDragPaths
        self.loadDragPaths = loadDragPaths
        self.saveDragWithOption = saveDragWithOption
        self.loadDragWithOption = loadDragWithOption
        self.saveClipboardPaths = saveClipboardPaths
        self.loadClipboardPaths = loadClipboardPaths
        self.postFileSystemChanged = postFileSystemChanged
        self.observeFileSystemChanged = observeFileSystemChanged
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
    case fileExists(itemName: String)
    case system(message: String, suggestion: String? = nil)

    public var message: String {
        switch self {
        case .notFound:
            return "The item could not be found."
        case .unsupportedType:
            return "This item type is not supported."
        case .cancelled:
            return "The operation was cancelled."
        case let .fileExists(itemName):
            return "A newer item named \"\(itemName)\" already exists in this location."
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

    public var isFileExists: Bool {
        if case .fileExists = self {
            return true
        }
        return false
    }

    public var itemName: String? {
        if case let .fileExists(name) = self {
            return name
        }
        return nil
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
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            },
            moveFile: { sourceURL, destinationURL in
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
                }
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            },
            renameFile: { sourceURL, destinationURL in
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
                }
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            },
            moveToTrash: { url in
                try await MainActor.run {
                    var result: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                }
            },
            deleteImmediately: { url in
                try FileManager.default.removeItem(at: url)
            },
            putBackFromTrash: { trashURL, originalPath in
                let originalURL = URL(fileURLWithPath: originalPath)

                let parentURL = originalURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentURL.path) {
                    try FileManager.default.createDirectory(
                        at: parentURL,
                        withIntermediateDirectories: true
                    )
                }

                if FileManager.default.fileExists(atPath: originalURL.path) {
                    throw FileOpError.fileExists(itemName: originalURL.lastPathComponent)
                }

                try FileManager.default.moveItem(at: trashURL, to: originalURL)

                await TrashMetadataStore.shared.remove(trashPath: trashURL.path)
            },
            compressItems: { itemURLs in
                guard !itemURLs.isEmpty else {
                    throw FileOpError.system(message: "No items to compress")
                }

                let parentURL = itemURLs[0].deletingLastPathComponent()

                let archiveName: String
                if itemURLs.count == 1 {
                    let itemName = itemURLs[0].lastPathComponent
                    archiveName = "\(itemName).zip"
                } else {
                    archiveName = "Archive.zip"
                }

                var archiveURL = parentURL.appendingPathComponent(archiveName)
                var counter = 2
                while FileManager.default.fileExists(atPath: archiveURL.path) {
                    let baseName = archiveName.replacingOccurrences(of: ".zip", with: "")
                    archiveURL = parentURL.appendingPathComponent("\(baseName) \(counter).zip")
                    counter += 1
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = parentURL

                var arguments = ["-r", "-q", archiveURL.lastPathComponent]
                for itemURL in itemURLs {
                    arguments.append(itemURL.lastPathComponent)
                }
                process.arguments = arguments

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    throw FileOpError.system(message: "Compression failed")
                }

                return archiveURL
            },
            loadItems: { directoryURL, showHidden in
                try await Task.detached {
                    let fileManager = FileManager.default
                    let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]

                    let contents = try fileManager.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: [
                            .nameKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .contentTypeKey,
                            .isDirectoryKey,
                            .isHiddenKey,
                            .labelColorKey,
                            .tagNamesKey,
                        ],
                        options: options
                    )

                    return contents.compactMap { FSItemsLoadUtils.convertURLToFSItem($0) }
                }.value
            },
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            saveDragPaths: { paths in
                // 커스텀 Pasteboard 사용 (drag는 시스템 전용)
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
                pasteboard.clearContents()
                let pathString = paths.joined(separator: "\n")
                pasteboard.setString(pathString, forType: .string)
            },
            loadDragPaths: {
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
                guard let pathString = pasteboard.string(forType: .string),
                      !pathString.isEmpty
                else {
                    return []
                }
                return pathString.split(separator: "\n").map(String.init)
            },
            saveDragWithOption: { isOptionPressed in
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
                pasteboard.setString(isOptionPressed ? "true" : "false",
                                     forType: NSPasteboard.PasteboardType("VoyagerDragOption"))
            },
            loadDragWithOption: {
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
                let optionString = pasteboard.string(forType: NSPasteboard.PasteboardType("VoyagerDragOption"))
                return optionString == "true"
            },
            saveClipboardPaths: { paths, operation in
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerClipboard"))
                pasteboard.clearContents()
                let pathString = paths.joined(separator: "\n")
                pasteboard.setString(pathString, forType: .string)

                switch operation {
                case .copy:
                    pasteboard.setString("copy", forType: NSPasteboard.PasteboardType("VoyagerClipboardOperation"))
                case .cut:
                    pasteboard.setString("cut", forType: NSPasteboard.PasteboardType("VoyagerClipboardOperation"))
                }
            },
            loadClipboardPaths: {
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerClipboard"))
                guard let pathString = pasteboard.string(forType: .string),
                      !pathString.isEmpty
                else {
                    return ([], .copy)
                }
                let paths = pathString.split(separator: "\n").map(String.init)
                let opString = pasteboard.string(forType: NSPasteboard.PasteboardType("VoyagerClipboardOperation"))
                let operation: ClipboardOperation = opString == "cut" ? .cut : .copy
                return (paths, operation)
            },
            postFileSystemChanged: { paths in
                let notificationName = NSNotification.Name("VoyagerFileSystemChanged")
                NotificationCenter.default.post(
                    name: notificationName,
                    object: nil,
                    userInfo: ["paths": paths]
                )
            },
            observeFileSystemChanged: {
                AsyncStream { continuation in
                    final class ObserverBox: @unchecked Sendable {
                        var observer: (any NSObjectProtocol)?
                        let center = NotificationCenter.default
                    }

                    let notificationName = NSNotification.Name("VoyagerFileSystemChanged")
                    let box = ObserverBox()
                    box.observer = box.center.addObserver(
                        forName: notificationName,
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let paths = notification.userInfo?["paths"] as? [String] {
                            continuation.yield(paths)
                        }
                    }

                    continuation.onTermination = { @Sendable _ in
                        if let obs = box.observer {
                            box.center.removeObserver(obs)
                        }
                    }
                }
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
            moveFile: { _, _ in unimplemented() },
            renameFile: { _, _ in unimplemented() },
            moveToTrash: { _ in unimplemented() },
            deleteImmediately: { _ in unimplemented() },
            putBackFromTrash: { _, _ in unimplemented() },
            compressItems: { _ in unimplemented() },
            loadItems: { _, _ in [] },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            saveClipboardPaths: { _, _ in },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
            observeFileSystemChanged: { AsyncStream { _ in } }
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
            moveFile: { _, _ in },
            renameFile: { _, _ in },
            moveToTrash: { _ in },
            deleteImmediately: { _ in },
            putBackFromTrash: { _, _ in },
            compressItems: { _ in URL(fileURLWithPath: "/tmp/Archive.zip") },
            loadItems: { _, _ in [] },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            saveClipboardPaths: { _, _ in },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
            observeFileSystemChanged: { AsyncStream { _ in } }
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
