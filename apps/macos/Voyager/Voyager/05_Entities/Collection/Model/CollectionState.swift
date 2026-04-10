import ComposableArchitecture
import Foundation

@ObservableState
struct CollectionState: Equatable {
    var pendingSave: CollectionSaveSnapshot?
    var isSaving: Bool = false
}

struct CollectionSaveSnapshot: Equatable, Sendable {
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
}
