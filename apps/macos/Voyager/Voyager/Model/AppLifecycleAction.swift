import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@CasePathable
enum AppLifecycleAction: CasePathable {
    case launch(Launch)
    case termination(Termination)
    case accountAccessGate(AccountAccessGate)
    case sessionLapseGuard(AccountAccessAction)
    case sessionExpiredDetected
    case delegate(Delegate)

    @CasePathable
    enum Launch: CasePathable, Equatable {
        case willFinishLaunching
        case didFinishLaunching
        case appReopen(hasVisibleWindows: Bool)
    }

    @CasePathable
    enum AccountAccessGate: CasePathable, Equatable {
        case checkAccessStatus
        case accessStatusResponse(Result<AccessStatusResponse, AccessError>)
        case showUnlockSurface
        case accountAccessGranted(snapshot: AccessStatusSnapshot)
    }

    @CasePathable
    enum Termination: CasePathable, Equatable {
        case requestTermination
        case quitConfirmationResponse(attemptID: UUID, result: QuitConfirmationResult)
        case startTerminationCleanup(attemptID: UUID)
        case completeTerminationAttempt(attemptID: UUID, shouldTerminate: Bool)
        case willTerminate
    }

    @CasePathable
    enum Delegate: CasePathable, Equatable {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
        case startHelperIfNeeded
    }
}
