import AppKit
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension EntryClient {
    nonisolated static var liveSetDefaultApp: @Sendable (UTType, String) async throws -> Void {
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

    nonisolated static var liveApplicationsForFile: @Sendable (URL) async -> [ApplicationInfo] {
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

    nonisolated static var liveDefaultApplication: @Sendable (UTType) async -> ApplicationInfo? {
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
            // TODO: displayName을 EntryClient 메서드로 전환할 때 변경

            return await MainActor.run {
                ApplicationInfo(id: bundleID, name: name, bundleID: bundleID)
            }
        }
    }

    nonisolated static var liveLoadItems: @Sendable (URL, Bool) async throws -> [Entry] {
        { directoryURL, showHidden in
            try await Task.detached {
                let entryClient = EntryClient.liveValue
                let workspaceClient = WorkspaceClient.liveValue
                let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]

                let contents = try entryClient.contentsOfDirectory(
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

                return contents.compactMap { url in
                    EntryLoadUtils.convertURLToEntry(
                        url,
                        entryClient: entryClient,
                        workspaceClient: workspaceClient,
                    )
                }
            }.value
        }
    }

    nonisolated static var liveLoadComputerItems: @Sendable () async throws -> [Entry] {
        {
            await Task.detached {
                let rootName = FileManager.default.displayName(atPath: "/")
                return [
                    Entry(
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

    nonisolated static var liveFileExists: @Sendable (String) -> Bool {
        { path in
            FileManager.default.fileExists(atPath: path)
        }
    }

    nonisolated static var liveFileExistsAtPath: @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool {
        { path, isDirectory in
            FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
        }
    }

    nonisolated static var liveDisplayName: @Sendable (String) -> String {
        { path in
            FileManager.default.displayName(atPath: path)
        }
    }

    nonisolated static var liveUrlsForDirectory: @Sendable (
        FileManager.SearchPathDirectory,
        FileManager.SearchPathDomainMask,
    ) -> [URL] {
        { directory, domain in
            FileManager.default.urls(for: directory, in: domain)
        }
    }

    nonisolated static var liveHomeDirectory: @Sendable () -> String {
        {
            NSHomeDirectory()
        }
    }

    nonisolated static var liveTrashDirectoryPath: @Sendable () -> String? {
        {
            FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
        }
    }

    nonisolated static var liveMountedVolumeURLs: @Sendable (
        [URLResourceKey],
        FileManager.VolumeEnumerationOptions,
    ) -> [URL]? {
        { keys, options in
            FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: options)
        }
    }

    nonisolated static var liveContentsOfDirectory: @Sendable (
        URL,
        [URLResourceKey],
        FileManager.DirectoryEnumerationOptions,
    ) throws -> [URL] {
        { url, keys, options in
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
        }
    }

    nonisolated static var liveGetItemMetadata: @Sendable (URL, Bool, WorkspaceClient) -> (
        kind: String,
        creatorApplication: String?,
        lastUsedDate: Date?,
    ) {
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
                    if let contentType = MDItemCopyAttribute(mdItem, kMDItemContentType) as? String {
                        if let uti = UTType(mimeType: contentType) {
                            kind = uti.localizedDescription ?? contentType
                        }
                    }

                    if let appURL = workspaceClient.urlForApplicationToOpen(url) {
                        creatorApplication = appURL.deletingPathExtension().lastPathComponent
                    }
                }

                if let lastUsed = MDItemCopyAttribute(mdItem, "kMDItemLastUsedDate" as CFString) as? Date {
                    lastUsedDate = lastUsed
                }
            }

            return (kind: kind, creatorApplication: creatorApplication, lastUsedDate: lastUsedDate)
        }
    }

    nonisolated static var liveGetImageResolution: @Sendable (URL) -> String? {
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

    nonisolated static var liveGetFormattedFileSize: @Sendable (URL) -> String? {
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

    nonisolated static var liveGetFolderItemCount: @Sendable (URL) -> String? {
        { url in
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            ) else {
                return nil
            }

            let count = contents.count
            if count == 0 {
                return "No items"
            }
            return "\(count) item\(count == 1 ? "" : "s")"
        }
    }

    nonisolated static var liveIsPackageDirectory: @Sendable (URL) -> Bool {
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
}
