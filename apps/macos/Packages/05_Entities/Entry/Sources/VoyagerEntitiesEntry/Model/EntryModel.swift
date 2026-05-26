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

    public nonisolated init(
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
    public let isHidden: Bool
    public let size: Int64
    public let modifiedDate: Date
    public let fileExtension: String
    public let facets: EntryFacets

    public nonisolated init(
        name: String,
        fullPath: String,
        isFolder: Bool,
        isHidden: Bool,
        size: Int64,
        modifiedDate: Date,
        fileExtension: String,
        facets: EntryFacets,
    ) {
        self.name = name
        self.fullPath = fullPath
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.size = size
        self.modifiedDate = modifiedDate
        self.fileExtension = fileExtension
        self.facets = facets
    }

    public var id: String { fullPath }
}

extension EntryModel: Equatable {
    public static func == (lhs: EntryModel, rhs: EntryModel) -> Bool {
        lhs.id == rhs.id &&
            lhs.modifiedDate == rhs.modifiedDate &&
            lhs.size == rhs.size &&
            lhs.facets.tags == rhs.facets.tags
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
        )
    }
}
