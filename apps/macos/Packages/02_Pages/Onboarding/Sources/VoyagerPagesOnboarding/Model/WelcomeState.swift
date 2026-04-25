import ComposableArchitecture

@ObservableState
struct WelcomeState: Equatable, Sendable {
    var isComplete: Bool = true
}
