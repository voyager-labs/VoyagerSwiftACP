import AppKit
import Foundation

enum EntryFileOpsLive {
    nonisolated static var createFolder: @Sendable (URL, String) async throws -> Void {
        { parentURL, folderName in
            let folderURL = parentURL.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: false,
                attributes: nil,
            )
        }
    }

    nonisolated static var pasteFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static var moveFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static var renameFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static var createAlias: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, aliasURL in
            if FileManager.default.fileExists(atPath: aliasURL.path) {
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
                var result: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                guard let trashURL = result as URL? else {
                    throw FileOpError.system(message: "Trash URL not found")
                }
                return trashURL
            }
        }
    }

    nonisolated static var deleteImmediately: @Sendable (URL) async throws -> Void {
        { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static var putBackFromTrash: @Sendable (URL, String) async throws -> Void {
        { trashURL, originalPath in
            let originalURL = URL(fileURLWithPath: originalPath)

            let parentURL = originalURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentURL.path) {
                try FileManager.default.createDirectory(
                    at: parentURL,
                    withIntermediateDirectories: true,
                )
            }

            if FileManager.default.fileExists(atPath: originalURL.path) {
                throw FileOpError.fileExists(itemName: originalURL.lastPathComponent)
            }

            try FileManager.default.moveItem(at: trashURL, to: originalURL)

            await TrashMetadataStore.shared.remove(trashPath: trashURL.path)
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
        }
    }

    nonisolated static var extractCompressedFile: @Sendable (URL) async throws -> Void {
        { zipURL in
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
                includingPropertiesForKeys: nil,
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
        }
    }

    nonisolated static var getTags: @Sendable (URL) async throws -> [String] {
        { url in
            try TagMetadataClient.loadTagNames(from: url)
        }
    }

    nonisolated static var setTags: @Sendable (URL, [String]) async throws -> Void {
        { url, tags in
            do {
                try TagMetadataClient.setTagNames(tags, for: url)
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

    nonisolated static var fileExists: @Sendable (String) -> Bool {
        { path in
            FileManager.default.fileExists(atPath: path)
        }
    }

    nonisolated static var saveDragPaths: @Sendable ([String]) -> Void {
        { paths in
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            pasteboard.clearContents()
            let pathString = paths.joined(separator: "\n")
            pasteboard.setString(pathString, forType: .string)
        }
    }

    nonisolated static var loadDragPaths: @Sendable () -> [String] {
        {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            guard let pathString = pasteboard.string(forType: .string),
                  !pathString.isEmpty
            else {
                return []
            }
            return pathString.split(separator: "\n").map(String.init)
        }
    }

    nonisolated static var saveDragWithOption: @Sendable (Bool) -> Void {
        { isOptionPressed in
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            pasteboard.setString(
                isOptionPressed ? "true" : "false",
                forType: NSPasteboard.PasteboardType("VoyagerDragOption"),
            )
        }
    }

    nonisolated static var loadDragWithOption: @Sendable () -> Bool {
        {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            let optionString = pasteboard.string(forType: NSPasteboard.PasteboardType("VoyagerDragOption"))
            return optionString == "true"
        }
    }

    nonisolated static var loadClipboardPaths: @Sendable () -> ([String], ClipboardOperation) {
        {
            let pasteboard = NSPasteboard.general

            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
                return ([], .copy)
            }

            let paths = urls.map(\.path)

            let opString = pasteboard
                .string(forType: NSPasteboard.PasteboardType("com.voyager.clipboard.operation"))
            let operation: ClipboardOperation = opString == "cut" ? .cut : .copy

            return (paths, operation)
        }
    }

    nonisolated static var postFileSystemChanged: @Sendable ([String]) -> Void {
        { paths in
            NotificationCenter.default.post(
                name: EntryWatchingLive.fileSystemChangedNotificationName,
                object: nil,
                userInfo: ["paths": paths],
            )
        }
    }
}
