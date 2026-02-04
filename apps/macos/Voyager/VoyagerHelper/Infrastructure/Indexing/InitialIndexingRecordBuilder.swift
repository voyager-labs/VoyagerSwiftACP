@preconcurrency import CoreServices
import Foundation

enum InitialIndexingRecordBuilder {
    private struct IdentifierPair {
        let volumeIdentifier: String
        let fileResourceIdentifier: String
    }

    private struct NameComponents {
        let dirURL: URL
        let nameFull: String
        let nameStem: String
        let fileExtension: String
    }

    private struct FileAttributes {
        let size: Int64
        let creationDate: Date
        let modificationDate: Date
        let contentCreationDate: Date
        let contentModificationDate: Date
        let addedDate: Date
        let uniformTypeIdentifier: String?
        let fileKind: String?
        let isInvisible: Bool
        let lastUsedDate: Date?
        let originalMetadata: String
    }

    private struct MDItemValues {
        let size: Int64?
        let creationDate: Date?
        let modificationDate: Date?
        let addedDate: Date?
    }

    private struct ResolvedDates {
        let creationDate: Date
        let modificationDate: Date
        let contentCreationDate: Date
        let contentModificationDate: Date
        let addedDate: Date
    }

    nonisolated static func makeRecord(
        mdItem: MDItem,
        path: String,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
    ) async -> EntryRecord? {
        let fileURL = URL(fileURLWithPath: path)
        let standardizedURL = fileURL.standardizedFileURL

        do {
            guard let identifiers = try identifiers(
                for: standardizedURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier,
            ) else {
                return nil
            }
            let names = nameComponents(for: standardizedURL)
            guard let attributes = await fileAttributes(mdItem: mdItem, url: standardizedURL) else {
                return nil
            }

            let relativeInfo = relativeInfo(path: standardizedURL, homeURL: homeURL)
            let record = EntryRecord(
                id: nil,
                volumeIdentifier: identifiers.volumeIdentifier,
                fileResourceIdentifier: identifiers.fileResourceIdentifier,
                path: standardizedURL.path,
                dirPath: names.dirURL.path,
                nameFull: names.nameFull,
                nameStem: names.nameStem,
                fileExtension: names.fileExtension,
                parentDirName: names.dirURL.lastPathComponent,
                depthFromHome: relativeInfo.depth,
                relativePathFromHome: relativeInfo.relative,
                size: attributes.size,
                uniformTypeIdentifier: attributes.uniformTypeIdentifier,
                fileKind: attributes.fileKind,
                isInvisible: attributes.isInvisible,
                creationDate: attributes.creationDate,
                modificationDate: attributes.modificationDate,
                contentCreationDate: attributes.contentCreationDate,
                contentModificationDate: attributes.contentModificationDate,
                addedDate: attributes.addedDate,
                lastUsedDate: attributes.lastUsedDate,
                originalMetadata: attributes.originalMetadata,
                directoryId: nil,
            )
            return record
        } catch {
            return nil
        }
    }

    private nonisolated static func identifiers(
        for url: URL,
        cachedVolumeIdentifier: String?,
    ) throws -> IdentifierPair? {
        let identifierKeys: Set<URLResourceKey> = cachedVolumeIdentifier == nil
            ? [.volumeIdentifierKey, .fileResourceIdentifierKey]
            : [.fileResourceIdentifierKey]
        let values = try url.resourceValues(forKeys: identifierKeys)
        guard let fileResourceIdentifier = identifierString(values.fileResourceIdentifier) else { return nil }
        let volumeIdentifier = cachedVolumeIdentifier ?? identifierString(values.volumeIdentifier)
        guard let volumeIdentifier else { return nil }
        return IdentifierPair(
            volumeIdentifier: volumeIdentifier,
            fileResourceIdentifier: fileResourceIdentifier,
        )
    }

    private nonisolated static func nameComponents(for url: URL) -> NameComponents {
        let dirURL = url.deletingLastPathComponent()
        return NameComponents(
            dirURL: dirURL,
            nameFull: url.lastPathComponent,
            nameStem: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
        )
    }

