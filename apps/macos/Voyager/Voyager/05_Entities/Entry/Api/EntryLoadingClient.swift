// swiftlint:disable file_length
import ComposableArchitecture
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VoyagerShared

public struct EntryLoadingClient: Sendable {
    public var loadItems: @Sendable (URL, Bool) async throws -> [EntryModel]
    public var loadComputerItems: @Sendable () async throws -> [EntryModel]
    public var loadRecentItems: @Sendable (Bool, WorkspaceClient) async -> [EntryModel]
    public var loadFilesWithTag: @Sendable (String, Bool, WorkspaceClient) async -> [EntryModel]
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
    public var getItemMetadata: @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata
    public var getImageResolution: @Sendable (URL) -> (width: Int, height: Int)?
    public var getFileSizeInBytes: @Sendable (URL) -> Int64?
    public var getFolderItemCount: @Sendable (URL) -> Int?
    public var isPackageDirectory: @Sendable (URL) -> Bool
    public var displayName: @Sendable (String) -> String

    public nonisolated init(
        loadItems: @escaping @Sendable (URL, Bool) async throws -> [EntryModel],
        loadComputerItems: @escaping @Sendable () async throws -> [EntryModel],
        loadRecentItems: @escaping @Sendable (Bool, WorkspaceClient) async -> [EntryModel],
        loadFilesWithTag: @escaping @Sendable (String, Bool, WorkspaceClient) async -> [EntryModel],
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
        getItemMetadata: @escaping @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata,
        getImageResolution: @escaping @Sendable (URL) -> (width: Int, height: Int)?,
        getFileSizeInBytes: @escaping @Sendable (URL) -> Int64?,
        getFolderItemCount: @escaping @Sendable (URL) -> Int?,
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
        self.getItemMetadata = getItemMetadata
        self.getImageResolution = getImageResolution
        self.getFileSizeInBytes = getFileSizeInBytes
        self.getFolderItemCount = getFolderItemCount
        self.isPackageDirectory = isPackageDirectory
        self.displayName = displayName
    }
}

extension EntryLoadingClient: DependencyKey {
    public nonisolated static var liveValue: EntryLoadingClient {
        EntryLoadingClient(
            loadItems: EntryLoadingLive.loadItems,
            loadComputerItems: EntryLoadingLive.loadComputerItems,
            loadRecentItems: EntryLoadingLive.loadRecentItems,
            loadFilesWithTag: EntryLoadingLive.loadFilesWithTag,
            fileExists: EntryLoadingLive.fileExists,
            fileExistsAtPath: EntryLoadingLive.fileExistsAtPath,
            contentsOfDirectory: EntryLoadingLive.contentsOfDirectory,
            mountedVolumeURLs: EntryLoadingLive.mountedVolumeURLs,
            urlsForDirectory: EntryLoadingLive.urlsForDirectory,
            homeDirectory: EntryLoadingLive.homeDirectory,
            getItemMetadata: EntryLoadingLive.getItemMetadata,
            getImageResolution: EntryLoadingLive.getImageResolution,
            getFileSizeInBytes: EntryLoadingLive.getFileSizeInBytes,
            getFolderItemCount: EntryLoadingLive.getFolderItemCount,
            isPackageDirectory: EntryLoadingLive.isPackageDirectory,
            displayName: EntryLoadingLive.displayName,
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
            getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "File", creatorApplication: nil, lastUsedDate: nil) },
            getImageResolution: { _ in nil },
            getFileSizeInBytes: { _ in nil },
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
            getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "File", creatorApplication: nil, lastUsedDate: nil) },
            getImageResolution: { _ in nil },
            getFileSizeInBytes: { _ in nil },
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

