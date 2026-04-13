import ComposableArchitecture
import Foundation
import VoyagerShared

public struct CollectionState: Equatable, Sendable {
    public var pendingSave: CollectionSaveSnapshot?
    public var isSaving: Bool = false

    public init(
        pendingSave: CollectionSaveSnapshot? = nil,
        isSaving: Bool = false,
    ) {
        self.pendingSave = pendingSave
        self.isSaving = isSaving
    }
}

@CasePathable
public enum CollectionAction: CasePathable, Sendable {
    case saveRequested(SaveRequestPayload)
    case saveToExisting(SaveRequestPayload, URL)
    case savePanelResponse(URL?)
    case saveCompleted(Result<URL, Error>)
}

public struct CollectionSaveSnapshot: Equatable, Sendable {
    public let query: String
    public let scopes: [String]
    public let conditions: [Condition]

    public init(query: String, scopes: [String], conditions: [Condition]) {
        self.query = query
        self.scopes = scopes
        self.conditions = conditions
    }
}

public struct SaveRequestPayload: Equatable, Sendable {
    public let context: CollectionContext?
    public let isSearchLoading: Bool
    public let isFiltersLoading: Bool

    public init(context: CollectionContext?, isSearchLoading: Bool, isFiltersLoading: Bool) {
        self.context = context
        self.isSearchLoading = isSearchLoading
        self.isFiltersLoading = isFiltersLoading
    }
}
