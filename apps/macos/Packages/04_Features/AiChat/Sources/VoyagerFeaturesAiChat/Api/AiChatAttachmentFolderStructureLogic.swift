import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

extension AiChatAttachmentResolverClient {
    static func directoryReferenceMetadata(
        base: [String: String],
        directoryURL: URL?,
        fileManagerClient: FileManagerClient,
    ) -> [String: String] {
        var metadata = base
        guard let directoryURL else { return metadata }
        do {
            let urls = try fileManagerClient.contentsOfDirectory(
                directoryURL,
                [.isDirectoryKey, .isRegularFileKey],
                [.skipsHiddenFiles],
            )
            let sorted = urls
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let limit = 80
            let paths = sorted.prefix(limit).map { $0.path(percentEncoded: false) }
            metadata["collectionItemCount"] = "\(urls.count)"
            metadata["collectionItemsIncluded"] = "\(paths.count)"
            metadata["collectionItemsTruncated"] = urls.count > limit ? "true" : "false"
            if !paths.isEmpty {
                metadata["collectionItemPaths"] = paths.joined(separator: "\n")
            }
        } catch {
            metadata["collectionSnapshotStatus"] = CollectionFileReferenceSnapshotStatus.missing.rawValue
        }
        return metadata
    }

    static func folderStructureMetadata(
        base: [String: String],
        directoryURL: URL?,
        mode: AiChatFolderStructureMode,
        fileManagerClient: FileManagerClient,
    ) -> [String: String] {
        var metadata = directoryReferenceMetadata(
            base: base,
            directoryURL: directoryURL,
            fileManagerClient: fileManagerClient,
        )
        metadata["folderStructureMode"] = mode.rawValue
        guard mode == .includeSubfolders else {
            return metadata
        }
        guard let directoryURL else {
            metadata["collectionSnapshotStatus"] = CollectionFileReferenceSnapshotStatus.missing.rawValue
            return metadata
        }

        let snapshot = folderStructureSnapshot(rootURL: directoryURL, fileManagerClient: fileManagerClient)
        metadata["folderStructurePathStyle"] = "relativeToSelectedFolder"
        metadata["folderStructureRootName"] = directoryURL.lastPathComponent.isEmpty ? directoryURL
            .path(percentEncoded: false) : directoryURL.lastPathComponent
        metadata["folderStructureMaxDepth"] = "8"
        metadata["folderStructureMaxEntries"] = "1000"
        metadata["folderStructureUTF8ByteBudget"] = "65536"
        metadata["folderStructureEntriesIncluded"] = "\(snapshot.includedCount)"
        metadata["folderStructureEntriesTruncated"] = snapshot.truncated ? "true" : "false"
        metadata["folderStructureSkippedCount"] = "\(snapshot.skippedCount)"
        metadata["folderStructureSymlinkEscapes"] = "\(snapshot.symlinkEscapes)"
        metadata["folderStructureReadFailures"] = "\(snapshot.readFailures)"
        if !snapshot.entries.isEmpty {
            metadata["folderStructureEntries"] = snapshot.entries.joined(separator: "\n")
        }
        if !snapshot.directoryFilePaths.isEmpty {
            metadata["folderStructureDirectoryFilePaths"] = snapshot.directoryFilePaths.joined(separator: "\n")
        }
        return metadata
    }

    static func folderStructureMode(from metadata: [String: String]) -> AiChatFolderStructureMode {
        AiChatFolderStructureMode(rawValue: metadata["folderStructureMode"] ?? "") ?? .currentFolderOnly
    }

