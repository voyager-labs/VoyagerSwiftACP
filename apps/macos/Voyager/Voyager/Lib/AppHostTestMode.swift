import Foundation

/// Selects how the real Voyager application host behaves while XCTest is attached.
/// Production launches return `nil`; application-hosted tests default to `.isolated`.
enum AppHostTestMode: String, Equatable {
    case isolated
    case lifecycleIntegration = "lifecycle-integration"

    static let environmentKey = "VOYAGER_APP_HOST_TEST_MODE"

    static var current: Self? {
        resolve(
            xctestConfigurationPath: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"],
            requestedMode: ProcessInfo.processInfo.environment["VOYAGER_APP_HOST_TEST_MODE"],
        )
    }

    var suppressesAutomaticLifecycle: Bool {
        self == .isolated
    }

    static func resolve(environment: [String: String]) -> Self? {
        resolve(
            xctestConfigurationPath: environment["XCTestConfigurationFilePath"],
            requestedMode: environment[environmentKey],
        )
    }

    private static func resolve(
        xctestConfigurationPath: String?,
        requestedMode: String?,
    ) -> Self? {
        guard xctestConfigurationPath != nil else { return nil }
        guard requestedMode == lifecycleIntegration.rawValue else {
            return .isolated
        }
        return .lifecycleIntegration
    }
}

enum AppHostLifecycleIntegrationEvent: Hashable {
    case willFinishLaunching
    case didFinishLaunching
    case helperStarted
    case entryCoreHealthChecked
    case initialWindowOpened
    case terminationRequested
    case terminationReply(Bool)
}

@MainActor
final class AppHostLifecycleIntegrationProbe {
    static let shared = AppHostLifecycleIntegrationProbe()

    private(set) var events: [AppHostLifecycleIntegrationEvent] = []
    private(set) weak var appDelegate: AppDelegate?

    private init() {}

    func record(_ event: AppHostLifecycleIntegrationEvent) {
        guard AppHostTestMode.current == .lifecycleIntegration else { return }
        events.append(event)
    }

    func register(appDelegate: AppDelegate) {
        guard AppHostTestMode.current == .lifecycleIntegration else { return }
        self.appDelegate = appDelegate
    }
}
