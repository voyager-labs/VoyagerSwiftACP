import ComposableArchitecture
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
    public var loadDragPaths: @Sendable () -> [String]
    public var getItemMetadata: @Sendable (URL, Bool, WorkspaceClient) -> EntryItemMetadata
    public var getImageResolution: @Sendable (URL) -> String?
    public var getFormattedFileSize: @Sendable (URL) -> String?
    public var getFolderItemCount: @Sendable (URL) -> String?
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
            loadDragPaths: EntryFileOpsLive.loadDragPaths,
            getItemMetadata: EntryLoadingLive.getItemMetadata,
            getImageResolution: EntryLoadingLive.getImageResolution,
            getFormattedFileSize: EntryLoadingLive.getFormattedFileSize,
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

enum EntryLoadingLive {
    nonisolated static var loadItems: @Sendable (URL, Bool) async throws -> [EntryModel] {
        { directoryURL, showHidden in
            try await Task.detached {
                let entryLoadingClient = EntryLoadingClient.liveValue
                let workspaceClient = WorkspaceClient.liveValue
                let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]

                let entries = try contentsOfDirectory(
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
                let rootName = FileManager.default.displayName(atPath: "/")
                return [
                    EntryModel(
                        name: rootName,
                        fullPath: "/",
                        isDirectory: true,
                        isHidden: false,
                        kind: "Volume",
                    ),
                ]
            }.value
        }
    }

    nonisolated static var fileExists: @Sendable (String) -> Bool {
        { path in
            FileManager.default.fileExists(atPath: path)
        }
    }

    nonisolated static var fileExistsAtPath: @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool {
        { path, isDirectory in
            FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
        }
    }

    nonisolated static var displayName: @Sendable (String) -> String {
        { path in
            FileManager.default.displayName(atPath: path)
        }
    }

    nonisolated static var urlsForDirectory: @Sendable (
        FileManager.SearchPathDirectory,
        FileManager.SearchPathDomainMask,
    ) -> [URL] {
        { directory, domain in
            FileManager.default.urls(for: directory, in: domain)
        }
    }

    nonisolated static var homeDirectory: @Sendable () -> String {
        {
            NSHomeDirectory()
        }
    }

    nonisolated static var trashDirectoryPath: @Sendable () -> String? {
        {
            FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
        }
    }

    nonisolated static var mountedVolumeURLs: @Sendable (
        [URLResourceKey],
        FileManager.VolumeEnumerationOptions,
    ) -> [URL]? {
        { keys, options in
            FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: options)
        }
    }

    nonisolated static var contentsOfDirectory: @Sendable (
        URL,
        [URLResourceKey],
        FileManager.DirectoryEnumerationOptions,
    ) throws -> [URL] {
        { url, keys, options in
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
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

    nonisolated static var getImageResolution: @Sendable (URL) -> String? {
        { url in
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int
            else {
                return nil
            }

            return "\(width) × \(height)"
        }
    }

    nonisolated static var getFormattedFileSize: @Sendable (URL) -> String? {
        { url in
            guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize
            else {
                return nil
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            formatter.includesUnit = true
            formatter.isAdaptive = true

            return formatter.string(fromByteCount: Int64(fileSize))
        }
    }

    nonisolated static var getFolderItemCount: @Sendable (URL) -> String? {
        { url in
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            ) else {
                return nil
            }

            let count = entries.count
            if count == 0 {
                return "No items"
            }
            return "\(count) item\(count == 1 ? "" : "s")"
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
        { showHidden, workspaceClient in
            await EntryMetadataSearchLive.loadRecentItems(
                showHidden: showHidden,
                workspaceClient: workspaceClient,
                fileExistsAtPath: fileExistsAtPath,
            )
        }
    }

    nonisolated static var loadFilesWithTag: @Sendable (String, Bool, WorkspaceClient) async -> [EntryModel] {
        { tag, showHidden, workspaceClient in
            await EntryMetadataSearchLive.loadFilesWithTag(
                tag: tag,
                showHidden: showHidden,
                workspaceClient: workspaceClient,
                fileExistsAtPath: fileExistsAtPath,
            )
        }
    }
}

private final class MetadataQueryCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var hasCompleted = false

    nonisolated func setCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasCompleted {
            return false
        }
        hasCompleted = true
        return true
    }
}

private final class MetadataQueryWrapper: @unchecked Sendable {
    nonisolated(unsafe) let query: NSMetadataQuery

    init(_ query: NSMetadataQuery) {
        self.query = query
    }
}

private final class MetadataObserverWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(_ observer: NSObjectProtocol?) {
        self.observer = observer
    }

    nonisolated func setObserver(_ observer: NSObjectProtocol?) {
        lock.lock()
        defer { lock.unlock() }
        if let oldObserver = self.observer {
            NotificationCenter.default.removeObserver(oldObserver)
        }
        self.observer = observer
    }

    nonisolated func remove() {
        lock.lock()
        defer { lock.unlock() }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}

