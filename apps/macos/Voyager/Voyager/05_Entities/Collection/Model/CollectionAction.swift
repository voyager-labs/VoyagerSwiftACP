import ComposableArchitecture
import Foundation
import VoyagerShared

@CasePathable
enum CollectionAction: CasePathable, Sendable {
    case saveRequested(SaveRequestPayload)
    case saveToExisting(SaveRequestPayload, URL)
    case savePanelResponse(URL?)
    case saveCompleted(Result<CollectionSaveCompletion, Error>)
}

struct SaveRequestPayload: Equatable, Sendable {
    let context: CollectionContext?
    let isSearchLoading: Bool
    let isFiltersLoading: Bool
    let snapshotItems: [JSONValue]?
    let definitionFingerprint: String
    let capturedAt: Date
    let relevanceRoots: [String]
}

struct CollectionSaveCompletion: Equatable, Sendable {
    let url: URL
    let file: VoyagerCollectionFile
}
