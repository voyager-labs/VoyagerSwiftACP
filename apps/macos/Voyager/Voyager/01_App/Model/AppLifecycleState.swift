import ComposableArchitecture
import Foundation
import VoyagerFeaturesLicenseAuth

@ObservableState
struct AppLifecycleState: Equatable {
    var didStartHelper = false
    var terminationAttemptID: UUID?
    var isCheckingLicenseAuth = false
    var lastLicenseAuthStatus: LicenseAuthStatus?
    var licenseAuthGateResolved = false
}
