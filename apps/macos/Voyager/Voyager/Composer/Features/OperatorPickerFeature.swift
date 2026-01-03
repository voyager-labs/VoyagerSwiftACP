import ComposableArchitecture
import Foundation

struct OperatorOption: Equatable, Identifiable {
    let code: String
    let label: String
    let valueArity: Int
    let valueType: ValueType?
    let valueUIKind: ValueUIKind

    var id: String { code }
}

@Reducer
struct OperatorPickerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var options: [OperatorOption] = []
        var propertyKey: String?
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case prepare(propertyKey: String, options: [OperatorOption])
        case select(OperatorOption)
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

            case let .prepare(propertyKey, options):
                state.propertyKey = propertyKey
                state.options = options
                state.isPresented = true
                return .none

            case .select:
                state.isPresented = false
                return .none
            }
        }
    }
}
