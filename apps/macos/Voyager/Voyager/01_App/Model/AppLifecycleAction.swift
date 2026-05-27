import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccess

@CasePathable
enum AppLifecycleAction: CasePathable, Equatable, Sendable {
    case launch(Launch)
    case termination(Termination)
    case accessGate(AccessGate)
    case delegate(Delegate)

    @CasePathable
    enum Launch: CasePathable, Equatable, Sendable {
        case willFinishLaunching
        case didFinishLaunching
        case appReopen(hasVisibleWindows: Bool)
    }

    @CasePathable
    enum AccessGate: CasePathable, Equatable, Sendable {
        case checkAccessStatus
        case accessStatusResponse(Result<AccessStatusResponse, AccessError>)
        case showUnlockSurface
        case accessGranted(snapshot: AccessStatusSnapshot)
    }

    @CasePathable
    enum Termination: CasePathable, Equatable, Sendable {
        case requestTermination
        case quitConfirmationResponse(attemptID: UUID, result: QuitConfirmationResult)
        case startTerminationCleanup(attemptID: UUID)
        case completeTerminationAttempt(attemptID: UUID, shouldTerminate: Bool)
        case willTerminate
    }

    @CasePathable
    enum Delegate: CasePathable, Equatable, Sendable {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
        case startHelperIfNeeded
    }
}
