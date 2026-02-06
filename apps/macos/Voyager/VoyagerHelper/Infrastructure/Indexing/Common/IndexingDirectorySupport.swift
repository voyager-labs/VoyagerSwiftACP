import Foundation

extension IndexingRecordBuilder {
    nonisolated static func makeLightweightDirectoryRecord(
        path: String,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
    ) -> DirectoryRecord? {
        let dirURL = URL(fileURLWithPath: path).standardizedFileURL
        do {
            guard let identifiers = try identifiers(
                for: dirURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier,
            ) else {
                return nil
            }
            let names = nameComponents(for: dirURL)
            let relativeInfo = relativeInfo(path: dirURL, homeURL: homeURL)
            let isInvisible: Bool? = if let hidden = try? dirURL.resourceValues(forKeys: [.isHiddenKey]).isHidden {
                hidden
            } else {
                nil
            }
            return DirectoryRecord(
                id: nil,
                volumeIdentifier: identifiers.volumeIdentifier,
                fileResourceIdentifier: identifiers.fileResourceIdentifier,
                path: dirURL.path,
                parentId: nil,
                nameFull: names.nameFull,
                nameStem: names.nameStem,
                depthFromHome: relativeInfo.depth,
                relativePathFromHome: relativeInfo.relative,
                isInvisible: isInvisible,
                creationDate: nil,
                modificationDate: nil,
                contentCreationDate: nil,
                contentModificationDate: nil,
                addedDate: nil,
                lastUsedDate: nil,
                originalMetadata: "{}",
            )
        } catch {
            return nil
        }
    }

    nonisolated static func isDirectory(mdItem: MDItem, path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }

        let attributes = MetadataJSONEncoder.attributes(from: mdItem)
        if let contentType = attributes[kMDItemContentType as String] as? String,
           contentType == "public.folder"
        {
            return true
        }
        if let contentTypeTree = attributes[kMDItemContentTypeTree as String] as? [String],
           contentTypeTree.contains("public.folder")
        {
            return true
        }
        if let fileKind = attributes[kMDItemKind as String] as? String {
            let lowered = fileKind.lowercased()
            if lowered.contains("folder") || lowered.contains("directory") {
                return true
            }
        }
        return false
    }
}
