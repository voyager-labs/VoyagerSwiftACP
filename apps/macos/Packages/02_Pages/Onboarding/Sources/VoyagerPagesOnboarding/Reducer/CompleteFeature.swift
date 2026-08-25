import ComposableArchitecture
import Foundation

@Reducer
struct CompleteFeature {
    typealias State = CompleteState
    typealias Action = CompleteAction

    @Dependency(\.onboardingProductMetricsClient)
    var metricsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startUsingTapped, .retryTapped:
                state.completionOperationID = UUID()
                state.lastHandledCompletionOperationID = nil
                state.isComplete = true
                state.isOpeningWindow = true
                state.openWindowError = nil
                return .none

            case let .progressSaveResponse(operationID, saved):
                guard state.completionOperationID == operationID else { return .none }
                guard saved else {
                    state.completionOperationID = nil
                    state.isComplete = false
                    state.isOpeningWindow = false
                    state.openWindowError = "Failed to save onboarding progress."
                    metricsClient.record(.completion(
                        operationID: operationID,
                        result: .failure,
                    ))
                    return .none
                }
                return .none

            case let .openWindowResponse(operationID, opened):
                guard state.completionOperationID == operationID else { return .none }
                state.lastHandledCompletionOperationID = operationID
                state.completionOperationID = nil
                state.isOpeningWindow = false
                if !opened {
                    state.openWindowError = "We couldn't open a file manager window. Please try again."
                }
                metricsClient.record(.completion(
                    operationID: operationID,
                    result: opened ? .success : .failure,
                ))
                return .none
            }
        }
    }
}
