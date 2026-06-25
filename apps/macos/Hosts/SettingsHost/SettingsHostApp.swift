import AppKit
import Combine
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerPagesSettings
import VoyagerShared

// MARK: - Deterministic smoke mode (env-toggle, host-only)

private enum SmokeMode {
    static var isEnabled: Bool {
        // TODO(VOY-432): ProcessInfo 대신 Dotenv 사용 검토 — https://linear.app/voyager-fm/issue/VOY-432
        ProcessInfo.processInfo.environment["SETTINGS_HOST_SMOKE"] == "1"
    }

    static var resetProgress: Bool {
        ProcessInfo.processInfo.environment["SETTINGS_HOST_RESET_PROGRESS"] != "0"
    }

    /// `SETTINGS_HOST_SCENARIO` 환경변수를 `SettingsHostPreset`으로 파싱.
    /// nil 또는 알 수 없는 값은 `.defaultSandbox`로 폴백하며, 폴백 시 stderr에 deterministic 경고 출력.
    static func resolvePreset() -> SettingsHostPreset {
        guard let rawValue = ProcessInfo.processInfo.environment["SETTINGS_HOST_SCENARIO"] else {
            return .defaultSandbox
        }
        guard let preset = SettingsHostPreset(rawValue: rawValue) else {
            FileHandle.standardError.write(
                Data(
                    "⚠️ Unknown SETTINGS_HOST_SCENARIO='\(rawValue)', falling back to defaultSandbox\n"
                        .utf8,
                ),
            )
            return .defaultSandbox
        }
        return preset
    }

    /// Run smoke checks and exit. Validates contract and exits nonzero on mismatch.
    static func run() -> Never {
        let resetMode = resetProgress
        let preset = resolvePreset()
        let scenario = preset.scenario

        print("smokeMode=true")
        print("resetMode=\(resetMode)")

        // 시나리오 컨트랙트 키 — T1 `preset.scenario` computed properties에서 파생 (하드코딩 금지).
        print("scenario=\(preset.id)")
        print("accountLoaded=\(scenario.accountLoaded)")
        print("sessionLapse=\(scenario.sessionLapse)")
        print("debugMenuWired=\(scenario.debugMenuWired)")

        let feature = SettingsFeature()
        var state = SettingsState()

        let initialSection = state.selectedSection.rawValue
        print("initialSection=\(initialSection)")

        feature.reduce(into: &state, action: .onAppear)
        print("onAppearDispatched=true")

        let sectionBefore = state.selectedSection.rawValue
        print("selectedSectionBefore=\(sectionBefore)")

        feature.reduce(into: &state, action: .selectSection(.appearance))
        let sectionAfter = state.selectedSection.rawValue
        print("selectedSectionAfter=\(sectionAfter)")

        feature.reduce(into: &state, action: .closeWindow)
        print("closeActionDispatched=true")

        let sectionAfterClose = state.selectedSection.rawValue
        print("selectedSectionAfterClose=\(sectionAfterClose)")

        let (valid, failureReason) = validateContract(
            initialSection: initialSection,
            sectionBefore: sectionBefore,
            sectionAfter: sectionAfter,
            sectionAfterClose: sectionAfterClose,
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
        initialSection: String,
        sectionBefore: String,
        sectionAfter: String,
        sectionAfterClose: String,
    ) -> (Bool, String?) {
        var failures: [String] = []

        if initialSection != "general" {
            failures.append("initialSection expected general, got \(initialSection)")
        }
        if sectionBefore != "general" {
            failures.append("selectedSectionBefore expected general, got \(sectionBefore)")
        }
        if sectionAfter != "appearance" {
            failures.append("selectedSectionAfter expected appearance, got \(sectionAfter)")
        }
        if sectionAfterClose != "general" {
            failures.append("selectedSectionAfterClose expected general, got \(sectionAfterClose)")
        }

        if failures.isEmpty {
            return (true, nil)
        } else {
            return (false, failures.joined(separator: "; "))
        }
    }
}

@main
struct SettingsHostApp: App {
    @NSApplicationDelegateAdaptor(SettingsHostAppDelegate.self)
    private var appDelegate

    private let store: StoreOf<SettingsHostFeature>

    init() {
        // Smoke gate runs BEFORE SwiftUI body is evaluated
        if SmokeMode.isEnabled {
            SmokeMode.run()
        }

        let hostUserDefaultsClient = Self.suiteBackedUserDefaultsClient(
            suiteName: "group.com.voyager.app.settingshost",
        )

        store = Store(initialState: SettingsHostState()) {
            SettingsHostFeature()
        } withDependencies: { dependencies in
            dependencies.userDefaultsClient = hostUserDefaultsClient
            dependencies.collectionSearchAISettingsClient = .live(userDefaultsClient: hostUserDefaultsClient)
            dependencies.launchAtLoginClient = .testValue
            dependencies.appearanceSettingsClient = .liveValue
        }
    }

