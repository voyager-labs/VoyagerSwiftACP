import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@CasePathable
enum AppLifecycleAction: CasePathable {
    case launch(Launch)
    case termination(Termination)
    case accountAccessGate(AccountAccessGate)
    case sessionLapseGuard(AccountAccessAction)
    case sessionExpiredDetected(reason: AccountSessionEndReason?)
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
        case accessStatusResponse(generation: Int, result: Result<AccessStatusResponse, AccessError>)
        case accessStatusFailed(generation: Int, error: AccessError, sessionExpiresAt: Date?)
        case deviceBindingResponse(
            generation: Int,
            snapshot: AccessStatusSnapshot,
            result: Result<DeviceBindingResponse, DeviceBindingError>,
        )
        case accessUnlockRequired(generation: Int, snapshot: AccessStatusSnapshot)
        case accountAccessGranted(generation: Int, snapshot: AccessStatusSnapshot)
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
