import ComposableArchitecture
import Foundation
import Sentry
import SwiftDotenv

@Reducer
struct AppLifecycleFeature {
    private enum CancelID {
        static let helperMonitor = "helperMonitor"
    }

    @ObservableState
    struct State: Equatable {
        var didStartHelper = false
    }

    enum Action: Sendable {
        case willFinishLaunching
        case didFinishLaunching
        case willTerminate
    }

    @Dependency(\.helperAppClient)
    var helperAppClient
    @Dependency(\.helperStateClient)
    var helperStateClient

    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .willFinishLaunching:
                try? EnvironmentLoader.loadEnvFiles()
                startSentryIfNeeded()

                if state.didStartHelper {
                    return .none
                }
                state.didStartHelper = true
                let helperClient = helperAppClient
                let stateClient = helperStateClient
                return .run { _ in
                    // Helper 상태 요청 및 fallback 처리
                    @Sendable
                    func requestHelperState() async {
                        let state = await stateClient.resolve()
                        if state != nil {
                            return
                        }

                        let isRunning = await helperClient.isRunning()
                        if !isRunning {
                            await helperClient.start()
                            _ = await stateClient.resolve()
                        }
                    }

                    async let monitor: Void = {
                        for await _ in helperClient.terminationEvents() {
                            await helperClient.start()
                            await requestHelperState()
                        }
                    }()

                    await helperClient.start()
                    await requestHelperState()
                    _ = await monitor
                }
                .cancellable(id: CancelID.helperMonitor, cancelInFlight: true)
            case .didFinishLaunching:
                return .run { [onboardingWindowClient] _ in
                    _ = onboardingWindowClient.showIfNeeded()
                }
            case .willTerminate:
                let helperClient = helperAppClient
                return .merge(
                    .run { _ in
                        await helperClient.stop()
                    },
                    .cancel(id: CancelID.helperMonitor),
                )
            }
        }
    }
}

private func startSentryIfNeeded() {
    guard let dsn = Dotenv["SENTRY_DSN"]?.stringValue, !dsn.isEmpty else {
        return
    }
    let tracesSampleRate = Double(Dotenv["SENTRY_TRACES_SAMPLE_RATE"]?.stringValue ?? "") ?? 0.05
    SentrySDK.start { options in
        options.dsn = dsn
        options.sendDefaultPii = false
        options.tracesSampleRate = NSNumber(value: tracesSampleRate)
        options.enableLogs = true
    }
    if let deviceId = DeviceIdentifierProvider.current() {
        let appVersion = AppVersionInfo.shortVersion
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        SentrySDK.configureScope { scope in
            scope.setUser(Sentry.User(userId: deviceId))
            scope.setTag(value: appVersion, key: "app_version")
            scope.setTag(value: osVersion, key: "os_version")
        }
    }
}
