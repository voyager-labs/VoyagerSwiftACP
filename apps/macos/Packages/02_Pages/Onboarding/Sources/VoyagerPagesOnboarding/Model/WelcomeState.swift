import ComposableArchitecture

@ObservableState
struct WelcomeState: Equatable {
    var isComplete: Bool = true
}
