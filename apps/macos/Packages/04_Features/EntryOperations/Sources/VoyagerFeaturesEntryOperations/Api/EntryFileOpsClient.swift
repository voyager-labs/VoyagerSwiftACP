import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

public struct EntryFileOpsClient: Sendable {
    public var createFolder: @Sendable (URL, String) async throws -> Void
    public var pasteFile: @Sendable (URL, URL) async throws -> Void
    public var moveFile: @Sendable (URL, URL) async throws -> Void
    public var renameFile: @Sendable (URL, URL) async throws -> Void
    public var createAlias: @Sendable (URL, URL) async throws -> Void
    public var moveToTrashAndReturnURL: @Sendable (URL) async throws -> URL
    public var deleteImmediately: @Sendable (URL) async throws -> Void
    public var putBackFromTrash: @Sendable (URL, String) async throws -> Void
    public var compressItems: @Sendable ([URL]) async throws -> URL
    public var extractCompressedFile: @Sendable (URL) async throws -> Void
    public var getTags: @Sendable (URL) async throws -> [String]
    public var setTags: @Sendable (URL, [String]) async throws -> Void
    public var toggleTag: @Sendable (URL, String) async throws -> Void
    public var fileExists: @Sendable (String) -> Bool
    public var saveDragPaths: @Sendable ([String]) -> Void
    public var loadDragPaths: @Sendable () -> [String]
    public var saveDragWithOption: @Sendable (Bool) -> Void
    public var loadDragWithOption: @Sendable () -> Bool
    public var clipboardChangeCount: @Sendable () -> Int
    public var loadClipboardCutSessionId: @Sendable () -> String?
    public var saveClipboardCutSessionId: @Sendable (String?) -> Void
    public var loadClipboardPaths: @Sendable () -> ([String], ClipboardOperation)
    public var postFileSystemChanged: @Sendable ([String]) -> Void

    nonisolated public init(
        createFolder: @escaping @Sendable (URL, String) async throws -> Void,
        pasteFile: @escaping @Sendable (URL, URL) async throws -> Void,
        moveFile: @escaping @Sendable (URL, URL) async throws -> Void,
        renameFile: @escaping @Sendable (URL, URL) async throws -> Void,
        createAlias: @escaping @Sendable (URL, URL) async throws -> Void,
        moveToTrashAndReturnURL: @escaping @Sendable (URL) async throws -> URL,
        deleteImmediately: @escaping @Sendable (URL) async throws -> Void,
        putBackFromTrash: @escaping @Sendable (URL, String) async throws -> Void,
        compressItems: @escaping @Sendable ([URL]) async throws -> URL,
        extractCompressedFile: @escaping @Sendable (URL) async throws -> Void,
        getTags: @escaping @Sendable (URL) async throws -> [String],
        setTags: @escaping @Sendable (URL, [String]) async throws -> Void,
        toggleTag: @escaping @Sendable (URL, String) async throws -> Void,
        fileExists: @escaping @Sendable (String) -> Bool,
        saveDragPaths: @escaping @Sendable ([String]) -> Void,
        loadDragPaths: @escaping @Sendable () -> [String],
        saveDragWithOption: @escaping @Sendable (Bool) -> Void,
        loadDragWithOption: @escaping @Sendable () -> Bool,
        clipboardChangeCount: @escaping @Sendable () -> Int,
        loadClipboardCutSessionId: @escaping @Sendable () -> String?,
        saveClipboardCutSessionId: @escaping @Sendable (String?) -> Void,
        loadClipboardPaths: @escaping @Sendable () -> ([String], ClipboardOperation),
        postFileSystemChanged: @escaping @Sendable ([String]) -> Void,
    ) {
        self.createFolder = createFolder
        self.pasteFile = pasteFile
        self.moveFile = moveFile
        self.renameFile = renameFile
        self.createAlias = createAlias
        self.moveToTrashAndReturnURL = moveToTrashAndReturnURL
        self.deleteImmediately = deleteImmediately
        self.putBackFromTrash = putBackFromTrash
        self.compressItems = compressItems
        self.extractCompressedFile = extractCompressedFile
        self.getTags = getTags
        self.setTags = setTags
        self.toggleTag = toggleTag
        self.fileExists = fileExists
        self.saveDragPaths = saveDragPaths
        self.loadDragPaths = loadDragPaths
        self.saveDragWithOption = saveDragWithOption
        self.loadDragWithOption = loadDragWithOption
        self.clipboardChangeCount = clipboardChangeCount
        self.loadClipboardCutSessionId = loadClipboardCutSessionId
        self.saveClipboardCutSessionId = saveClipboardCutSessionId
        self.loadClipboardPaths = loadClipboardPaths
        self.postFileSystemChanged = postFileSystemChanged
    }
}

