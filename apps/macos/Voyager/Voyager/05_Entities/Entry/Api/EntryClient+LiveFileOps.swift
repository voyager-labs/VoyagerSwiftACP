import Foundation

extension EntryClient {
    nonisolated static var liveCreateFolder: @Sendable (URL, String) async throws -> Void {
        { parentURL, folderName in
            let folderURL = parentURL.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: false,
                attributes: nil,
            )
        }
    }

    nonisolated static var livePasteFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static var liveMoveFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static var liveRenameFile: @Sendable (URL, URL) async throws -> Void {
        { sourceURL, destinationURL in
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw FileOpError.fileExists(itemName: destinationURL.lastPathComponent)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    nonisolated static var liveCreateAlias: @Sendable (URL, URL) async throws -> Void {
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

    nonisolated static var liveMoveToTrash: @Sendable (URL) async throws -> Void {
        { url in
            try await MainActor.run {
                var result: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
            }
        }
    }

    nonisolated static var liveMoveToTrashAndReturnURL: @Sendable (URL) async throws -> URL {
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

    nonisolated static var liveDeleteImmediately: @Sendable (URL) async throws -> Void {
        { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static var livePutBackFromTrash: @Sendable (URL, String) async throws -> Void {
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

    nonisolated static var liveCompressItems: @Sendable ([URL]) async throws -> URL {
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

    nonisolated static var liveExtractCompressedFile: @Sendable (URL) async throws -> Void {
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

    nonisolated static var liveGetTags: @Sendable (URL) async throws -> [String] {
        { url in
            let values = try url.resourceValues(forKeys: [.tagNamesKey])
            return values.tagNames ?? []
        }
    }

    nonisolated static var liveSetTags: @Sendable (URL, [String]) async throws -> Void {
        { url, tags in
            try setFileTags(url: url, tags: tags)
        }
    }

    nonisolated static var liveToggleTag: @Sendable (URL, String) async throws -> Void {
        { url, tag in
            var currentTags = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []

            if currentTags.contains(tag) {
                currentTags.removeAll { $0 == tag }
            } else {
                currentTags.append(tag)
            }

            try setFileTags(url: url, tags: currentTags)
        }
    }
}

private nonisolated func setFileTags(url: URL, tags: [String]) throws {
    if tags.isEmpty {
        let result = removexattr(
            url.path,
            "com.apple.metadata:_kMDItemUserTags",
            XATTR_NOFOLLOW,
        )
        if result != 0, errno != ENOATTR {
            throw FileOpError.system(message: "Failed to remove tags")
        }
    } else {
        let tagData = try PropertyListSerialization.data(
            fromPropertyList: tags,
            format: .binary,
            options: 0,
        )

        let result = setxattr(
            url.path,
            "com.apple.metadata:_kMDItemUserTags",
            (tagData as NSData).bytes,
            tagData.count,
            0,
            XATTR_NOFOLLOW,
        )

        if result != 0 {
            throw FileOpError.system(message: "Failed to set tags")
        }
    }
}
