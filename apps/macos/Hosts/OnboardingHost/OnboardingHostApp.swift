import AppKit
import Combine
import SwiftUI
import VoyagerFeaturesAccountAccess
import VoyagerPagesOnboarding

// MARK: - Deterministic smoke mode (env-toggle, host-only)

private enum SmokeMode {
    static var isEnabled: Bool {
        // TODO(VOY-432): ProcessInfo 대신 Dotenv 사용 검토 — https://linear.app/voyager-fm/issue/VOY-432
        ProcessInfo.processInfo.environment["ONBOARDING_HOST_SMOKE"] == "1"
    }

    static var resetProgress: Bool {
        ProcessInfo.processInfo.environment["ONBOARDING_HOST_RESET_PROGRESS"] != "0"
    }

    private static var expectedRequiredAfterCompleted: Bool? {
        guard let value = ProcessInfo.processInfo.environment["ONBOARDING_HOST_EXPECT_REQUIRED_AFTER_COMPLETED"] else {
            return nil
        }
        return value == "1"
    }

    /// Run smoke checks and exit. Validates contract and exits nonzero on mismatch.
    static func run() -> Never {
        let resetMode = resetProgress
        print("resetMode=\(resetMode)")

        let liveClient = OnboardingWindowClient.liveValue

        if resetMode {
            liveClient.resetStoredProgress()
        }

        let isRequiredBeforeShow = liveClient.isRequired()
        print("isRequiredBeforeShow=\(isRequiredBeforeShow)")

        let showIfNeededReturned = liveClient.showIfNeeded()
        print("showIfNeededReturned=\(showIfNeededReturned)")

        seedCompletedProgress()
        let isRequiredAfterCompletedSnapshot = liveClient.isRequired()
        print("isRequiredAfterCompletedSnapshot=\(isRequiredAfterCompletedSnapshot)")

        let (valid, failureReason) = validateContract(
            resetMode: resetMode,
            isRequiredBeforeShow: isRequiredBeforeShow,
            showIfNeededReturned: showIfNeededReturned,
            isRequiredAfterCompletedSnapshot: isRequiredAfterCompletedSnapshot,
        )

        if valid {
            print("exitReason=smoke_complete")
            exit(0)
        } else {
            print("failureReason=\(failureReason ?? "unknown")")
            print("exitReason=smoke_failed")
            exit(1)
        }
    }

    private static func validateContract(
        resetMode: Bool,
        isRequiredBeforeShow: Bool,
        showIfNeededReturned: Bool,
        isRequiredAfterCompletedSnapshot: Bool,
    ) -> (Bool, String?) {
        var failures: [String] = []

        if resetMode {
            if !isRequiredBeforeShow {
                failures.append("isRequiredBeforeShow expected true, got false")
            }
            if !showIfNeededReturned {
                failures.append("showIfNeededReturned expected true, got false")
            }
        } else {
            if isRequiredBeforeShow {
                failures.append("isRequiredBeforeShow expected false, got true")
            }
            if showIfNeededReturned {
                failures.append("showIfNeededReturned expected false, got true")
            }
        }

        let expectedAfterCompleted = expectedRequiredAfterCompleted ?? false
        if isRequiredAfterCompletedSnapshot != expectedAfterCompleted {
            failures
                .append(
                    "isRequiredAfterCompletedSnapshot expected \(expectedAfterCompleted), "
                        + "got \(isRequiredAfterCompletedSnapshot)",
                )
        }

        if failures.isEmpty {
            return (true, nil)
        } else {
            return (false, failures.joined(separator: "; "))
        }
    }

    private static func seedCompletedProgress() {
        let defaults = UserDefaults.standard
        defaults.set(1.1, forKey: "onboardingProgressVersion")
        defaults.set("complete", forKey: "onboardingCurrentStep")

        let stepState: [String: Bool] = [
            "welcomeComplete": true,
            "accessUnlockComplete": true,
            "permissionsComplete": true,
            "completeComplete": true,
        ]

        if let data = try? JSONSerialization.data(withJSONObject: stepState) {
            defaults.set(data, forKey: "onboardingStepState")
        }
    }
}