    static func folderStructureSnapshot(
        rootURL: URL,
        fileManagerClient: FileManagerClient,
    ) -> FolderStructureSnapshot {
        let rootURL = rootURL.standardizedFileURL
        let rootCanonicalURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootCanonicalPath = rootCanonicalURL.path(percentEncoded: false)
        let rootRelativePath = rootCanonicalURL.lastPathComponent.isEmpty ? rootCanonicalPath : rootCanonicalURL
            .lastPathComponent
        var snapshot = FolderStructureSnapshot(rootPath: rootCanonicalPath)

        guard let resourceValues = try? rootCanonicalURL.resourceValues(forKeys: [.isDirectoryKey]) else {
            snapshot.readFailures += 1
            snapshot.truncated = true
            return snapshot
        }
        guard resourceValues.isDirectory == true else {
            snapshot.readFailures += 1
            snapshot.truncated = true
            return snapshot
        }

        snapshot.entries.append("directory\t0\t\(rootRelativePath)")
        snapshot.includedCount += 1
        snapshot.bytesUsed += snapshot.entries.last?.utf8.count ?? 0

        collectFolderStructureEntries(
            at: rootCanonicalURL,
            relativePath: rootRelativePath,
            depth: 0,
            snapshot: &snapshot,
            context: FolderTraversalContext(
                rootCanonicalPath: rootCanonicalPath,
                fileManagerClient: fileManagerClient,
            ),
        )
        return snapshot
    }

    struct FolderTraversalContext {
        var rootCanonicalPath: String
        var fileManagerClient: FileManagerClient
    }

    static func collectFolderStructureEntries(
        at directoryURL: URL,
        relativePath: String,
        depth: Int,
        snapshot: inout FolderStructureSnapshot,
        context _: FolderTraversalContext,
    ) {
        guard !snapshot.truncated, snapshot.includedCount < 1000, depth < 8 else {
            snapshot.truncated = true
            return
        }

        guard let sortedChildren = sortedFolderStructureChildren(
            at: directoryURL,
            snapshot: &snapshot,
            fileManagerClient: context.fileManagerClient,
        ) else { return }

        appendDirectoryFilePaths(
            directoryRelativePath: relativePath,
            children: sortedChildren,
            snapshot: &snapshot,
        )

        for child in sortedChildren {
            guard !snapshot.truncated, snapshot.includedCount < 1000 else {
                snapshot.truncated = true
                return
            }

            appendFolderStructureChild(
                child,
                parentRelativePath: relativePath,
                depth: depth,
                snapshot: &snapshot,
                context: context,
            )
        }
    }

    static func sortedFolderStructureChildren(
        at directoryURL: URL,
        snapshot: inout FolderStructureSnapshot,
        fileManagerClient: FileManagerClient,
    ) -> [URL]? {
        do {
            return try fileManagerClient.contentsOfDirectory(
                directoryURL,
                [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey],
                [.skipsHiddenFiles],
            )
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
        } catch {
            snapshot.readFailures += 1
            return nil
        }
    }