    private nonisolated static func fileAttributes(mdItem: MDItem, url: URL) async -> FileAttributes? {
        let attributes = MetadataJSONEncoder.attributes(from: mdItem)
        let mdItemValues = mdItemValues(from: attributes)
        let fallbackValues = fallbackValuesIfNeeded(url: url, values: mdItemValues)
        guard let resolvedDates = resolvedDates(
            values: mdItemValues,
            fallbackValues: fallbackValues,
            attributes: attributes,
        ) else {
            return nil
        }

        let size = resolvedSize(values: mdItemValues, fallbackValues: fallbackValues)
        let uniformTypeIdentifier = stringValue(attributeValue(attributes, key: kMDItemContentType))
        let fileKind = stringValue(attributeValue(attributes, key: kMDItemKind))
        let isInvisible = boolValue(attributeValue(attributes, key: kMDItemFSInvisible))
        let lastUsedDate = dateValue(attributeValue(attributes, key: kMDItemLastUsedDate))
        let originalMetadata = await MetadataJSONEncoder.encode(
            attributes: attributes,
            path: url.path,
        ) ?? "{}"

        return FileAttributes(
            size: size,
            creationDate: resolvedDates.creationDate,
            modificationDate: resolvedDates.modificationDate,
            contentCreationDate: resolvedDates.contentCreationDate,
            contentModificationDate: resolvedDates.contentModificationDate,
            addedDate: resolvedDates.addedDate,
            uniformTypeIdentifier: uniformTypeIdentifier,
            fileKind: fileKind,
            isInvisible: isInvisible,
            lastUsedDate: lastUsedDate,
            originalMetadata: originalMetadata,
        )
    }

    private nonisolated static func mdItemValues(from attributes: NSDictionary) -> MDItemValues {
        MDItemValues(
            size: int64Value(attributeValue(attributes, key: kMDItemFSSize)),
            creationDate: dateValue(attributeValue(attributes, key: kMDItemFSCreationDate)),
            modificationDate: dateValue(attributeValue(attributes, key: kMDItemFSContentChangeDate)),
            addedDate: dateValue(attributeValue(attributes, key: kMDItemDateAdded)),
        )
    }

    private nonisolated static func fallbackValuesIfNeeded(
        url: URL,
        values: MDItemValues,
    ) -> URLResourceValues? {
        let needsFallback = values.size == nil
            || values.creationDate == nil
            || values.modificationDate == nil
            || values.addedDate == nil
        guard needsFallback else { return nil }
        return try? url.resourceValues(
            forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .addedToDirectoryDateKey],
        )
    }

    private nonisolated static func resolvedSize(
        values: MDItemValues,
        fallbackValues: URLResourceValues?,
    ) -> Int64 {
        values.size
            ?? fallbackValues?.fileSize.map(Int64.init)
            ?? 0
    }

    private nonisolated static func resolvedDates(
        values: MDItemValues,
        fallbackValues: URLResourceValues?,
        attributes: NSDictionary,
    ) -> ResolvedDates? {
        guard let creationDate = values.creationDate ?? fallbackValues?.creationDate else {
            return nil
        }
        guard let modificationDate = values.modificationDate ?? fallbackValues?.contentModificationDate else {
            return nil
        }

        let contentCreationDate = dateValue(attributeValue(attributes, key: kMDItemContentCreationDate))
            ?? creationDate
        let contentModificationDate = dateValue(attributeValue(attributes, key: kMDItemContentModificationDate))
            ?? modificationDate
        let addedDate = values.addedDate
            ?? fallbackValues?.addedToDirectoryDate
            ?? creationDate

        return ResolvedDates(
            creationDate: creationDate,
            modificationDate: modificationDate,
            contentCreationDate: contentCreationDate,
            contentModificationDate: contentModificationDate,
            addedDate: addedDate,
        )
    }

    private nonisolated static func attributeValue(_ attributes: NSDictionary, key: CFString) -> Any? {
        attributes[key as String]
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private nonisolated static func int64Value(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private nonisolated static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private nonisolated static func dateValue(_ value: Any?) -> Date? {
        value as? Date
    }

    private nonisolated static func identifierString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        if let uuid = value as? UUID {
            return uuid.uuidString
        }
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    nonisolated static func volumeIdentifier(from url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
        return identifierString(values?.volumeIdentifier)
    }

    private nonisolated static func relativeInfo(path: URL, homeURL: URL) -> (depth: Int, relative: String?) {
        let homePath = homeURL.standardizedFileURL.path
        let targetPath = path.standardizedFileURL.path
        guard targetPath == homePath || targetPath.hasPrefix(homePath + "/") else {
            return (-1, nil)
        }
        let relative = targetPath.dropFirst(homePath.count).trimmingCharacters(
            in: CharacterSet(charactersIn: "/"),
        )
        guard !relative.isEmpty else { return (-1, "~/") }
        let depth = max(-1, relative.split(separator: "/").count - 1)
        return (depth, "~/" + relative)
    }
}
