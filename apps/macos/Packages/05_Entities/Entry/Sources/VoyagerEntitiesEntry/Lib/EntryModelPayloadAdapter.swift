import VoyagerEntitiesTag
import VoyagerShared

enum EntryModelPayloadAdapter {
    nonisolated static func makeEntry(_ payload: SearchEntryPayload) -> EntryModel {
        EntryModel(
            name: payload.name,
            fullPath: payload.fullPath,
            isFolder: payload.isFolder,
            isHidden: payload.isHidden,
            size: payload.size,
            modifiedDate: payload.modifiedDate,
            fileExtension: payload.fileExtension,
            facets: EntryFacets(
                createdDate: payload.createdDate,
                addedDate: payload.addedDate,
                lastOpenedDate: payload.lastOpenedDate,
                kind: payload.kind,
                creatorApplication: payload.creatorApplication,
                tags: payload.tags?.map { Tag(name: $0.name, colorCode: $0.colorCode) },
                supplementaryMetadata: makeSupplementaryMetadata(payload.supplementaryMetadata),
            ),
            isPackage: payload.isPackage,
        )
    }

    nonisolated private static func makeSupplementaryMetadata(
        _ payload: SearchEntrySupplementaryMetadataPayload?,
    ) -> EntrySupplementaryMetadata? {
        guard let payload else {
            return nil
        }

        switch payload {
        case let .folderItemCount(itemCount):
            return .folderItemCount(itemCount)
        case let .imageResolution(width, height):
            return .imageResolution(width: width, height: height)
        case let .compressedFileSize(fileSize):
            return .compressedFileSize(fileSize)
        }
    }
}
