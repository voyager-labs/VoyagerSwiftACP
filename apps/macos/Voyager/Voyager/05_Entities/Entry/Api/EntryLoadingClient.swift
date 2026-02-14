import ComposableArchitecture
import Foundation

public struct EntryLoadingClient: Sendable {
    public var loadItems: @Sendable (URL, Bool) async throws -> [Entry]
    public var loadComputerItems: @Sendable () async throws -> [Entry]
    public var loadRecentItems: @Sendable (Bool, WorkspaceClient) async -> [Entry]
    public var loadFilesWithTag: @Sendable (String, Bool, WorkspaceClient) async -> [Entry]
    public var fileExists: @Sendable (String) -> Bool
    public var fileExistsAtPath: @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool
    public var contentsOfDirectory: @Sendable (
        URL,
        [URLResourceKey],
        FileManager.DirectoryEnumerationOptions,
    ) throws -> [URL]
    public var mountedVolumeURLs: @Sendable (
        [URLResourceKey],
        FileManager.VolumeEnumerationOptions,
    ) -> [URL]?
    public var urlsForDirectory: @Sendable (
        FileManager.SearchPathDirectory,
        FileManager.SearchPathDomainMask,
    ) -> [URL]
    public var homeDirectory: @Sendable () -> String
    public var loadDragPaths: @Sendable () -> [String]
    public var getItemMetadata: @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata
    public var getImageResolution: @Sendable (URL) -> String?
    public var getFormattedFileSize: @Sendable (URL) -> String?
    public var getFolderItemCount: @Sendable (URL) -> String?
    public var isPackageDirectory: @Sendable (URL) -> Bool
    public var displayName: @Sendable (String) -> String

    public nonisolated init(
        loadItems: @escaping @Sendable (URL, Bool) async throws -> [Entry],
        loadComputerItems: @escaping @Sendable () async throws -> [Entry],
        loadRecentItems: @escaping @Sendable (Bool, WorkspaceClient) async -> [Entry],
        loadFilesWithTag: @escaping @Sendable (String, Bool, WorkspaceClient) async -> [Entry],
        fileExists: @escaping @Sendable (String) -> Bool,
        fileExistsAtPath: @escaping @Sendable (
            String,
            UnsafeMutablePointer<ObjCBool>?,
        ) -> Bool,
        contentsOfDirectory: @escaping @Sendable (URL, [URLResourceKey], FileManager.DirectoryEnumerationOptions) throws
            -> [URL],
        mountedVolumeURLs: @escaping @Sendable ([URLResourceKey], FileManager.VolumeEnumerationOptions) -> [URL]?,
        urlsForDirectory: @escaping @Sendable (FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask)
            -> [URL],
        homeDirectory: @escaping @Sendable () -> String,
        loadDragPaths: @escaping @Sendable () -> [String],
        getItemMetadata: @escaping @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata,
        getImageResolution: @escaping @Sendable (URL) -> String?,
        getFormattedFileSize: @escaping @Sendable (URL) -> String?,
        getFolderItemCount: @escaping @Sendable (URL) -> String?,
        isPackageDirectory: @escaping @Sendable (URL) -> Bool,
        displayName: @escaping @Sendable (String) -> String,
    ) {
        self.loadItems = loadItems
        self.loadComputerItems = loadComputerItems
        self.loadRecentItems = loadRecentItems
        self.loadFilesWithTag = loadFilesWithTag
        self.fileExists = fileExists
        self.fileExistsAtPath = fileExistsAtPath
        self.contentsOfDirectory = contentsOfDirectory
        self.mountedVolumeURLs = mountedVolumeURLs
        self.urlsForDirectory = urlsForDirectory
        self.homeDirectory = homeDirectory
        self.loadDragPaths = loadDragPaths
        self.getItemMetadata = getItemMetadata
        self.getImageResolution = getImageResolution
        self.getFormattedFileSize = getFormattedFileSize
        self.getFolderItemCount = getFolderItemCount
        self.isPackageDirectory = isPackageDirectory
        self.displayName = displayName
    }
}

extension EntryLoadingClient: DependencyKey {
    public nonisolated static var liveValue: EntryLoadingClient {
        EntryLoadingClient(
            loadItems: EntrySystemPrimitives.liveLoadItems,
            loadComputerItems: EntrySystemPrimitives.liveLoadComputerItems,
            loadRecentItems: EntrySystemPrimitives.liveLoadRecentItems,
            loadFilesWithTag: EntrySystemPrimitives.liveLoadFilesWithTag,
            fileExists: EntrySystemPrimitives.liveFileExists,
            fileExistsAtPath: EntrySystemPrimitives.liveFileExistsAtPath,
            contentsOfDirectory: EntrySystemPrimitives.liveContentsOfDirectory,
            mountedVolumeURLs: EntrySystemPrimitives.liveMountedVolumeURLs,
            urlsForDirectory: EntrySystemPrimitives.liveUrlsForDirectory,
            homeDirectory: EntrySystemPrimitives.liveHomeDirectory,
            loadDragPaths: EntrySystemPrimitives.liveLoadDragPaths,
            getItemMetadata: EntrySystemPrimitives.liveGetItemMetadata,
            getImageResolution: EntrySystemPrimitives.liveGetImageResolution,
            getFormattedFileSize: EntrySystemPrimitives.liveGetFormattedFileSize,
            getFolderItemCount: EntrySystemPrimitives.liveGetFolderItemCount,
            isPackageDirectory: EntrySystemPrimitives.liveIsPackageDirectory,
            displayName: EntrySystemPrimitives.liveDisplayName,
        )
    }

    public nonisolated static var testValue: EntryLoadingClient {
        EntryLoadingClient(
            loadItems: { _, _ in [] },
            loadComputerItems: { [] },
            loadRecentItems: { _, _ in [] },
            loadFilesWithTag: { _, _, _ in [] },
            fileExists: { _ in false },
            fileExistsAtPath: { _, _ in false },
            contentsOfDirectory: { _, _, _ in [] },
            mountedVolumeURLs: { _, _ in nil },
            urlsForDirectory: { _, _ in [] },
            homeDirectory: { "/Users/test" },
            loadDragPaths: { [] },
            getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "File", creatorApplication: nil, lastUsedDate: nil) },
            getImageResolution: { _ in nil },
            getFormattedFileSize: { _ in nil },
            getFolderItemCount: { _ in nil },
            isPackageDirectory: { _ in false },
            displayName: { path in path },
        )
    }

    public nonisolated static var previewValue: EntryLoadingClient {
        EntryLoadingClient(
            loadItems: { _, _ in [] },
            loadComputerItems: { [] },
            loadRecentItems: { _, _ in [] },
            loadFilesWithTag: { _, _, _ in [] },
            fileExists: { _ in false },
            fileExistsAtPath: { _, _ in false },
            contentsOfDirectory: { _, _, _ in [] },
            mountedVolumeURLs: { _, _ in nil },
            urlsForDirectory: { _, _ in [] },
            homeDirectory: { "/Users/test" },
            loadDragPaths: { [] },
            getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "File", creatorApplication: nil, lastUsedDate: nil) },
            getImageResolution: { _ in nil },
            getFormattedFileSize: { _ in nil },
            getFolderItemCount: { _ in nil },
            isPackageDirectory: { _ in false },
            displayName: { path in path },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryLoadingClient: EntryLoadingClient {
        get { self[EntryLoadingClient.self] }
        set { self[EntryLoadingClient.self] = newValue }
    }
}
