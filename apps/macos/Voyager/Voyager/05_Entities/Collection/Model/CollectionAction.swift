import ComposableArchitecture
import Foundation

@CasePathable
enum CollectionAction: CasePathable, Sendable {
    case saveRequested(SaveRequestPayload)
    case saveToExisting(SaveRequestPayload, URL)
    case savePanelResponse(URL?)
    case saveCompleted(Result<URL, Error>)
}

struct SaveRequestPayload: Equatable, Sendable {
    let context: CollectionContext?
    let isSearchLoading: Bool
    let isFiltersLoading: Bool
}