    static func appendFolderStructureChild(
        _ child: URL,
        parentRelativePath: String,
        depth: Int,
        snapshot: inout FolderStructureSnapshot,
        context _: FolderTraversalContext,
    ) {
        let childRelativePath = parentRelativePath.isEmpty
            ? child.lastPathComponent
            : parentRelativePath + "/" + child.lastPathComponent
        let resourceValues = try? child.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
        ])

        if shouldSkipFolderStructureChild(child, resourceValues: resourceValues) {
            snapshot.skippedCount += 1
            return
        }

        if resourceValues?.isSymbolicLink == true {
            appendFolderStructureSymlink(
                child,
                relativePath: childRelativePath,
                depth: depth,
                rootCanonicalPath: context.rootCanonicalPath,
                snapshot: &snapshot,
            )
        } else if isPackageDirectory(child) {
            appendFolderStructureEntry(
                kind: "package",
                depth: depth + 1,
                relativePath: childRelativePath,
                snapshot: &snapshot,
            )
        } else if resourceValues?.isDirectory == true {
            appendFolderStructureDirectory(
                child,
                relativePath: childRelativePath,
                depth: depth,
                snapshot: &snapshot,
                context: context,
            )
        } else if resourceValues?.isRegularFile == true {
            appendFolderStructureEntry(
                kind: "file",
                depth: depth + 1,
                relativePath: childRelativePath,
                snapshot: &snapshot,
            )
        } else {
            snapshot.skippedCount += 1
        }
    }

    static func shouldSkipFolderStructureChild(
        _ child: URL,
        resourceValues: URLResourceValues?,
    ) -> Bool {
        resourceValues?.isHidden == true
            || child.lastPathComponent.hasPrefix(".")
            || isHeavyFolder(name: child.lastPathComponent)
    }

    static func appendFolderStructureSymlink(
        _ child: URL,
        relativePath: String,
        depth: Int,
        rootCanonicalPath: String,
        snapshot: inout FolderStructureSnapshot,
    ) {
        let childCanonicalPath = child.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let isWithinRoot = childCanonicalPath == rootCanonicalPath || childCanonicalPath
            .hasPrefix(rootCanonicalPath + "/")
        snapshot.symlinkEscapes += 1
        appendFolderStructureEntry(
            kind: isWithinRoot ? "symlink-skipped" : "symlink-escape-skipped",
            depth: depth + 1,
            relativePath: relativePath,
            snapshot: &snapshot,
        )
    }

    static func appendFolderStructureDirectory(
        _ child: URL,
        relativePath: String,
        depth: Int,
        snapshot: inout FolderStructureSnapshot,
        context: FolderTraversalContext,
    ) {
        appendFolderStructureEntry(kind: "directory", depth: depth + 1, relativePath: relativePath, snapshot: &snapshot)
        collectFolderStructureEntries(
            at: child.standardizedFileURL,
            relativePath: relativePath,
            depth: depth + 1,
            snapshot: &snapshot,
            context: context,
        )
    }

    static func appendDirectoryFilePaths(
        directoryRelativePath: String,
        children: [URL],
        snapshot: inout FolderStructureSnapshot,
    ) {
        for child in children {
            let resourceValues = try? child.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isHiddenKey,
            ])
            guard resourceValues?.isRegularFile == true,
                  resourceValues?.isHidden != true,
                  resourceValues?.isSymbolicLink != true,
                  !child.lastPathComponent.hasPrefix(".")
            else { continue }

            let fileRelativePath = directoryRelativePath.isEmpty
                ? child.lastPathComponent
                : directoryRelativePath + "/" + child.lastPathComponent
            let line = "\(directoryRelativePath)\t\(fileRelativePath)"
            guard consumeFolderStructureMetadataBudget(for: line, snapshot: &snapshot) else { return }
            snapshot.directoryFilePaths.append(line)
        }
    }

    static func appendFolderStructureEntry(
        kind: String,
        depth: Int,
        relativePath: String,
        snapshot: inout FolderStructureSnapshot,
    ) {
        let line = "\(kind)\t\(depth)\t\(relativePath)"
        guard consumeFolderStructureMetadataBudget(for: line, snapshot: &snapshot) else { return }
        snapshot.entries.append(line)
        snapshot.includedCount += 1
    }

    static func consumeFolderStructureMetadataBudget(
        for line: String,
        snapshot: inout FolderStructureSnapshot,
    ) -> Bool {
        guard !snapshot.truncated else { return false }
        let lineBytes = line.utf8.count + (snapshot.metadataLineCount == 0 ? 0 : 1)
        guard snapshot.bytesUsed + lineBytes <= 64 * 1024 else {
            snapshot.truncated = true
            return false
        }
        guard snapshot.metadataLineCount < 1000 else {
            snapshot.truncated = true
            return false
        }
        snapshot.metadataLineCount += 1
        snapshot.bytesUsed += lineBytes
        return true
    }

    static func isPackageDirectory(_ url: URL) -> Bool {
        let extensionSet: Set = ["app", "framework", "xcarchive", "playground", "xcodeproj"]
        return extensionSet.contains(url.pathExtension.lowercased())
    }

    static func isHeavyFolder(name: String) -> Bool {
        let heavyNames: Set = [
            "node_modules", ".build", ".swiftpm", "DerivedData", "build", "dist", ".next", ".turbo", ".cache", "Pods",
            "Carthage",
        ]
        return heavyNames.contains(name)
    }

    struct FolderStructureSnapshot {
        var rootPath: String
        var entries: [String] = []
        var directoryFilePaths: [String] = []
        var includedCount: Int = 0
        var metadataLineCount: Int = 0
        var skippedCount: Int = 0
        var symlinkEscapes: Int = 0
        var readFailures: Int = 0
        var bytesUsed: Int = 0
        var truncated: Bool = false
    }
}
