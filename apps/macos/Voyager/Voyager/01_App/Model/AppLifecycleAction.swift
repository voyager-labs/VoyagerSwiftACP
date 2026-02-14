import ComposableArchitecture
import Foundation

@CasePathable
enum AppLifecycleAction: CasePathable, Sendable {
    case willFinishLaunching
    case didFinishLaunching
    case appReopen(hasVisibleWindows: Bool)
    case requestTermination
    case quitConfirmationResponse(attemptID: UUID, result: QuitConfirmationResult)
    case startTerminationCleanup(attemptID: UUID)
    case completeTerminationAttempt(attemptID: UUID, shouldTerminate: Bool)
    case willTerminate
    case delegate(Delegate)

    enum Delegate: Sendable {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
    }
}
