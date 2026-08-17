import Foundation
import VoyagerEntitiesTag

public enum EntrySupplementaryMetadata: Equatable, Sendable {
    case folderItemCount(Int)
    case imageResolution(width: Int, height: Int)
    case compressedFileSize(Int64)
}

public struct EntryFacets: Equatable, Sendable {
    public let createdDate: Date
    public let addedDate: Date
    public let lastOpenedDate: Date?
    public let kind: String
    public let creatorApplication: String?
    public let tags: [Tag]?
    public let supplementaryMetadata: EntrySupplementaryMetadata?

    nonisolated public init(
        createdDate: Date,
        addedDate: Date,
        lastOpenedDate: Date?,
        kind: String,
        creatorApplication: String?,
        tags: [Tag]?,
        supplementaryMetadata: EntrySupplementaryMetadata?,
    ) {
        self.createdDate = createdDate
        self.addedDate = addedDate
        self.lastOpenedDate = lastOpenedDate
        self.kind = kind
        self.creatorApplication = creatorApplication
        self.tags = tags
        self.supplementaryMetadata = supplementaryMetadata
    }
}

public struct EntryModel: Identifiable, Sendable {
    public let name: String
    public let fullPath: String
    public let isFolder: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let size: Int64
    public let modifiedDate: Date
    public let fileExtension: String
    public let facets: EntryFacets

    nonisolated public init(
        name: String,
        fullPath: String,
        isFolder: Bool,
        isHidden: Bool,
        size: Int64,
        modifiedDate: Date,
        fileExtension: String,
        facets: EntryFacets,
        isPackage: Bool = false,
    ) {
        self.name = name
        self.fullPath = fullPath
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.size = size
        self.modifiedDate = modifiedDate
        self.fileExtension = fileExtension
        self.facets = facets
    }

    public var id: String {
        fullPath
    }
}

extension EntryModel: Equatable {
    public func applying(_ patch: EntryMetadataPatch) -> EntryModel {
        let updatedFacets: EntryFacets
        switch patch {
        case let .spotlight(id, kind, creatorApplication, lastOpenedDate) where id == self.id:
            updatedFacets = EntryFacets(
                createdDate: facets.createdDate,
                addedDate: facets.addedDate,
                lastOpenedDate: lastOpenedDate,
                kind: kind ?? facets.kind,
                creatorApplication: creatorApplication,
                tags: facets.tags,
                supplementaryMetadata: facets.supplementaryMetadata,
            )
        case let .tags(id, tags) where id == self.id:
            updatedFacets = EntryFacets(
                createdDate: facets.createdDate,
                addedDate: facets.addedDate,
                lastOpenedDate: facets.lastOpenedDate,
                kind: facets.kind,
                creatorApplication: facets.creatorApplication,
                tags: tags,
                supplementaryMetadata: facets.supplementaryMetadata,
            )
        case let .supplementaryMetadata(id, metadata) where id == self.id:
            updatedFacets = EntryFacets(
                createdDate: facets.createdDate,
                addedDate: facets.addedDate,
                lastOpenedDate: facets.lastOpenedDate,
                kind: facets.kind,
                creatorApplication: facets.creatorApplication,
                tags: facets.tags,
                supplementaryMetadata: metadata,
            )
        default:
            return self
        }
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            fileExtension: fileExtension,
            facets: updatedFacets,
            isPackage: isPackage,
        )
    }

    public static func temporaryFolder(id: ID, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: true,
            isHidden: false,
            size: 0,
            modifiedDate: Date(),
            fileExtension: "",
            facets: EntryFacets(
                createdDate: Date(),
                addedDate: Date(),
                lastOpenedDate: nil,
                kind: "Folder",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
            isPackage: false,
        )
    }
}
