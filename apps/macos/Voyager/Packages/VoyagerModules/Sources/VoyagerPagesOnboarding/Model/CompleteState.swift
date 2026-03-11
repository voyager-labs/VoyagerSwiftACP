import ComposableArchitecture

@ObservableState
struct CompleteState: Equatable, Sendable {
    var isComplete: Bool = false
    var isOpeningWindow: Bool = false
    var openWindowError: String?
}
