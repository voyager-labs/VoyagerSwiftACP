import ComposableArchitecture

@ObservableState
struct CompleteState: Equatable {
    var isComplete: Bool = false
    var isOpeningWindow: Bool = false
    var openWindowError: String?
}
