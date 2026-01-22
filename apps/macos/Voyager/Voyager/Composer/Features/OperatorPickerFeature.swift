import ComposableArchitecture
import Foundation

@Reducer
struct OperatorPickerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var options: [String] = []
        var optionLabels: [String: String] = [:]
        var propertyKey: String?
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case prepare(propertyKey: String, options: [String], optionLabels: [String: String])
        case select(String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    state.propertyKey = nil
                }
                return .none

            case let .prepare(propertyKey, options, optionLabels):
                state.propertyKey = propertyKey
                state.options = options
                state.optionLabels = optionLabels
                state.isPresented = true
                return .none

            case .select:
                state.isPresented = false
                return .none
            }
        }
    }
}
