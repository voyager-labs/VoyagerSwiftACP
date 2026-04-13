import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

@Reducer
struct CollectionDocumentSessionFeature {
    typealias State = CollectionDocumentSessionState
    typealias Action = CollectionDocumentSessionAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .openRequested(url):
                state.isOpening = true
                return .send(.delegate(.loadFile(url)))

            case let .openLoaded(url: url, file: file):
                state.isOpening = false
                state.openedURL = url
                state.openedName = file.name
                state.baseline = .init(context: .init(
                    query: file.query,
                    scopes: file.scopes,
                    conditions: [],
                ))
                return .none

            case .openCancelled:
                state.isOpening = false
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