enum EntryLoadingLive {
    nonisolated static var loadItems: @Sendable (URL, Bool) async throws -> [EntryModel] {
        { directoryURL, showHidden in
            try await Task.detached {
                let entryLoadingClient = EntryLoadingClient.liveValue
                let workspaceClient = WorkspaceClient.liveValue
                let fileManagerClient = FileManagerClient.liveValue
                let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]

                let entries = try fileManagerClient.contentsOfDirectory(
                    directoryURL,
                    [
                        .nameKey,
                        .fileSizeKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                        .contentTypeKey,
                        .isDirectoryKey,
                        .isHiddenKey,
                        .labelColorKey,
                        .tagNamesKey,
                        .addedToDirectoryDateKey,
                        .contentAccessDateKey,
                    ],
                    options,
                )

                return entries.compactMap { url in
                    EntryModelConverterLive.convertURLToEntry(
                        url,
                        entryLoadingClient: entryLoadingClient,
                        workspaceClient: workspaceClient,
                    )
                }
            }.value
        }
    }

    nonisolated static var loadComputerItems: @Sendable () async throws -> [EntryModel] {
        {
            await Task.detached {
                let fileManagerClient = FileManagerClient.liveValue
                let rootName = fileManagerClient.displayName("/")
                return [
                    EntryModel(
                        name: rootName,
                        fullPath: "/",
                        isFolder: true,
                        isHidden: false,
                        size: 0,
                        modifiedDate: Date(),
                        fileExtension: "",
                        facets: EntryFacets(
                            createdDate: Date(),
                            addedDate: Date(),
                            lastOpenedDate: nil,
                            kind: "Volume",
                            creatorApplication: nil,
                            tags: nil,
                            supplementaryMetadata: nil,
                        ),
                    ),
                ]
            }.value
        }
    }

    nonisolated static var fileExists: @Sendable (String) -> Bool {
        { path in
            FileManagerClient.liveValue.fileExists(path)
        }
    }

    nonisolated static var fileExistsAtPath: @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool {
        { path, isDirectory in
            FileManagerClient.liveValue.fileExistsWithIsDirectory(path, isDirectory)
        }
    }

    nonisolated static var displayName: @Sendable (String) -> String {
        { path in
            FileManagerClient.liveValue.displayName(path)
        }
    }

    nonisolated static var urlsForDirectory: @Sendable (
        FileManager.SearchPathDirectory,
        FileManager.SearchPathDomainMask,
    ) -> [URL] {
        { directory, domain in
            FileManagerClient.liveValue.urlsForDirectory(directory, domain)
        }
    }

    nonisolated static var homeDirectory: @Sendable () -> String {
        {
            NSHomeDirectory()
        }
    }

    nonisolated static var trashDirectoryPath: @Sendable () -> String? {
        {
            FileManagerClient.liveValue.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path
        }
    }

    nonisolated static var mountedVolumeURLs: @Sendable (
        [URLResourceKey],
        FileManager.VolumeEnumerationOptions,
    ) -> [URL]? {
        { keys, options in
            FileManagerClient.liveValue.mountedVolumeURLs(keys, options)
        }
    }

    nonisolated static var contentsOfDirectory: @Sendable (
        URL,
        [URLResourceKey],
        FileManager.DirectoryEnumerationOptions,
    ) throws -> [URL] {
        { url, keys, options in
            try FileManagerClient.liveValue.contentsOfDirectory(url, keys, options)
        }
    }

    nonisolated static var getItemMetadata: @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata {
        { url, isDirectory, workspaceClient in
            var kind: String
            var creatorApplication: String?
            var lastUsedDate: Date?

            if isDirectory {
                kind = "Folder"
            } else {
                kind = url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased() + " File"
            }

            if let mdItem = MDItemCreate(kCFAllocatorDefault, url.path as CFString) {
                if !isDirectory {
                    if let contentType = MDItemCopyAttribute(mdItem, kMDItemContentType) as? String,
                       let uti = UTType(mimeType: contentType)
                    {
                        kind = uti.localizedDescription ?? contentType
                    }

                    if let appURL = workspaceClient.urlForApplicationToOpen(url) {
                        creatorApplication = appURL.deletingPathExtension().lastPathComponent
                    }
                }

                if let lastUsed = MDItemCopyAttribute(mdItem, "kMDItemLastUsedDate" as CFString) as? Date {
                    lastUsedDate = lastUsed
                }
            }

            return EntryItemMetadata(
                kind: kind,
                creatorApplication: creatorApplication,
                lastUsedDate: lastUsedDate,
            )
        }
    }

    nonisolated static var getImageResolution: @Sendable (URL) -> (width: Int, height: Int)? {
        { url in
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int
            else {
                return nil
            }

            return (width: width, height: height)
        }
    }

    nonisolated static var getFileSizeInBytes: @Sendable (URL) -> Int64? {
        { url in
            guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize
            else {
                return nil
            }

            return Int64(fileSize)
        }
    }

    nonisolated static var getFolderItemCount: @Sendable (URL) -> Int? {
        { url in
            guard let entries = try? FileManagerClient.liveValue.contentsOfDirectory(
                url,
                nil,
                [.skipsHiddenFiles],
            ) else {
                return nil
            }

            return entries.count
        }
    }

    nonisolated static var isPackageDirectory: @Sendable (URL) -> Bool {
        { url in
            if let values = try? url.resourceValues(forKeys: [.isPackageKey]),
               values.isPackage == true
            {
                return true
            }

            let ext = url.pathExtension.lowercased()
            if ["app", "icon"].contains(ext) {
                return true
            }

            if let type = UTType(filenameExtension: url.pathExtension),
               type.conforms(to: .package)
            {
                return true
            }

            return false
        }
    }

    nonisolated static var loadRecentItems: @Sendable (Bool, WorkspaceClient) async -> [EntryModel] {
        { showHidden, _ in
            await loadRecentItemsViaSearch(showHidden: showHidden, recentSearchClient: RecentSearchClient.liveValue)
        }
    }

    nonisolated static var loadFilesWithTag: @Sendable (String, Bool, WorkspaceClient) async -> [EntryModel] {
        { tag, showHidden, _ in
            await loadFilesWithTagViaSearch(
                tag: tag,
                showHidden: showHidden,
                tagSearchClient: TagSearchClient.liveValue,
            )
        }
    }

    nonisolated static func loadRecentItemsViaSearch(
        showHidden: Bool,
        recentSearchClient: RecentSearchClient,
    ) async -> [EntryModel] {
        do {
            let response = try await recentSearchClient.search(
                .init(
                    scopeMode: .allIndexed,
                    scopes: [],
                    resultCap: 100,
                    includeHidden: showHidden,
                    sort: .lastUsedDateDescending,
                ),
            )
            return response.items.map(EntryModelPayloadAdapter.makeEntry)
        } catch {
            return []
        }
    }

    nonisolated static func loadFilesWithTagViaSearch(
        tag: String,
        showHidden: Bool,
        tagSearchClient: TagSearchClient,
    ) async -> [EntryModel] {
        do {
            let response = try await tagSearchClient.search(
                .init(
                    requestedTag: tag,
                    scopeMode: .allIndexed,
                    scopes: [],
                    resultCap: 100,
                    includeHidden: showHidden,
                    sort: .lastUsedDateDescending,
                    exactTagVerification: true,
                ),
            )
            return response.items.map(EntryModelPayloadAdapter.makeEntry)
        } catch {
            return []
        }
    }
}

