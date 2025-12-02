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

public struct FSItemClient: Sendable {
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
    public var extractCompressedFile: @Sendable (URL) async throws -> Void
    public var getTags: @Sendable (URL) async throws -> [String]
    public var setTags: @Sendable (URL, [String]) async throws -> Void
    public var toggleTag: @Sendable (URL, String) async throws -> Void
    public var loadItems: @Sendable (URL, Bool) async throws -> [FSItem]
    public var loadComputerItems: @Sendable () async throws -> [FSItem]
    public var fileExists: @Sendable (String) -> Bool
    public var saveDragPaths: @Sendable ([String]) -> Void
    public var loadDragPaths: @Sendable () -> [String]
    public var saveDragWithOption: @Sendable (Bool) -> Void
    public var loadDragWithOption: @Sendable () -> Bool
    public var loadClipboardPaths: @Sendable () -> ([String], ClipboardOperation)
    public var postFileSystemChanged: @Sendable ([String]) -> Void
    public var observeFileSystemChanged: @Sendable () -> AsyncStream<[String]>
    public var startWatchingDirectory: @Sendable (URL) -> AsyncStream<[String]>
    public var stopWatchingDirectory: @Sendable () -> Void

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
        extractCompressedFile: @escaping @Sendable (URL) async throws -> Void,
        getTags: @escaping @Sendable (URL) async throws -> [String],
        setTags: @escaping @Sendable (URL, [String]) async throws -> Void,
        toggleTag: @escaping @Sendable (URL, String) async throws -> Void,
        loadItems: @escaping @Sendable (URL, Bool) async throws -> [FSItem],
        loadComputerItems: @escaping @Sendable () async throws -> [FSItem],
        fileExists: @escaping @Sendable (String) -> Bool,
        saveDragPaths: @escaping @Sendable ([String]) -> Void,
        loadDragPaths: @escaping @Sendable () -> [String],
        saveDragWithOption: @escaping @Sendable (Bool) -> Void,
        loadDragWithOption: @escaping @Sendable () -> Bool,
        loadClipboardPaths: @escaping @Sendable () -> ([String], ClipboardOperation),
        postFileSystemChanged: @escaping @Sendable ([String]) -> Void,
        observeFileSystemChanged: @escaping @Sendable () -> AsyncStream<[String]>,
        startWatchingDirectory: @escaping @Sendable (URL) -> AsyncStream<[String]>,
        stopWatchingDirectory: @escaping @Sendable () -> Void
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
        self.extractCompressedFile = extractCompressedFile
        self.getTags = getTags
        self.setTags = setTags
        self.toggleTag = toggleTag
        self.loadItems = loadItems
        self.loadComputerItems = loadComputerItems
        self.fileExists = fileExists
        self.saveDragPaths = saveDragPaths
        self.loadDragPaths = loadDragPaths
        self.saveDragWithOption = saveDragWithOption
        self.loadDragWithOption = loadDragWithOption
        self.loadClipboardPaths = loadClipboardPaths
        self.postFileSystemChanged = postFileSystemChanged
        self.observeFileSystemChanged = observeFileSystemChanged
        self.startWatchingDirectory = startWatchingDirectory
        self.stopWatchingDirectory = stopWatchingDirectory
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

private nonisolated func setFileTags(url: URL, tags: [String]) throws {
    if tags.isEmpty {
        let result = removexattr(
            url.path,
            "com.apple.metadata:_kMDItemUserTags",
            XATTR_NOFOLLOW
        )
        if result != 0, errno != ENOATTR {
            throw FileOpError.system(message: "Failed to remove tags")
        }
    } else {
        let tagData = try PropertyListSerialization.data(
            fromPropertyList: tags,
            format: .binary,
            options: 0
        )

        let result = setxattr(
            url.path,
            "com.apple.metadata:_kMDItemUserTags",
            (tagData as NSData).bytes,
            tagData.count,
            0,
            XATTR_NOFOLLOW
        )

        if result != 0 {
            throw FileOpError.system(message: "Failed to set tags")
        }
    }
}

extension FSItemClient: DependencyKey {
    public nonisolated static var liveValue: FSItemClient {
        final class FSEventsWatcher: @unchecked Sendable {
            var eventStream: FSEventStreamRef?
            let lock = NSLock()

            func setStream(_ stream: FSEventStreamRef?) {
                lock.lock()
                defer { lock.unlock() }
                eventStream = stream
            }

            func getStream() -> FSEventStreamRef? {
                lock.lock()
                defer { lock.unlock() }
                return eventStream
            }
        }

        let watcher = FSEventsWatcher()

        return FSItemClient(
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
                    .all,
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
            extractCompressedFile: { zipURL in
                guard zipURL.pathExtension.lowercased() == "zip" else {
                    throw FileOpError.unsupportedType
                }

                let parentURL = zipURL.deletingLastPathComponent()
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", "-q", zipURL.path, "-d", tempURL.path]

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    throw FileOpError.system(message: "Extraction failed")
                }

                let extractedItems = try FileManager.default.contentsOfDirectory(
                    at: tempURL,
                    includingPropertiesForKeys: nil
                )

                if extractedItems.count == 1 {
                    let item = extractedItems[0]
                    var targetURL = parentURL.appendingPathComponent(item.lastPathComponent)
                    var counter = 2

                    while FileManager.default.fileExists(atPath: targetURL.path) {
                        let name = (item.lastPathComponent as NSString).deletingPathExtension
                        let ext = (item.lastPathComponent as NSString).pathExtension

                        targetURL = ext.isEmpty
                            ? parentURL.appendingPathComponent("\(name) \(counter)")
                            : parentURL.appendingPathComponent("\(name) \(counter).\(ext)")
                        counter += 1
                    }

                    try FileManager.default.moveItem(at: item, to: targetURL)
                } else {
                    let baseName = zipURL.deletingPathExtension().lastPathComponent
                    var folderURL = parentURL.appendingPathComponent(baseName)
                    var counter = 2

                    while FileManager.default.fileExists(atPath: folderURL.path) {
                        folderURL = parentURL.appendingPathComponent("\(baseName) \(counter)")
                        counter += 1
                    }

                    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)

                    for item in extractedItems {
                        let target = folderURL.appendingPathComponent(item.lastPathComponent)
                        try FileManager.default.moveItem(at: item, to: target)
                    }
                }
            },
            getTags: { url in
                let values = try url.resourceValues(forKeys: [.tagNamesKey])
                return values.tagNames ?? []
            },
            setTags: { url, tags in
                try setFileTags(url: url, tags: tags)
            },
            toggleTag: { url, tag in
                var currentTags = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []

                if currentTags.contains(tag) {
                    currentTags.removeAll { $0 == tag }
                } else {
                    currentTags.append(tag)
                }

                try setFileTags(url: url, tags: currentTags)
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

                    return contents.compactMap { FSItemLoadUtils.convertURLToFSItem($0) }
                }.value
            },
            loadComputerItems: {
                try await Task.detached {
                    let rootName = FileManager.default.displayName(atPath: "/")
                    return [
                        FSItem(
                            name: rootName,
                            fullPath: "/",
                            isDirectory: true,
                            isHidden: false,
                            kind: "Volume"
                        ),
                    ]
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
            loadClipboardPaths: {
                let pasteboard = NSPasteboard.general

                guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
                    return ([], .copy)
                }

                let paths = urls.map { $0.path }

                let opString = pasteboard
                    .string(forType: NSPasteboard.PasteboardType("com.voyager.clipboard.operation"))
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
            },
            startWatchingDirectory: { url in
                AsyncStream { continuation in
                    final class ContinuationBox {
                        let continuation: AsyncStream<[String]>.Continuation
                        init(_ continuation: AsyncStream<[String]>.Continuation) {
                            self.continuation = continuation
                        }
                    }

                    let box = ContinuationBox(continuation)

                    let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
                        guard let info = info else { return }

                        let box = Unmanaged<ContinuationBox>
                            .fromOpaque(info)
                            .takeUnretainedValue()

                        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                            return
                        }
                        box.continuation.yield(paths)
                    }

                    var context = FSEventStreamContext(
                        version: 0,
                        info: Unmanaged.passRetained(box).toOpaque(),
                        retain: nil,
                        release: { info in
                            guard let info = info else { return }
                            Unmanaged<ContinuationBox>.fromOpaque(info).release()
                        },
                        copyDescription: nil
                    )

                    guard let stream = FSEventStreamCreate(
                        nil,
                        callback,
                        &context,
                        [url.path] as CFArray,
                        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                        0.3, // 300ms 지연 (배터리 효율)
                        UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
                    ) else {
                        continuation.finish()
                        return
                    }

                    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

                    guard FSEventStreamStart(stream) else {
                        FSEventStreamInvalidate(stream)
                        FSEventStreamRelease(stream)
                        continuation.finish()
                        return
                    }

                    watcher.setStream(stream)

                    continuation.onTermination = { @Sendable _ in
                        if let stream = watcher.getStream() {
                            FSEventStreamStop(stream)
                            FSEventStreamInvalidate(stream)
                            FSEventStreamRelease(stream)
                            watcher.setStream(nil)
                        }
                    }
                }
            },
            stopWatchingDirectory: {
                if let stream = watcher.getStream() {
                    FSEventStreamStop(stream)
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                    watcher.setStream(nil)
                }
            }
        )
    }

    public nonisolated static var testValue: FSItemClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("FSItemClient test dependency not set.")
        }
        return FSItemClient(
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
            extractCompressedFile: { _ in unimplemented() },
            getTags: { _ in unimplemented() },
            setTags: { _, _ in unimplemented() },
            toggleTag: { _, _ in unimplemented() },
            loadItems: { _, _ in [] },
            loadComputerItems: { [] },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
            observeFileSystemChanged: { AsyncStream { _ in } },
            startWatchingDirectory: { _ in AsyncStream { _ in } },
            stopWatchingDirectory: {}
        )
    }

    public nonisolated static var previewValue: FSItemClient {
        let previewInfo = ApplicationInfo(
            id: "com.apple.preview",
            name: "Preview",
            bundleID: "com.apple.preview"
        )
        let chromeInfo = ApplicationInfo(id: "com.google.Chrome", name: "Google Chrome", bundleID: "com.google.Chrome")
        let otherInfo = ApplicationInfo(id: "other", name: "Other…", bundleID: nil)

        return FSItemClient(
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
            extractCompressedFile: { _ in },
            getTags: { _ in [] },
            setTags: { _, _ in },
            toggleTag: { _, _ in },
            loadItems: { _, _ in [] },
            loadComputerItems: { [] },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
            observeFileSystemChanged: { AsyncStream { _ in } },
            startWatchingDirectory: { _ in AsyncStream { _ in } },
            stopWatchingDirectory: {}
        )
    }
}

public extension DependencyValues {
    nonisolated var fsItemClient: FSItemClient {
        get { self[FSItemClient.self] }
        set { self[FSItemClient.self] = newValue }
    }
}

func withScopedAccess<T>(_ url: URL, perform: @escaping () async throws -> T) async throws -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try await perform()
}
