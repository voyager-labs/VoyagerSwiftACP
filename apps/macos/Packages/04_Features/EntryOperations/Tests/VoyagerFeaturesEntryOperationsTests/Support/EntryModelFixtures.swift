import Foundation
import VoyagerEntitiesEntry

/// Factory for creating EntryModel test fixtures.
///
/// For simple folder cases, prefer `EntryModel.temporaryFolder(id:name:)` directly.
/// Use `makeFileEntry` and `makeEntry` when you need file entries or path-based entries.
enum EntryModelFixtures {
    static func makeFileEntry(
        id: String = "/Users/test/file.txt",
        name: String = "file.txt",
        fileExtension: String = "txt",
    ) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 1024,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: fileExtension,
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    static func makeEntry(
        path: String,
        isFolder: Bool = false,
        name: String? = nil,
    ) -> EntryModel {
        let entryName = name ?? URL(fileURLWithPath: path).lastPathComponent
        return EntryModel(
            name: entryName,
            fullPath: path,
            isFolder: isFolder,
            isHidden: false,
            size: isFolder ? 0 : 512,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: isFolder ? "" : URL(fileURLWithPath: path).pathExtension,
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