extension EntryFileOpsClient: DependencyKey {
    nonisolated public static var liveValue: EntryFileOpsClient {
        EntryFileOpsClient(
            createFolder: EntryFileOpsLive.createFolder,
            pasteFile: EntryFileOpsLive.pasteFile,
            moveFile: EntryFileOpsLive.moveFile,
            renameFile: EntryFileOpsLive.renameFile,
            createAlias: EntryFileOpsLive.createAlias,
            moveToTrashAndReturnURL: EntryFileOpsLive.moveToTrashAndReturnURL,
            deleteImmediately: EntryFileOpsLive.deleteImmediately,
            putBackFromTrash: EntryFileOpsLive.putBackFromTrash,
            compressItems: EntryFileOpsLive.compressItems,
            extractCompressedFile: EntryFileOpsLive.extractCompressedFile,
            getTags: EntryFileOpsLive.getTags,
            setTags: EntryFileOpsLive.setTags,
            toggleTag: EntryFileOpsLive.toggleTag,
            fileExists: EntryFileOpsLive.fileExists,
            saveDragPaths: EntryFileOpsLive.saveDragPaths,
            loadDragPaths: EntryFileOpsLive.loadDragPaths,
            saveDragWithOption: EntryFileOpsLive.saveDragWithOption,
            loadDragWithOption: EntryFileOpsLive.loadDragWithOption,
            clipboardChangeCount: EntryFileOpsLive.clipboardChangeCount,
            loadClipboardCutSessionId: EntryFileOpsLive.loadClipboardCutSessionId,
            saveClipboardCutSessionId: EntryFileOpsLive.saveClipboardCutSessionId,
            loadClipboardPaths: EntryFileOpsLive.loadClipboardPaths,
            postFileSystemChanged: EntryFileOpsLive.postFileSystemChanged,
        )
    }

