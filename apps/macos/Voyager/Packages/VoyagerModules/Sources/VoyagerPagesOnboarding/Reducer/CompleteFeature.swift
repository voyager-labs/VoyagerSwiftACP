import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
struct CompleteFeature {
    typealias State = CompleteState
    typealias Action = CompleteAction

    @Dependency(\.onboardingWindowClient)
    private var onboardingWindowClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startUsingTapped, .retryTapped:
                state.isComplete = true
                state.isOpeningWindow = true
                state.openWindowError = nil
                return .run { [onboardingWindowClient] send in
                    let path = await MainActor.run {
                        SettingsDefaults.defaultTabPath()
                    }
                    let opened = await onboardingWindowClient.openMainWindow(path)
                    await send(.openWindowResponse(opened))
                }

            case let .openWindowResponse(opened):
                state.isOpeningWindow = false
                if !opened {
                    state.openWindowError = "We couldn't open a file manager window. Please try again."
                    return .none
                }

                return .run { [onboardingWindowClient] _ in
                    await onboardingWindowClient.closeWindow()
                }
            }
        }
    }
}
