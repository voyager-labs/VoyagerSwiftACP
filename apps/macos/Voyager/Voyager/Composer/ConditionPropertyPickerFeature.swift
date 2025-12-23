import ComposableArchitecture
import Foundation

@Reducer
struct ConditionPropertyPickerFeature {
    @Dependency(\.mdItemPropertyClient)
    var mdItemPropertyClient
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var properties: [MDItemProperty] = []
        var searchText: String = ""
        var mode: Mode = .root
        var selectedCategory: String?
    }

    enum Mode: Equatable {
        case root
        case category(String)
    }

    enum PropertyError: Error, Sendable {
        case loadFailed
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case onAppear
        case searchTextChanged(String)
        case categoryTapped(String)
        case backFromCategory
        case propertyTapped(MDItemProperty)
        case loadProperties
        case propertiesResponse(Result<[MDItemProperty], PropertyError>)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented

                if !isPresented {
                    state.mode = .root
                    state.selectedCategory = nil
                    state.searchText = ""
                }
                return .none

            case .onAppear:
                if state.properties.isEmpty {
                    return .send(.loadProperties)
                }
                return .none

            case .loadProperties:
                return .run { send in
                    do {
                        let items = try await mdItemPropertyClient.fetchAll()
                        await send(.propertiesResponse(.success(items)))
                    } catch {
                        await send(.propertiesResponse(.failure(.loadFailed)))
                    }
                }

            case let .propertiesResponse(.success(items)):
                state.properties = items
                return .none

            case .propertiesResponse(.failure):
                // TODO(voy-95): 필요 시 에러 상태/토스트 추가.
                return .none

            case let .searchTextChanged(text):
                state.searchText = text
                return .none

            case let .categoryTapped(category):
                state.mode = .category(category)
                state.selectedCategory = category
                return .none

            case .backFromCategory:
                state.mode = .root
                state.selectedCategory = nil
                return .none

            case .propertyTapped:
                state.isPresented = false
                return .none
            }
        }
    }
}