enum EntryModelConverterLive {
    nonisolated static func convertURLToEntry(
        _ itemURL: URL,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
    ) -> EntryModel? {
        var isDirectory: ObjCBool = false
        guard entryLoadingClient.fileExistsAtPath(itemURL.path, &isDirectory) else {
            return nil
        }

        let resourceValues = try? itemURL.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
            .contentAccessDateKey,
            .isHiddenKey,
        ])

        let name = resourceValues?.name ?? itemURL.lastPathComponent
        let size = Int64(resourceValues?.fileSize ?? 0)
        let modifiedDate = resourceValues?.contentModificationDate ?? Date()
        let createdDate = resourceValues?.creationDate ?? Date()
        let addedDate = resourceValues?.addedToDirectoryDate ?? Date()

        let isHidden = resourceValues?.isHidden ?? false || name.hasPrefix(".")

        let metadata = entryLoadingClient.getItemMetadata(itemURL, isDirectory.boolValue, workspaceClient)
        let lastOpenedDate = metadata.lastUsedDate
        let tags = entryTags(from: itemURL)

        let supplementaryMetadata = entrySupplementaryMetadata(
            url: itemURL,
            isDirectory: isDirectory.boolValue,
            entryLoadingClient: entryLoadingClient,
        )

        return EntryModel(
            name: name,
            fullPath: itemURL.path,
            isFolder: isDirectory.boolValue,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            fileExtension: itemURL.pathExtension,
            facets: EntryFacets(
                createdDate: createdDate,
                addedDate: addedDate,
                lastOpenedDate: lastOpenedDate,
                kind: metadata.kind,
                creatorApplication: metadata.creatorApplication,
                tags: tags,
                supplementaryMetadata: supplementaryMetadata,
            ),
        )
    }

    private nonisolated static func entryTags(from itemURL: URL) -> [Tag]? {
        if let tags = TagMetadataClient.loadTags(from: itemURL) {
            return tags
        }

        if let tagNames = try? itemURL.resourceValues(forKeys: [.tagNamesKey]).tagNames {
            let tags = tagNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { Tag(name: $0, colorCode: 0) }
            return tags.isEmpty ? nil : tags
        }
        return nil
    }

    private nonisolated static func entrySupplementaryMetadata(
        url: URL,
        isDirectory: Bool,
        entryLoadingClient: EntryLoadingClient,
    ) -> EntrySupplementaryMetadata? {
        if isDirectory {
            if entryLoadingClient.isPackageDirectory(url) {
                return nil
            }
            let ext = url.pathExtension.lowercased()
            if ext == CollectionConstants.fileExtension {
                return nil
            }
            guard let itemCount = entryLoadingClient.getFolderItemCount(url) else {
                return nil
            }
            return .folderItemCount(itemCount)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext),
           let resolution = entryLoadingClient.getImageResolution(url)
        {
            return .imageResolution(width: resolution.width, height: resolution.height)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext),
           let fileSizeInBytes = entryLoadingClient.getFileSizeInBytes(url)
        {
            return .compressedFileSize(fileSizeInBytes)
        }

        return nil
    }
}

