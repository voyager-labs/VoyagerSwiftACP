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

        _ = feature.reduce(into: &state, action: .onAppear)
        print("onAppearDispatched=true")

        let sectionBefore = state.selectedSection.rawValue
        print("selectedSectionBefore=\(sectionBefore)")

        _ = feature.reduce(into: &state, action: .selectSection(.appearance))
        let sectionAfter = state.selectedSection.rawValue
        print("selectedSectionAfter=\(sectionAfter)")

        _ = feature.reduce(into: &state, action: .closeWindow)
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
            // 호스트 전용 시나리오 프리셋 메뉴 — in-window SettingsHostScenarioBar와 동일 경로.
            // 선택은 SettingsHostStoreContainer.select를 통해 Store를 새 시나리오 의존성으로 재생성한다.
            CommandMenu("Settings Debug") {
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
    @Published private(set) var preset: SettingsHostPreset

    let authMode: SettingsHostAuthMode

    init(preset: SettingsHostPreset, authMode: SettingsHostAuthMode) {
        self.authMode = authMode
        self.preset = preset
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
            // mock: preset-derived 초기 Settings 상태 주입. Host는 child internals를 직접 건드리지 않고
            // Settings package-owned factory만 호출한다 (boundary).
            Store(initialState: SettingsHostState(settings: .hostPreset(for: preset.scenario))) {
                SettingsHostFeature()
            } withDependencies: { dependencies in
                SettingsHostSandbox.configure(&dependencies, for: preset.scenario)
            }
        case .live:
            // live: 실제 user data를 덮어쓰지 않도록 safe default (.init()) 유지.
            Store(initialState: SettingsHostState()) {
                SettingsHostFeature()
            }
        }
    }

    /// 디버그 메뉴/시나리오 바에서 preset 선택 시 호출.
    /// Store를 새 시나리오 의존성으로 재생성 → @Published가 window content remount 유발.
    /// 이전 Store는 deallocation으로 in-flight effect가 취소된다 (TCA lifecycle).
    func select(_ preset: SettingsHostPreset) {
        self.preset = preset
        scenarioID = preset.id
        store = Self.makeStore(preset: preset, authMode: authMode)
    }
}

// MARK: - Window content (host-only)

// 컨테이너의 @Published 변경을 관찰 → 시나리오 변경 시 store 교체 + `.id(scenarioID)`로 clean remount.

private struct SettingsHostWindowContent: View {
    @ObservedObject var container: SettingsHostStoreContainer

    var body: some View {
        VStack(spacing: 0) {
            SettingsHostScenarioBar(container: container)
            SettingsHostRootView(store: container.store)
                .id(container.scenarioID)
        }
    }
}

// MARK: - In-window scenario chrome (host-only)

/// 플로팅 패널 없이도 시나리오 전환을 창 내에서 직접 수행 가능한 호스트 전용 상단 바.
/// SettingsView 프로덕션 영역 바깥에 렌더링되므로 프로덕션 코드에 영향 없음.
private struct SettingsHostScenarioBar: View {
    @ObservedObject var container: SettingsHostStoreContainer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            Text("Scenario")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { container.preset },
                set: { container.select($0) },
            )) {
                ForEach(SettingsHostPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 280)

            Spacer(minLength: 0)

            Text(container.preset.scenario.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings host scenario selector")
    }
}

@MainActor
private final class SettingsHostAppDelegate: NSObject, NSApplicationDelegate {
    let storeContainer: SettingsHostStoreContainer

    override init() {
        let preset = SmokeMode.resolvePreset()
        let authMode = SettingsHostAuthMode.current
        storeContainer = SettingsHostStoreContainer(preset: preset, authMode: authMode)
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // 시나리오 변경 시 Store 재생성은 SettingsHostStoreContainer.select가 담당.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func selectPreset(_ preset: SettingsHostPreset) {
        storeContainer.select(preset)
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
