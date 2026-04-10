import ComposableArchitecture
import Foundation

@Reducer
struct OperatorPickerFeature {
    typealias State = OperatorPickerState
    typealias Action = OperatorPickerAction

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
                if !optionLabels.isEmpty {
                    state.optionLabels = optionLabels
                }
                state.isPresented = true
                return .none

            case .select:
                state.isPresented = false
                return .none
            }
        }
    }
}
