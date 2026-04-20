import ComposableArchitecture
import Foundation
import VoyagerShared

@ObservableState
struct CollectionState: Equatable {
    var pendingSave: CollectionSaveSnapshot?
    var isSaving: Bool = false
}

struct CollectionSaveSnapshot: Equatable, Sendable {
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshotItems: [VoyagerShared.JSONValue]?
    let definitionFingerprint: String
    let capturedAt: Date
    let relevanceRoots: [String]
}