private enum EntryModelPayloadAdapter {
    nonisolated static func makeEntry(_ payload: SearchEntryPayload) -> EntryModel {
        EntryModel(
            name: payload.name,
            fullPath: payload.fullPath,
            isFolder: payload.isFolder,
            isHidden: payload.isHidden,
            size: payload.size,
            modifiedDate: payload.modifiedDate,
            fileExtension: payload.fileExtension,
            facets: EntryFacets(
                createdDate: payload.createdDate,
                addedDate: payload.addedDate,
                lastOpenedDate: payload.lastOpenedDate,
                kind: payload.kind,
                creatorApplication: payload.creatorApplication,
                tags: payload.tags?.map { Tag(name: $0.name, colorCode: $0.colorCode) },
                supplementaryMetadata: makeSupplementaryMetadata(payload.supplementaryMetadata),
            ),
        )
    }

    private nonisolated static func makeSupplementaryMetadata(
        _ payload: SearchEntrySupplementaryMetadataPayload?,
    ) -> EntrySupplementaryMetadata? {
        guard let payload else {
            return nil
        }

        switch payload {
        case let .folderItemCount(itemCount):
            return .folderItemCount(itemCount)
        case let .imageResolution(width, height):
            return .imageResolution(width: width, height: height)
        case let .compressedFileSize(fileSize):
            return .compressedFileSize(fileSize)
        }
    }
}
