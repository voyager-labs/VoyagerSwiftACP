import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@CasePathable
enum AppLifecycleAction: CasePathable {
    case launch(Launch)
    case termination(Termination)
    case accountAccess(AccountAccessAction)
    case sessionExpiredDetected(reason: AccountSessionEndReason?)
    case entryCoreHealthProbeCompleted(EntryCoreHealthProbeResult)
    case delegate(Delegate)

    @CasePathable
    enum Launch: CasePathable, Equatable {
        case willFinishLaunching
        case didFinishLaunching
        case appReopen(hasVisibleWindows: Bool)
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

nonisolated struct EntryCoreHealthProbeResult: Equatable {
    nonisolated enum Outcome: String, Equatable {
        case healthy
        case unavailable
        case failed
    }

    nonisolated enum Phase: String, Equatable {
        case endpointResolution
        case connect
        case write
        case read
        case response
    }

    let outcome: Outcome
    let phase: Phase
    let duration: Duration
}