    var body: some Scene {
        WindowGroup("Settings") {
            SettingsHostRootView(store: store)
        }
        .commands {
            // 호스트 전용 debug surface — OnboardingHost 패리티 스캐폴드.
            // 선택은 호스트-private store를 갱신하며, T5가 sandbox 연결을 완성한다.
            CommandMenu("Settings Debug") {
                Button("Show Scenario Panel") {
                    appDelegate.showDebugPanel()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Default Sandbox") {
                    appDelegate.selectPreset(.defaultSandbox)
                }

                Menu("Account/Auth") {
                    ForEach(SettingsHostDebugMenu.accountAuth, id: \.self) { preset in
                        Button(preset.title) {
                            appDelegate.selectPreset(preset)
                        }
                    }
                }

                Menu("AI Connection") {
                    ForEach(SettingsHostDebugMenu.aiConnection, id: \.self) { preset in
                        Button(preset.title) {
                            appDelegate.selectPreset(preset)
                        }
                    }
                }

                Menu("Permissions") {
                    ForEach(SettingsHostDebugMenu.permissions, id: \.self) { preset in
                        Button(preset.title) {
                            appDelegate.selectPreset(preset)
                        }
                    }
                }

                // Persistence 축은 독립 프리셋이 없음 (다른 프리셋 내부에 묶여 있음).
                Menu("Failure/Latency") {
                    ForEach(SettingsHostDebugMenu.failureLatency, id: \.self) { preset in
                        Button(preset.title) {
                            appDelegate.selectPreset(preset)
                        }
                    }
                }

                Divider()

                Button("Reset to Default Sandbox") {
                    appDelegate.selectPreset(.defaultSandbox)
                }
            }
        }
    }

    private static func suiteBackedUserDefaultsClient(suiteName: String) -> UserDefaultsClient {
        UserDefaultsClient(
            bool: { key in
                UserDefaults(suiteName: suiteName)?.bool(forKey: key) ?? false
            },
            setBool: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
            string: { key in
                UserDefaults(suiteName: suiteName)?.string(forKey: key)
            },
            setString: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
            double: { key in
                UserDefaults(suiteName: suiteName)?.double(forKey: key) ?? 0.0
            },
            setDouble: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
            object: { key in
                UserDefaults(suiteName: suiteName)?.object(forKey: key)
            },
            setObject: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
        )
    }
}

@MainActor
private final class SettingsHostAppDelegate: NSObject, NSApplicationDelegate {
    private let debugStore = SettingsHostDebugStore(initialPreset: .defaultSandbox)
    private var debugPanel: NSPanel?

    func applicationDidFinishLaunching(_: Notification) {
        // T5가 onPresetChanged를 sandbox 재구성으로 연결한다.
        debugStore.onPresetChanged = { [weak self] _ in
            self?.refreshDebugPanel()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func showDebugPanel() {
        if let debugPanel {
            debugPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsHostDebugPanel(store: debugStore)
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(contentViewController: hostingController)
        panel.title = "Settings Debug"
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.setContentSize(NSSize(width: 360, height: 420))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        debugPanel = panel
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectPreset(_ preset: SettingsHostPreset) {
        debugStore.select(preset)
        showDebugPanel()
    }

    private func refreshDebugPanel() {
        // 패널 콘텐츠는 @ObservedObject 바인딩으로 자동 갱신됨 — 필요시에만 보정.
        guard debugPanel != nil else { return }
        debugPanel?.contentViewController?.view.needsLayout = true
    }
}

// MARK: - Debug menu grouping (host-only)

private enum SettingsHostDebugMenu {
    static let accountAuth: [SettingsHostPreset] = [
        .signedOut,
        .signedIn,
        .authExpired,
        .accountLoading,
        .accountError,
    ]

    static let aiConnection: [SettingsHostPreset] = [
        .aiNotConfigured,
        .aiConnected,
        .aiConnectionError,
    ]

    static let permissions: [SettingsHostPreset] = [
        .permissionsAllGranted,
        .permissionsDenied,
    ]

    static let failureLatency: [SettingsHostPreset] = [
        .errorStates,
    ]
}

// MARK: - Debug store (host-only, OnboardingHost-parity)

private final class SettingsHostDebugStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var preset: SettingsHostPreset

    var onPresetChanged: (@MainActor (SettingsHostPreset) -> Void)?

    private let lock = NSLock()
    nonisolated(unsafe) private var lockedPreset: SettingsHostPreset

    init(initialPreset: SettingsHostPreset) {
        preset = initialPreset
        lockedPreset = initialPreset
    }

    nonisolated var currentPreset: SettingsHostPreset {
        lock.lock()
        defer { lock.unlock() }
        return lockedPreset
    }

    @MainActor
    func select(_ preset: SettingsHostPreset) {
        lock.lock()
        lockedPreset = preset
        lock.unlock()

        self.preset = preset
        onPresetChanged?(preset)
    }
}

// MARK: - Debug panel (host-only, OnboardingHost-parity)

private struct SettingsHostDebugPanel: View {
    @ObservedObject var store: SettingsHostDebugStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scenario Presets")
                    .font(.headline)
                Text("SettingsHost는 샌드박스된 의존성으로 SettingsView를 마운트한다. 프리셋 선택은 활성 시나리오를 갱신한다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(SettingsHostPreset.allCases, id: \.self) { preset in
                        Button {
                            store.select(preset)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: store.preset == preset ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.preset == preset ? .blue : .secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title)
                                        .font(.system(.body, weight: .semibold))
                                    Text(preset.summary)
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
                                .fill(store.preset == preset ? Color.blue.opacity(0.16) : Color.secondary
                                    .opacity(0.08)),
                        )
                    }
                }
            }

            Text("T5가 프리셋 선택 → sandbox 재구성 런타임 연결을 완성한다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360)
    }
}
