import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
