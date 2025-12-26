import ComposableArchitecture
import Foundation

enum ValueType: String, Sendable, Equatable {
    case string
    case number
    case date
    case boolean
    case array
    case unknown
}

@Reducer
struct ValuePickerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var propertyKey: String?
        var operatorOption: OperatorOption?
        var valueType: ValueType = .string
        var valueArity: Int = 1
        var values: [String] = [""]
        var errorMessage: String?
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case prepare(propertyKey: String, operatorOption: OperatorOption, valueType: ValueType)
        case setValue(index: Int, text: String)
        case commit
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    state.propertyKey = nil
                    state.operatorOption = nil
                    state.values = [""]
                    state.errorMessage = nil
                }
                return .none

            case let .prepare(propertyKey, operatorOption, valueType):
                state.propertyKey = propertyKey
                state.operatorOption = operatorOption
                state.valueType = valueType
                state.valueArity = max(0, operatorOption.valueArity)
                state.errorMessage = nil

                if state.valueArity == 0 {
                    state.values = []
                } else if state.valueArity == 1 {
                    state.values = [state.values.first ?? ""]
                } else {
                    // arity 2 이상은 최소 2칸 확보
                    state.values = Array(repeating: "", count: state.valueArity)
                }

                state.isPresented = true
                return .none

            case let .setValue(index, text):
                // 값 배열이 비어있을 수 있으므로 아리티에 맞춰 길이 보정
                if state.values.count < max(state.valueArity, 1) {
                    state.values = Array(
                        repeating: "",
                        count: max(state.valueArity, 1),
                    )
                }
                guard state.values.indices.contains(index) else { return .none }
                state.values[index] = text
                return .none

            case .commit:
                return .none
            }
        }
    }
}
