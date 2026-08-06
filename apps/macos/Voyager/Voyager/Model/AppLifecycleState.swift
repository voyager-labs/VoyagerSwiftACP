import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@ObservableState
struct AppLifecycleState: Equatable {
    var accountAccess: AccountAccessFeature.State = Self.makeAccountAccessState()
    var didStartHelper = false
    var didStartEntryCoreHealthProbe = false
    var didCompleteEntryCoreHealthProbe = false
    var didFinishLaunching = false
    var didCreateInitialWindow = false
    var terminationAttemptID: UUID?
    var sessionEndReason: AccountSessionEndReason?

    var isShellRuntimeReady: Bool {
        didFinishLaunching && didStartHelper && didCompleteEntryCoreHealthProbe
    }

    var isShellReady: Bool {
        isShellRuntimeReady && didCreateInitialWindow
    }

    private static func makeAccountAccessState() -> AccountAccessFeature.State {
        AccountAccessFeature.State()
    }
}
