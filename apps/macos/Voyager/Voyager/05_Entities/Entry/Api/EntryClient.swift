import AppKit
import ComposableArchitecture

import Foundation
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

public struct EntryItemMetadata: Equatable, Sendable {
    public let kind: String
    public let creatorApplication: String?
    public let lastUsedDate: Date?

    public nonisolated init(kind: String, creatorApplication: String?, lastUsedDate: Date?) {
        self.kind = kind
        self.creatorApplication = creatorApplication
        self.lastUsedDate = lastUsedDate
    }
}

public struct EntryClient: Sendable {
    public var open: @Sendable (URL, OpenKind) async throws -> Void
    public var setDefaultApp: @Sendable (UTType, String) async throws -> Void
    public var quickLook: @Sendable (URL) async throws -> Void
    public var quickLookFiles: @Sendable ([URL]) async throws -> Void
    public var openFinderInfo: @Sendable ([URL]) async throws -> Void
    public var shareItems: @Sendable ([URL], CGPoint?) async throws -> Void
    public var performService: @Sendable (String, [URL]) async throws -> Void
    public var revealInFinder: @Sendable ([URL]) async throws -> Void
    public var applicationsForFile: @Sendable (URL) async -> [ApplicationInfo]
    public var defaultApplication: @Sendable (UTType) async -> ApplicationInfo?
    public var createFolder: @Sendable (URL, String) async throws -> Void
    public var pasteFile: @Sendable (URL, URL) async throws -> Void
    public var moveFile: @Sendable (URL, URL) async throws -> Void
    public var renameFile: @Sendable (URL, URL) async throws -> Void
    public var createAlias: @Sendable (URL, URL) async throws -> Void
    public var moveToTrash: @Sendable (URL) async throws -> Void
    public var moveToTrashAndReturnURL: @Sendable (URL) async throws -> URL
    public var deleteImmediately: @Sendable (URL) async throws -> Void
    public var putBackFromTrash: @Sendable (URL, String) async throws -> Void
    public var compressItems: @Sendable ([URL]) async throws -> URL
    public var extractCompressedFile: @Sendable (URL) async throws -> Void
    public var getTags: @Sendable (URL) async throws -> [String]
    public var setTags: @Sendable (URL, [String]) async throws -> Void
    public var toggleTag: @Sendable (URL, String) async throws -> Void
    public var loadItems: @Sendable (URL, Bool) async throws -> [Entry]
    public var loadComputerItems: @Sendable () async throws -> [Entry]
    public var fileExists: @Sendable (String) -> Bool
    public var fileExistsAtPath: @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool
    public var displayName: @Sendable (String) -> String
    public var urlsForDirectory: @Sendable (FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask) -> [URL]
    public var homeDirectory: @Sendable () -> String
    public var trashDirectoryPath: @Sendable () -> String?
    public var mountedVolumeURLs: @Sendable ([URLResourceKey], FileManager.VolumeEnumerationOptions) -> [URL]?
    public var contentsOfDirectory: @Sendable (URL, [URLResourceKey], FileManager.DirectoryEnumerationOptions) throws
        -> [URL]
    public var getItemMetadata: @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata
    public var getImageResolution: @Sendable (URL) -> String?
    public var getFormattedFileSize: @Sendable (URL) -> String?
    public var getFolderItemCount: @Sendable (URL) -> String?
    public var isPackageDirectory: @Sendable (URL) -> Bool
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
        quickLookFiles: @escaping @Sendable ([URL]) async throws -> Void,
        openFinderInfo: @escaping @Sendable ([URL]) async throws -> Void,
        shareItems: @escaping @Sendable ([URL], CGPoint?) async throws -> Void,
        performService: @escaping @Sendable (String, [URL]) async throws -> Void,
        revealInFinder: @escaping @Sendable ([URL]) async throws -> Void,
        applicationsForFile: @escaping @Sendable (URL) async -> [ApplicationInfo],
        defaultApplication: @escaping @Sendable (UTType) async -> ApplicationInfo?,
        createFolder: @escaping @Sendable (URL, String) async throws -> Void,
        pasteFile: @escaping @Sendable (URL, URL) async throws -> Void,
        moveFile: @escaping @Sendable (URL, URL) async throws -> Void,
        renameFile: @escaping @Sendable (URL, URL) async throws -> Void,
        createAlias: @escaping @Sendable (URL, URL) async throws -> Void,
        moveToTrash: @escaping @Sendable (URL) async throws -> Void,
        moveToTrashAndReturnURL: @escaping @Sendable (URL) async throws -> URL,
        deleteImmediately: @escaping @Sendable (URL) async throws -> Void,
        putBackFromTrash: @escaping @Sendable (URL, String) async throws -> Void,
        compressItems: @escaping @Sendable ([URL]) async throws -> URL,
        extractCompressedFile: @escaping @Sendable (URL) async throws -> Void,
        getTags: @escaping @Sendable (URL) async throws -> [String],
        setTags: @escaping @Sendable (URL, [String]) async throws -> Void,
        toggleTag: @escaping @Sendable (URL, String) async throws -> Void,
        loadItems: @escaping @Sendable (URL, Bool) async throws -> [Entry],
        loadComputerItems: @escaping @Sendable () async throws -> [Entry],
        fileExists: @escaping @Sendable (String) -> Bool,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
        displayName: @escaping @Sendable (String) -> String,
        urlsForDirectory: @escaping @Sendable (FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask)
            -> [URL],
        homeDirectory: @escaping @Sendable () -> String,
        trashDirectoryPath: @escaping @Sendable () -> String?,
        mountedVolumeURLs: @escaping @Sendable ([URLResourceKey], FileManager.VolumeEnumerationOptions) -> [URL]?,
        contentsOfDirectory: @escaping @Sendable (
            URL,
            [URLResourceKey],
            FileManager.DirectoryEnumerationOptions,
        ) throws -> [URL],
        getItemMetadata: @escaping @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata,
        getImageResolution: @escaping @Sendable (URL) -> String?,
        getFormattedFileSize: @escaping @Sendable (URL) -> String?,
        getFolderItemCount: @escaping @Sendable (URL) -> String?,
        isPackageDirectory: @escaping @Sendable (URL) -> Bool,
        saveDragPaths: @escaping @Sendable ([String]) -> Void,
        loadDragPaths: @escaping @Sendable () -> [String],
        saveDragWithOption: @escaping @Sendable (Bool) -> Void,
        loadDragWithOption: @escaping @Sendable () -> Bool,
        loadClipboardPaths: @escaping @Sendable () -> ([String], ClipboardOperation),
        postFileSystemChanged: @escaping @Sendable ([String]) -> Void,
        observeFileSystemChanged: @escaping @Sendable () -> AsyncStream<[String]>,
        startWatchingDirectory: @escaping @Sendable (URL) -> AsyncStream<[String]>,
        stopWatchingDirectory: @escaping @Sendable () -> Void,
    ) {
        self.open = open
        self.setDefaultApp = setDefaultApp
        self.quickLook = quickLook
        self.quickLookFiles = quickLookFiles
        self.openFinderInfo = openFinderInfo
        self.shareItems = shareItems
        self.performService = performService
        self.revealInFinder = revealInFinder
        self.applicationsForFile = applicationsForFile
        self.defaultApplication = defaultApplication
        self.createFolder = createFolder
        self.pasteFile = pasteFile
        self.moveFile = moveFile
        self.renameFile = renameFile
        self.createAlias = createAlias
        self.moveToTrash = moveToTrash
        self.moveToTrashAndReturnURL = moveToTrashAndReturnURL
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
        self.fileExistsAtPath = fileExistsAtPath
        self.displayName = displayName
        self.urlsForDirectory = urlsForDirectory
        self.homeDirectory = homeDirectory
        self.trashDirectoryPath = trashDirectoryPath
        self.mountedVolumeURLs = mountedVolumeURLs
        self.contentsOfDirectory = contentsOfDirectory
        self.getItemMetadata = getItemMetadata
        self.getImageResolution = getImageResolution
        self.getFormattedFileSize = getFormattedFileSize
        self.getFolderItemCount = getFolderItemCount
        self.isPackageDirectory = isPackageDirectory
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
            "The item could not be found."
        case .unsupportedType:
            "This item type is not supported."
        case .cancelled:
            "The operation was cancelled."
        case let .fileExists(itemName):
            "A newer item named \"\(itemName)\" already exists in this location."
        case let .system(message, _):
            message
        }
    }

    public var suggestion: String? {
        switch self {
        case let .system(_, hint):
            hint
        default:
            nil
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

extension EntryClient: DependencyKey {
    // FSEventsWatcher 싱글톤 패턴으로 중복 생성 방지
    private nonisolated static let sharedWatcher = FSEventsWatcher()

    public nonisolated static var liveValue: EntryClient {
        let watcher = sharedWatcher
        return EntryClient(
            open: liveOpen,
            setDefaultApp: liveSetDefaultApp,
            quickLook: liveQuickLook,
            quickLookFiles: liveQuickLookFiles,
            openFinderInfo: liveOpenFinderInfo,
            shareItems: liveShareItems,
            performService: livePerformService,
            revealInFinder: liveRevealInFinder,
            applicationsForFile: liveApplicationsForFile,
            defaultApplication: liveDefaultApplication,
            createFolder: liveCreateFolder,
            pasteFile: livePasteFile,
            moveFile: liveMoveFile,
            renameFile: liveRenameFile,
            createAlias: liveCreateAlias,
            moveToTrash: liveMoveToTrash,
            moveToTrashAndReturnURL: liveMoveToTrashAndReturnURL,
            deleteImmediately: liveDeleteImmediately,
            putBackFromTrash: livePutBackFromTrash,
            compressItems: liveCompressItems,
            extractCompressedFile: liveExtractCompressedFile,
            getTags: liveGetTags,
            setTags: liveSetTags,
            toggleTag: liveToggleTag,
            loadItems: liveLoadItems,
            loadComputerItems: liveLoadComputerItems,
            fileExists: liveFileExists,
            fileExistsAtPath: liveFileExistsAtPath,
            displayName: liveDisplayName,
            urlsForDirectory: liveUrlsForDirectory,
            homeDirectory: liveHomeDirectory,
            trashDirectoryPath: liveTrashDirectoryPath,
            mountedVolumeURLs: liveMountedVolumeURLs,
            contentsOfDirectory: liveContentsOfDirectory,
            getItemMetadata: liveGetItemMetadata,
            getImageResolution: liveGetImageResolution,
            getFormattedFileSize: liveGetFormattedFileSize,
            getFolderItemCount: liveGetFolderItemCount,
            isPackageDirectory: liveIsPackageDirectory,
            saveDragPaths: liveSaveDragPaths,
            loadDragPaths: liveLoadDragPaths,
            saveDragWithOption: liveSaveDragWithOption,
            loadDragWithOption: liveLoadDragWithOption,
            loadClipboardPaths: liveLoadClipboardPaths,
            postFileSystemChanged: livePostFileSystemChanged,
            observeFileSystemChanged: liveObserveFileSystemChanged,
            startWatchingDirectory: makeStartWatchingDirectory(watcher: watcher),
            stopWatchingDirectory: makeStopWatchingDirectory(watcher: watcher),
        )
    }

    public nonisolated static var testValue: EntryClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryClient test dependency not set.")
        }
        return EntryClient(
            open: { _, _ in unimplemented() },
            setDefaultApp: { _, _ in unimplemented() },
            quickLook: { _ in unimplemented() },
            quickLookFiles: { _ in unimplemented() },
            openFinderInfo: { _ in unimplemented() },
            shareItems: { _, _ in unimplemented() },
            performService: { _, _ in unimplemented() },
            revealInFinder: { _ in unimplemented() },
            applicationsForFile: { _ in unimplemented() },
            defaultApplication: { _ in unimplemented() },
            createFolder: { _, _ in unimplemented() },
            pasteFile: { _, _ in unimplemented() },
            moveFile: { _, _ in unimplemented() },
            renameFile: { _, _ in unimplemented() },
            createAlias: { _, _ in unimplemented() },
            moveToTrash: { _ in unimplemented() },
            moveToTrashAndReturnURL: { _ in unimplemented() },
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
            fileExistsAtPath: { _, _ in false },
            displayName: { path in path },
            urlsForDirectory: { _, _ in [] },
            homeDirectory: { "/Users/test" },
            trashDirectoryPath: { nil },
            mountedVolumeURLs: { _, _ in nil },
            contentsOfDirectory: { _, _, _ in [] },
            getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "File", creatorApplication: nil, lastUsedDate: nil) },
            getImageResolution: { _ in nil },
            getFormattedFileSize: { _ in nil },
            getFolderItemCount: { _ in nil },
            isPackageDirectory: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
            observeFileSystemChanged: { AsyncStream { _ in } },
            startWatchingDirectory: { _ in AsyncStream { _ in } },
            stopWatchingDirectory: {},
        )
    }

    public nonisolated static var previewValue: EntryClient {
        let previewInfo = ApplicationInfo(
            id: "com.apple.preview",
            name: "Preview",
            bundleID: "com.apple.preview",
        )
        let chromeInfo = ApplicationInfo(id: "com.google.Chrome", name: "Google Chrome", bundleID: "com.google.Chrome")
        let otherInfo = ApplicationInfo(id: "other", name: "Other…", bundleID: nil)

        return EntryClient(
            open: { _, _ in },
            setDefaultApp: { _, _ in },
            quickLook: { _ in },
            quickLookFiles: { _ in },
            openFinderInfo: { _ in },
            shareItems: { _, _ in },
            performService: { _, _ in },
            revealInFinder: { _ in },
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
            createAlias: { _, _ in },
            moveToTrash: { _ in },
            moveToTrashAndReturnURL: { _ in URL(fileURLWithPath: "/tmp/.Trash/test") },
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
            fileExistsAtPath: { _, _ in false },
            displayName: { path in path },
            urlsForDirectory: { _, _ in [] },
            homeDirectory: { "/Users/test" },
            trashDirectoryPath: { nil },
            mountedVolumeURLs: { _, _ in nil },
            contentsOfDirectory: { _, _, _ in [] },
            getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "File", creatorApplication: nil, lastUsedDate: nil) },
            getImageResolution: { _ in nil },
            getFormattedFileSize: { _ in nil },
            getFolderItemCount: { _ in nil },
            isPackageDirectory: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
            observeFileSystemChanged: { AsyncStream { _ in } },
            startWatchingDirectory: { _ in AsyncStream { _ in } },
            stopWatchingDirectory: {},
        )
    }
}

public extension DependencyValues {
    nonisolated var entryClient: EntryClient {
        get { self[EntryClient.self] }
        set { self[EntryClient.self] = newValue }
    }
}
