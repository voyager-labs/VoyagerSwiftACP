import ComposableArchitecture
import Foundation
import VoyagerFeaturesLicenseAuth

@CasePathable
enum AppLifecycleAction: CasePathable, Equatable, Sendable {
    case launch(Launch)
    case termination(Termination)
    case licenseAuthGate(LicenseAuthGate)
    case delegate(Delegate)

    @CasePathable
    enum Launch: CasePathable, Equatable, Sendable {
        case willFinishLaunching
        case didFinishLaunching
        case appReopen(hasVisibleWindows: Bool)
    }

    @CasePathable
    enum LicenseAuthGate: CasePathable, Equatable, Sendable {
        case checkAccessStatus
        case licenseAuthStatusResponse(Result<LicenseAuthStatusResponse, LicenseAuthError>)
        case showUnlockSurface
        case licenseAuthGranted(snapshot: LicenseAuthStatusSnapshot)
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