enum EntryMetadataSearchLive {
    nonisolated static func loadRecentItems(
        showHidden: Bool,
        workspaceClient: WorkspaceClient,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
    ) async -> [EntryModel] {
        let entryLoadingClient = EntryLoadingClient.liveValue
        let predicate = NSPredicate(format: "kMDItemLastUsedDate > %@", Date.distantPast as NSDate)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let recentFiles = await searchFiles(
            predicate: predicate,
            fileExistsAtPath: fileExistsAtPath,
            sortDescriptors: sortDescriptors,
            filterFiles: true,
        )

        let items = recentFiles.compactMap { url in
            EntryModelConverterLive.convertURLToEntry(
                url,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            )
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    nonisolated static func loadFilesWithTag(
        tag: String,
        showHidden: Bool,
        workspaceClient: WorkspaceClient,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
    ) async -> [EntryModel] {
        let entryLoadingClient = EntryLoadingClient.liveValue
        let predicate = NSPredicate(format: "kMDItemUserTags CONTAINS %@", tag)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let taggedFiles = await searchFiles(
            predicate: predicate,
            fileExistsAtPath: fileExistsAtPath,
            sortDescriptors: sortDescriptors,
        )

        let items: [EntryModel] = taggedFiles.compactMap { url in
            guard let item = EntryModelConverterLive.convertURLToEntry(
                url,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            ) else {
                return nil
            }

            let hasTags = item.tags?.contains(where: { $0.name == tag }) ?? false
            return hasTags ? item : nil
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    @MainActor
    private static func searchFiles(
        predicate: NSPredicate,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
        sortDescriptors: [NSSortDescriptor] = [],
        timeout: TimeInterval = 5,
        filterFiles: Bool = false,
    ) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = []
                query.predicate = predicate
                query.sortDescriptors = sortDescriptors

                let completionState = MetadataQueryCompletionState()
                let queryWrapper = MetadataQueryWrapper(query)
                let observerWrapper = MetadataObserverWrapper(nil)

                let observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: queryWrapper.query,
                    queue: .main,
                ) { _ in
                    let capturedQuery = queryWrapper.query
                    Task { @MainActor in
                        guard completionState.setCompleted() else { return }
                        capturedQuery.stop()

                        let urls: [URL] = Array(capturedQuery.results
                            .compactMap { $0 as? NSMetadataItem }
                            .compactMap { item -> URL? in
                                guard let path = item.value(forAttribute: "kMDItemPath") as? String
                                else { return nil }

                                if filterFiles {
                                    var isDirectory: ObjCBool = false
                                    if fileExistsAtPath(path, &isDirectory), isDirectory.boolValue {
                                        return nil
                                    }
                                }

                                return URL(fileURLWithPath: path)
                            }
                            .prefix(100))

                        continuation.resume(returning: urls)
                        observerWrapper.remove()
                    }
                }

                observerWrapper.setObserver(observer)
                query.start()

                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    let capturedQuery = queryWrapper.query
                    Task { @MainActor in
                        guard completionState.setCompleted() else { return }
                        capturedQuery.stop()
                        continuation.resume(returning: [])
                        observerWrapper.remove()
                    }
                }
            }
        }
    }
}

enum EntryModelConverterLive {
    private nonisolated static let entryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private nonisolated(unsafe) static let entryByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

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

        let additionalInfo = entryAdditionalInfo(
            url: itemURL,
            isDirectory: isDirectory.boolValue,
            entryLoadingClient: entryLoadingClient,
        )

        let formattedSize = isDirectory.boolValue ? "--" : entryByteFormatter.string(fromByteCount: size)
        let formattedModifiedDate = entryDateFormatter.string(from: modifiedDate)
        let formattedCreatedDate = entryDateFormatter.string(from: createdDate)

        return EntryModel(
            name: name,
            fullPath: itemURL.path,
            isDirectory: isDirectory.boolValue,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            addedDate: addedDate,
            lastOpenedDate: lastOpenedDate,
            fileExtension: itemURL.pathExtension,
            kind: metadata.kind,
            creatorApplication: metadata.creatorApplication,
            tags: tags,
            additionalInfo: additionalInfo,
            formattedSize: formattedSize,
            formattedModifiedDate: formattedModifiedDate,
            formattedCreatedDate: formattedCreatedDate,
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

    private nonisolated static func entryAdditionalInfo(
        url: URL,
        isDirectory: Bool,
        entryLoadingClient: EntryLoadingClient,
    ) -> String? {
        if isDirectory {
            if entryLoadingClient.isPackageDirectory(url) {
                return nil
            }
            let ext = url.pathExtension.lowercased()
            if ext == CollectionConstants.fileExtension {
                return nil
            }
            return entryLoadingClient.getFolderItemCount(url)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext) {
            return entryLoadingClient.getImageResolution(url)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext) {
            return entryLoadingClient.getFormattedFileSize(url)
        }

        return nil
    }
}
