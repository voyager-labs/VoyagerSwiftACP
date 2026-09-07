import ComposableArchitecture
import Foundation

@ObservableState
struct CompleteState: Equatable {
    var isComplete: Bool = false
    var isOpeningWindow: Bool = false
    var openWindowError: String?
    @ObservationStateIgnored var completionOperationID: UUID?
    @ObservationStateIgnored var lastHandledCompletionOperationID: UUID?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isComplete == rhs.isComplete
            && lhs.isOpeningWindow == rhs.isOpeningWindow
            && lhs.openWindowError == rhs.openWindowError
    }
}
