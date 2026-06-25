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
        let liveDependencies = SettingsHostAuthMode.current == .live

        print("smokeMode=true")
        print("resetMode=\(resetMode)")

        // 시나리오 컨트랙트 키 — T1 `preset.scenario` computed properties에서 파생 (하드코딩 금지).
        print("scenario=\(preset.id)")
        print("accountLoaded=\(scenario.accountLoaded)")
        print("sessionLapse=\(scenario.sessionLapse)")
        print("debugMenuWired=\(scenario.debugMenuWired)")
        // T5 라이브 opt-in 플래그 — 기본 `.mock`(sandbox). `.live`는 명시적 env opt-in 필요.
        // smoke는 Store/의존성 생성 이전에 exit하므로 사이드 이펙트 없이 플래그만 보고한다.
        print("liveDependencies=\(liveDependencies)")

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

// MARK: - Live/mock auth mode (host-only, opt-in live)

private enum SettingsHostAuthMode: String {
    case mock
    case live

    /// 기본은 `.mock`(sandbox 의존성). `.live`는 `SETTINGS_HOST_AUTH_MODE=live` 명시적 opt-in 필요.
    static var current: SettingsHostAuthMode {
        let rawValue = ProcessInfo.processInfo.environment["SETTINGS_HOST_AUTH_MODE"]?.lowercased()
        return rawValue.flatMap(SettingsHostAuthMode.init(rawValue:)) ?? .mock
    }
}

@main
struct SettingsHostApp: App {
    @NSApplicationDelegateAdaptor(SettingsHostAppDelegate.self)
    private var appDelegate

    init() {
        // Smoke gate runs BEFORE SwiftUI body is evaluated
        if SmokeMode.isEnabled {
            SmokeMode.run()
        }
    }

    var body: some Scene {
        WindowGroup("Settings") {
            SettingsHostWindowContent(container: appDelegate.storeContainer)
        }
        .commands {
            // 호스트 전용 debug surface — OnboardingHost 패리티.
            // 선택은 SettingsHostStoreContainer.select를 통해 Store를 새 시나리오 의존성으로 재생성한다.
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
}

// MARK: - Runtime store container (host-only)

// TCA Store를 시나리오 변경 시 재생성 가능하게 보관하는 ObservableObject.
// OnboardingHost는 WindowClient 클로저로 call-time 시나리오를 읽지만, SettingsHost는
// TCA Store를 쓰므로 "select 시 Store 재생성(Option A)"으로 동일한 call-time 의존성 갱신을 달성한다.

@MainActor
private final class SettingsHostStoreContainer: ObservableObject {
    @Published private(set) var store: StoreOf<SettingsHostFeature>
    @Published private(set) var scenarioID: String

    let debugStore: SettingsHostDebugStore
    let authMode: SettingsHostAuthMode

    init(preset: SettingsHostPreset, authMode: SettingsHostAuthMode) {
        debugStore = SettingsHostDebugStore(initialPreset: preset)
        self.authMode = authMode
        scenarioID = preset.id
        store = Self.makeStore(preset: preset, authMode: authMode)
    }

    /// 현재 preset의 시나리오를 호출 시점에 읽어 Store를 (재)생성한다.
    /// `.mock` → T2 SettingsHostSandbox가 5축 fake 의존성 주입.
    /// `.live` → 프로덕션 `.liveValue` 의존성 (명시적 opt-in). `date`는 양쪽 모두 real.
    private static func makeStore(
        preset: SettingsHostPreset,
        authMode: SettingsHostAuthMode,
    ) -> StoreOf<SettingsHostFeature> {
        switch authMode {
        case .mock:
            Store(initialState: SettingsHostState()) {
                SettingsHostFeature()
            } withDependencies: { dependencies in
                SettingsHostSandbox.configure(&dependencies, for: preset.scenario)
            }
        case .live:
            Store(initialState: SettingsHostState()) {
                SettingsHostFeature()
            }
        }
    }

    /// 디버그 메뉴/패널에서 preset 선택 시 호출. debugStore를 갱신(패널 자동 refresh)하고
    /// Store를 새 시나리오 의존성으로 재생성 → @Published가 window content remount 유발.
    func select(_ preset: SettingsHostPreset) {
        debugStore.select(preset)
        scenarioID = preset.id
        store = Self.makeStore(preset: preset, authMode: authMode)
    }
}

// MARK: - Window content (host-only)

// 컨테이너의 @Published 변경을 관찰 → 시나리오 변경 시 store 교체 + `.id(scenarioID)`로 clean remount.

private struct SettingsHostWindowContent: View {
    @ObservedObject var container: SettingsHostStoreContainer

    var body: some View {
        SettingsHostRootView(store: container.store)
            .id(container.scenarioID)
    }
}

@MainActor
private final class SettingsHostAppDelegate: NSObject, NSApplicationDelegate {
    let storeContainer: SettingsHostStoreContainer
    private var debugPanel: NSPanel?

    override init() {
        let preset = SmokeMode.resolvePreset()
        let authMode = SettingsHostAuthMode.current
        storeContainer = SettingsHostStoreContainer(preset: preset, authMode: authMode)
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // 시나리오 변경 시 Store 재생성은 SettingsHostStoreContainer.select가 담당.
        // 패널 콘텐츠는 debugStore의 @Published로 자동 갱신됨.
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

        let rootView = SettingsHostDebugPanel(store: storeContainer.debugStore)
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
        storeContainer.select(preset)
        showDebugPanel()
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

            Text("프리셋 선택 시 SettingsHostFeature Store를 해당 시나리오 의존성으로 재생성하여 window를 remount한다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360)
    }
}
