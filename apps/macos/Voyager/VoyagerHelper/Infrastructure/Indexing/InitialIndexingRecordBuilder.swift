@preconcurrency import CoreServices
import Foundation

enum InitialIndexingRecordBuilder {
    struct IdentifierPair {
        let volumeIdentifier: String
        let fileResourceIdentifier: String
    }

    struct NameComponents {
        let dirURL: URL
        let nameFull: String
        let nameStem: String
        let fileExtension: String
    }

    struct FileAttributes {
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

    struct MDItemValues {
        let size: Int64?
        let creationDate: Date?
        let modificationDate: Date?
        let addedDate: Date?
    }

    struct ResolvedDates {
        let creationDate: Date
        let modificationDate: Date
        let contentCreationDate: Date
        let contentModificationDate: Date
        let addedDate: Date
    }

    nonisolated static func makeRecord(
        mdItem: MDItem,
        path: String,
        homeURL _: URL,
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

            let record = EntryRecord(
                id: nil,
                volumeIdentifier: identifiers.volumeIdentifier,
                fileResourceIdentifier: identifiers.fileResourceIdentifier,
                path: standardizedURL.path,
                dirPath: names.dirURL.path,
                nameFull: names.nameFull,
                nameStem: names.nameStem,
                fileExtension: names.fileExtension,
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

    nonisolated static func makeDirectoryRecord(
        path: String,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
    ) async -> DirectoryRecord? {
        guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            return makeLightweightDirectoryRecord(
                path: path,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier,
            )
        }
        let dirURL = URL(fileURLWithPath: path).standardizedFileURL
        return await buildDirectoryRecordFromMDItem(
            mdItem: mdItem,
            dirURL: dirURL,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedVolumeIdentifier,
        ) ?? makeLightweightDirectoryRecord(
            path: dirURL.path,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedVolumeIdentifier,
        )
    }

    private nonisolated static func buildDirectoryRecordFromMDItem(
        mdItem: MDItem,
        dirURL: URL,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
    ) async -> DirectoryRecord? {
        do {
            guard let identifiers = try identifiers(
                for: dirURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier,
            ) else {
                return nil
            }
            let names = nameComponents(for: dirURL)
            guard let attributes = await fileAttributes(mdItem: mdItem, url: dirURL) else {
                return nil
            }
            return buildDirectoryRecord(
                identifiers: identifiers,
                names: names,
                relativeInfo: relativeInfo(path: dirURL, homeURL: homeURL),
                path: dirURL.path,
                attributes: attributes,
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func buildDirectoryRecord(
        identifiers: IdentifierPair,
        names: NameComponents,
        relativeInfo: (depth: Int, relative: String?),
        path: String,
        attributes: FileAttributes,
    ) -> DirectoryRecord {
        DirectoryRecord(
            id: nil,
            volumeIdentifier: identifiers.volumeIdentifier,
            fileResourceIdentifier: identifiers.fileResourceIdentifier,
            path: path,
            parentId: nil,
            nameFull: names.nameFull,
            nameStem: names.nameStem,
            depthFromHome: relativeInfo.depth,
            relativePathFromHome: relativeInfo.relative,
            isInvisible: attributes.isInvisible,
            creationDate: attributes.creationDate,
            modificationDate: attributes.modificationDate,
            contentCreationDate: attributes.contentCreationDate,
            contentModificationDate: attributes.contentModificationDate,
            addedDate: attributes.addedDate,
            lastUsedDate: attributes.lastUsedDate,
            originalMetadata: attributes.originalMetadata,
        )
    }
}