    nonisolated public static var testValue: EntryFileOpsClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryFileOpsClient test dependency not set.")
        }
        return EntryFileOpsClient(
            createFolder: { _, _ in unimplemented() },
            pasteFile: { _, _ in unimplemented() },
            moveFile: { _, _ in unimplemented() },
            renameFile: { _, _ in unimplemented() },
            createAlias: { _, _ in unimplemented() },
            moveToTrashAndReturnURL: { _ in unimplemented() },
            deleteImmediately: { _ in unimplemented() },
            putBackFromTrash: { _, _ in unimplemented() },
            compressItems: { _ in unimplemented() },
            extractCompressedFile: { _ in unimplemented() },
            getTags: { _ in unimplemented() },
            setTags: { _, _ in unimplemented() },
            toggleTag: { _, _ in unimplemented() },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            clipboardChangeCount: { 0 },
            loadClipboardCutSessionId: { nil },
            saveClipboardCutSessionId: { _ in },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
        )
    }

    nonisolated public static var previewValue: EntryFileOpsClient {
        EntryFileOpsClient(
            createFolder: { _, _ in },
            pasteFile: { _, _ in },
            moveFile: { _, _ in },
            renameFile: { _, _ in },
            createAlias: { _, _ in },
            moveToTrashAndReturnURL: { _ in URL(fileURLWithPath: "/tmp/.Trash/test") },
            deleteImmediately: { _ in },
            putBackFromTrash: { _, _ in },
            compressItems: { _ in URL(fileURLWithPath: "/tmp/Archive.zip") },
            extractCompressedFile: { _ in },
            getTags: { _ in [] },
            setTags: { _, _ in },
            toggleTag: { _, _ in },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            clipboardChangeCount: { 0 },
            loadClipboardCutSessionId: { nil },
            saveClipboardCutSessionId: { _ in },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryFileOpsClient: EntryFileOpsClient {
        get { self[EntryFileOpsClient.self] }
        set { self[EntryFileOpsClient.self] = newValue }
    }
}

enum EntryFileOpsLive {
    nonisolated static var createFolder: @Sendable (URL, String) async throws -> Void {
        { parentURL, folderName in
            let folderURL = parentURL.appendingPathComponent(folderName)
            try FileManagerClient.liveValue.createDirectory(
                folderURL,
                false,
                nil,
            )
        }
    }

    nonisolated static var pasteFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManagerClient.liveValue.fileExists(destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManagerClient.liveValue.copyItem(sourceURL, destinationURL)
        }
    }

    nonisolated static var moveFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManagerClient.liveValue.fileExists(destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManagerClient.liveValue.moveItem(sourceURL, destinationURL)
        }
    }

    nonisolated static var renameFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManagerClient.liveValue.fileExists(destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManagerClient.liveValue.moveItem(sourceURL, destinationURL)
        }
    }

    nonisolated static var createAlias: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, aliasURL in
            if FileManagerClient.liveValue.fileExists(aliasURL.path) {
                throw FileOpError.fileExists(itemName: aliasURL.lastPathComponent)
            }
            let bookmarkData = try sourceURL.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
            try URL.writeBookmarkData(bookmarkData, to: aliasURL)
        }
    }

    nonisolated static var moveToTrashAndReturnURL: @Sendable (URL) async throws -> URL {
        { url in
            try await MainActor.run {
                try FileManagerClient.liveValue.trashItem(url)
            }
        }
    }

    nonisolated static var deleteImmediately: @Sendable (URL) async throws -> Void {
        { url in
            try FileManagerClient.liveValue.removeItem(url)
        }
    }

    nonisolated static var putBackFromTrash: @Sendable (URL, String) async throws -> Void {
        { trashURL, originalPath in
            let originalURL = URL(fileURLWithPath: originalPath)

            let parentURL = originalURL.deletingLastPathComponent()
            if !FileManagerClient.liveValue.fileExists(parentURL.path) {
                try FileManagerClient.liveValue.createDirectory(
                    parentURL,
                    true,
                    nil,
                )
            }

            if FileManagerClient.liveValue.fileExists(originalURL.path) {
                throw FileOpError.fileExists(itemName: originalURL.lastPathComponent)
            }

            try FileManagerClient.liveValue.moveItem(trashURL, originalURL)

            await TrashMetadataStoreClient.liveValue.remove(trashURL.path)
        }
    }

    nonisolated static var compressItems: @Sendable ([URL]) async throws -> URL {
        { itemURLs in
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
            while FileManagerClient.liveValue.fileExists(archiveURL.path) {
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
        }
    }

    nonisolated static var extractCompressedFile: @Sendable (URL) async throws -> Void {
        { zipURL in
            guard zipURL.pathExtension.lowercased() == "zip" else {
                throw FileOpError.unsupportedType
            }

            let parentURL = zipURL.deletingLastPathComponent()
            let tempURL = FileManagerClient.liveValue.temporaryDirectory().appendingPathComponent(UUID().uuidString)

            defer {
                try? FileManagerClient.liveValue.removeItem(tempURL)
            }

            try FileManagerClient.liveValue.createDirectory(tempURL, true, nil)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", zipURL.path, "-d", tempURL.path]

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw FileOpError.system(message: "Extraction failed")
            }

            let extractedItems = try FileManagerClient.liveValue.contentsOfDirectory(
                tempURL,
                nil,
                [],
            )

            if extractedItems.count == 1 {
                let item = extractedItems[0]
                var targetURL = parentURL.appendingPathComponent(item.lastPathComponent)
                var counter = 2

                while FileManagerClient.liveValue.fileExists(targetURL.path) {
                    let name = (item.lastPathComponent as NSString).deletingPathExtension
                    let ext = (item.lastPathComponent as NSString).pathExtension

                    targetURL = ext.isEmpty
                        ? parentURL.appendingPathComponent("\(name) \(counter)")
                        : parentURL.appendingPathComponent("\(name) \(counter).\(ext)")
                    counter += 1
                }

                try FileManagerClient.liveValue.moveItem(item, targetURL)
            } else {
                let baseName = zipURL.deletingPathExtension().lastPathComponent
                var folderURL = parentURL.appendingPathComponent(baseName)
                var counter = 2

                while FileManagerClient.liveValue.fileExists(folderURL.path) {
                    folderURL = parentURL.appendingPathComponent("\(baseName) \(counter)")
                    counter += 1
                }

                try FileManagerClient.liveValue.createDirectory(folderURL, false, nil)

                for item in extractedItems {
                    let target = folderURL.appendingPathComponent(item.lastPathComponent)
                    try FileManagerClient.liveValue.moveItem(item, target)
                }
            }
        }
    }

    nonisolated static var getTags: @Sendable (URL) async throws -> [String] {
        { url in
            // MDItem 기반 로드 우선 (색상 포함 데이터에서 이름 추출)
            if let tags = TagMetadataClient.loadTags(from: url), !tags.isEmpty {
                return tags.map(\.name)
            }
            // fallback: resourceValues 기반
            return (try? TagMetadataClient.loadTagNames(from: url)) ?? []
        }
    }

    nonisolated static var setTags: @Sendable (URL, [String]) async throws -> Void {
        { url, tagNames in
            @Dependency(\.finderFavoritesTagClient)
            var finderFavoritesTagClient
            do {
                let existingTags = TagMetadataClient.loadTags(from: url) ?? []
                let updatedTags = EntryFileOpsTagPersistenceResolver.makeTags(
                    tagNames: tagNames,
                    existingTags: existingTags,
                    favoriteTags: finderFavoritesTagClient.favoriteTags(),
                )
                try TagMetadataClient.setTags(updatedTags, for: url)
            } catch TagMetadataClient.Error.failedToRemoveTags {
                throw FileOpError.system(message: "Failed to remove tags")
            } catch TagMetadataClient.Error.failedToSetTags {
                throw FileOpError.system(message: "Failed to set tags")
            } catch {
                throw error
            }
        }
    }

    nonisolated static var toggleTag: @Sendable (URL, String) async throws -> Void {
        { url, tag in
            do {
                try TagMetadataClient.toggleTag(tag, for: url)
            } catch TagMetadataClient.Error.failedToRemoveTags {
                throw FileOpError.system(message: "Failed to remove tags")
            } catch TagMetadataClient.Error.failedToSetTags {
                throw FileOpError.system(message: "Failed to set tags")
            } catch {
                throw error
            }
        }
    }
}