private enum OnboardingHostAuthMode: String, CaseIterable {
    case mock
    case live

    var title: String {
        switch self {
        case .mock: "Mock Account"
        case .live: "Live Account"
        }
    }

    var summary: String {
        switch self {
        case .mock: "Hardcoded active access, no network calls."
        case .live: "Real Gateway + Web auth flow."
        }
    }
}

private struct OnboardingHostAuthClients {
    let accountSessionClient: AccountSessionClient
    let authNetworkClient: AuthNetworkClient
    let signInHandoffClient: SignInHandoffClient
}

@main
struct OnboardingHostApp: App {
    @NSApplicationDelegateAdaptor(OnboardingHostAppDelegate.self)
    private var appDelegate

    init() {
        // Smoke gate runs BEFORE SwiftUI body is evaluated
        if SmokeMode.isEnabled {
            SmokeMode.run()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("Onboarding Debug") {
                Button("Show Permission Scenarios") {
                    appDelegate.showDebugPanel()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                ForEach(OnboardingPermissionDebugScenario.allCases) { scenario in
                    Button(scenario.title) {
                        appDelegate.selectDebugScenario(scenario)
                    }
                }
            }
        }
    }
}

@MainActor
final class OnboardingHostAppDelegate: NSObject, NSApplicationDelegate {
    private let sessionHolder = MockSignInState()
    private let debugStore = OnboardingHostDebugStore(initialScenario: .allGranted)
    private var debugPanel: NSPanel?

    private var onboardingWindowClient: OnboardingWindowClient!

    func applicationDidFinishLaunching(_: Notification) {
        debugStore.onSettingsChanged = { [weak self] in
            self?.reloadOnboardingWindow()
        }
        resetOnboardingProgress()
        onboardingWindowClient = makeOnboardingWindowClient()
        _ = onboardingWindowClient.showIfNeeded()
        showDebugPanel()
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        guard url.scheme == "voyager",
              url.host == "auth",
              url.path == "/callback"
        else {
            return
        }

        // 온보딩 창이 켜져 있으면 온보딩 흐름(AccountAccessFeature)으로 라우팅,
        // 아니면 unlock surface로 폴백 (메인 Voyager.app AppDelegate와 동일 패턴)
        if VoyagerPagesOnboarding.routeAuthCallbackToOnboardingIfPresent(url) {
            return
        }
        VoyagerPagesOnboarding.routeAuthCallbackToUnlockSurface(url)
    }

    private func makeOnboardingWindowClient() -> OnboardingWindowClient {
        let authClients = makeAuthClients()

        return OnboardingWindowClient.makeLive(
            openMainWindow: { _ in
                await MainActor.run {
                    NSApp.terminate(nil)
                }
                return true
            },
            accountSessionClient: authClients.accountSessionClient,
            authNetworkClient: authClients.authNetworkClient,
            signInHandoffClient: authClients.signInHandoffClient,
            permissionDebugScenario: { [debugStore] in
                debugStore.currentScenario
            },
        )
    }

    private func makeAuthClients() -> OnboardingHostAuthClients {
        switch debugStore.currentAuthMode {
        case .mock:
            OnboardingHostAuthClients(
                accountSessionClient: AccountSessionClient(
                    read: { self.sessionHolder.session },
                    persist: { _ in },
                    delete: { self.sessionHolder.setSession(nil) },
                ),
                authNetworkClient: AuthNetworkClient(
                    exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                    fetchAccessStatus: { AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                    },
                    refreshToken: { throw AccessError.notConfigured },
                ),
                signInHandoffClient: makeMockSignInHandoffClient(),
            )
        case .live:
            OnboardingHostAuthClients(
                accountSessionClient: .liveValue,
                authNetworkClient: .liveValue,
                signInHandoffClient: .liveValue,
            )
        }
    }

