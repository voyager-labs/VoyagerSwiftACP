import ComposableArchitecture
import Foundation

@CasePathable
enum AppLifecycleAction: CasePathable {
    case launch(Launch)
    case termination(Termination)
    case delegate(Delegate)

    @CasePathable
    enum Launch: CasePathable {
        case willFinishLaunching
        case didFinishLaunching
        case appReopen(hasVisibleWindows: Bool)
    }

    @CasePathable
    enum Termination: CasePathable {
        case requestTermination
        case quitConfirmationResponse(attemptID: UUID, result: QuitConfirmationResult)
        case startTerminationCleanup(attemptID: UUID)
        case completeTerminationAttempt(attemptID: UUID, shouldTerminate: Bool)
        case willTerminate
    }

    enum Delegate {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
    }
}
