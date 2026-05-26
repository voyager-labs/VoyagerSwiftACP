import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryArrangements

@MainActor
func makeEntryArrangementsStore(
    initialState: EntryArrangementsState = EntryArrangementsState(),
    date: Date = Date(timeIntervalSince1970: 0),
) -> TestStore<EntryArrangementsFeature.State, EntryArrangementsFeature.Action> {
    TestStore(
        initialState: initialState,
    ) {
        EntryArrangementsFeature()
    } withDependencies: {
        $0.date = .constant(date)
    }
}

func makeEntry(
    _ date: Date,
    _ name: String,
    _ fullPath: String,
    _ size: Int64 = 0,
    dir: Bool = false,
    ext: String = "",
    kind: String = "",
    tags: [Tag]? = nil,
    lastOpenedDate: Date? = nil,
) -> EntryModel {
    EntryModel(
        name: name,
        fullPath: fullPath,
        isFolder: dir,
        isHidden: false,
        size: size,
        modifiedDate: date,
        fileExtension: ext,
        facets: EntryFacets(
            createdDate: date,
            addedDate: date,
            lastOpenedDate: lastOpenedDate,
            kind: kind,
            creatorApplication: nil,
            tags: tags,
            supplementaryMetadata: nil,
        ),
    )
}