    private func makeMockSignInHandoffClient() -> SignInHandoffClient {
        SignInHandoffClient { [sessionHolder] in
            let mockSession = AccountSession(
                accessToken: "mock-onboarding-token",
                status: .coreLicenseActive,
            )
            sessionHolder.setSession(mockSession)
            guard let callbackURL = URL(string: "voyager://auth/callback") else {
                return .failure
            }
            return .success(callbackURL: callbackURL)
        }
    }

    func showDebugPanel() {
        if let debugPanel {
            debugPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = OnboardingHostDebugPanel(store: debugStore)
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(contentViewController: hostingController)
        panel.title = "Onboarding Debug"
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.setContentSize(NSSize(width: 360, height: 560))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        debugPanel = panel
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectDebugScenario(_ scenario: OnboardingPermissionDebugScenario) {
        debugStore.select(scenario)
        showDebugPanel()
    }

    private func resetOnboardingProgress() {
        OnboardingWindowClient.liveValue.resetStoredProgress()
    }

    private func reloadOnboardingWindow() {
        Task { @MainActor in
            await onboardingWindowClient.closeWindow()
            resetOnboardingProgress()
            onboardingWindowClient = makeOnboardingWindowClient()
            _ = onboardingWindowClient.showIfNeeded()
        }
    }
}

private final class OnboardingHostDebugStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var scenario: OnboardingPermissionDebugScenario
    @Published private(set) var authMode: OnboardingHostAuthMode

    var onSettingsChanged: (@MainActor () -> Void)?

    private let lock = NSLock()
    nonisolated(unsafe) private var lockedScenario: OnboardingPermissionDebugScenario
    nonisolated(unsafe) private var lockedAuthMode: OnboardingHostAuthMode

    init(
        initialScenario: OnboardingPermissionDebugScenario,
        initialAuthMode: OnboardingHostAuthMode = .live,
    ) {
        scenario = initialScenario
        authMode = initialAuthMode
        lockedScenario = initialScenario
        lockedAuthMode = initialAuthMode
    }

    nonisolated var currentScenario: OnboardingPermissionDebugScenario {
        lock.lock()
        defer { lock.unlock() }
        return lockedScenario
    }

    nonisolated var currentAuthMode: OnboardingHostAuthMode {
        lock.lock()
        defer { lock.unlock() }
        return lockedAuthMode
    }

    @MainActor
    func select(_ scenario: OnboardingPermissionDebugScenario) {
        lock.lock()
        lockedScenario = scenario
        lock.unlock()

        self.scenario = scenario
        onSettingsChanged?()
    }

    @MainActor
    func setAuthMode(_ mode: OnboardingHostAuthMode) {
        lock.lock()
        lockedAuthMode = mode
        lock.unlock()

        authMode = mode
        onSettingsChanged?()
    }
}

private struct OnboardingHostDebugPanel: View {
    @ObservedObject var store: OnboardingHostDebugStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permission Scenarios")
                    .font(.headline)
                Text("OnboardingHost uses mocked permission clients. Voyager.app still uses live macOS permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(OnboardingPermissionDebugScenario.allCases) { scenario in
                    Button {
                        store.select(scenario)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: store.scenario == scenario ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.scenario == scenario ? .orange : .secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scenario.title)
                                    .font(.system(.body, weight: .semibold))
                                Text(scenario.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(store.scenario == scenario ? Color.orange.opacity(0.16) : Color.secondary
                                .opacity(0.08)),
                    )
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Account Auth Mode")
                    .font(.headline)
                Text("Live calls the real Gateway/Web. Mock returns hardcoded active access without network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(OnboardingHostAuthMode.allCases, id: \.self) { mode in
                    Button {
                        store.setAuthMode(mode)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: store.authMode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.authMode == mode ? .orange : .secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.system(.body, weight: .semibold))
                                Text(mode.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(store.authMode == mode ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.08)),
                    )
                }
            }

            Text("Changing a scenario or auth mode reloads the onboarding window and replays the normal reducer path.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360)
    }
}
