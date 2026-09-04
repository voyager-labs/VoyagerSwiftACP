// FLOW-ID: set.settings_general
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class SettingsGeneralFlowTests: XCTestCase {
    private func persistedStartPageClient(_ startPage: StartPage) -> UserDefaultsClient {
        let values: [String: String] = switch startPage {
        case .home:
            [SettingsKeys.defaultStartPageType: "home"]
        case let .directory(path):
            [
                SettingsKeys.defaultStartPageType: "directory",
                SettingsKeys.defaultTabPath: path,
            ]
        }
        return UserDefaultsClient(
            bool: { _ in false },
            setBool: { _, _ in },
            string: { key in values[key] },
            setString: { _, _ in },
            double: { _ in 0 },
            setDouble: { _, _ in },
            object: { _ in nil },
            setObject: { _, _ in },
        )
    }

    // FLOW-PATH: happy_path

    /// set.settings_general: happy_path
    func testLaunchBootstrapLoadsGeneralPreferencesThroughSettingsComposition() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.directorySelectionClient = DirectorySelectionClient(
                pickDirectory: { nil },
                pathExists: { _ in false },
                isDirectory: { _ in false },
                standardDirectories: {
                    StandardDirectories(
                        homePath: "/flow-home",
                        homeDisplayName: "flow-home",
                        desktopPath: nil,
                        documentsPath: nil,
                        downloadsPath: nil,
                    )
                },
            )
            $0.launchAtLoginClient.isEnabled = { false }
            $0.launchAtLoginClient.setEnabled = { _ in }
            $0.userDefaultsClient = UserDefaultsClient(
                bool: { _ in false },
                setBool: { _, _ in },
                string: { _ in nil },
                setString: { _, _ in },
                double: { _ in 0 },
                setDouble: { _, _ in },
                object: { _ in nil },
                setObject: { _, _ in },
            )
        }
        // store.exhaustivity = .off: root launch의 독립 observer와 Settings 자식 bootstrap을 함께 검증한다.
        store.exhaustivity = .off

        await store.send(.lifecycle(.launch(.willFinishLaunching)))
        await store.receive(\.settings.bootstrapLocalPreferences)
        await store.receive(\.settings.ai.onAppear)
        await store.receive(\.settings.general.loadSettings) {
            $0.settings.generalSettings.startingDirectory = "/flow-home"
            $0.settings.generalSettings.selectedDirectoryOption = .home
        }
    }

    // MARK: - SET-002-settings_general_composition

    /// SET-002-settings_general_composition: persisted start page reaches every default content surface.
    /// Reloaded settings must be delegated through AppRoot before WindowManager creates initial, new-window, and
    /// new-tab content.
    /// - 검증 내용: persisted Home/Directory, existing-window preservation, initial window, Cmd+N, Cmd+T, Sidebar new-tab,
    /// path privacy
    /// - 사전 조건: persisted preference is reloaded through AppPreferences and no path-bearing metric payload is accepted
    /// - 기대 결과: configured start page is used by each default surface while existing content remains unchanged
    func testPersistedStartPageComposesInitialWindowNewWindowAndTabsWithoutPathTelemetry() async throws {
        let existingID = UUID()
        let existingPath = "/existing-content"
        let directoryPath = "/configured-directory"
        let metricNames = LockIsolated<[String]>([])

        for startPage in [StartPage.home, .directory(directoryPath)] {
            var initialState = AppRootFeature.State()
            initialState.windowManager.windows = [
                .init(id: existingID, window: .makeInitial(path: existingPath)),
            ]
            initialState.windowManager.focusedWindowID = existingID
            let registeredWindowIDs = LockIsolated<Set<UUID>>([existingID])
            let store = TestStore(initialState: initialState) {
                AppRootFeature()
            } withDependencies: {
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.uuid = .incrementing
                $0.onboardingWindowClient.showIfNeeded = { false }
                $0.fileManagerWindowClient.open = { id in
                    _ = registeredWindowIDs.withValue { $0.insert(id) }
                }
                $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
                $0.userDefaultsClient = persistedStartPageClient(startPage)
                $0.metricsClient = MetricsClient(
                    logMetric: { name, _, tags in
                        metricNames.withValue { $0.append(name) }
                        XCTAssertNil(tags?["path"])
                    },
                    logDAUNavigation: { _ in },
                    logDAUEntryAction: { _, _ in },
                )
                $0.startPageAvailabilityClient = .init { path in
                    path == directoryPath ? .availableDirectory : .missing
                }
            }
            store.exhaustivity = .off

            await store.send(.appPreferences(.load))
            await store.receive { action in
                guard case .appPreferences(.delegate(.updated)) = action else { return false }
                return true
            }
            await store.receive(\.windowManager.lifecycle.applyAppPreferences)

            await store.send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))
            await store.send(.windowManager(.file(.newWindow(path: nil))))
            if case .directory = startPage {
                // Directory 시작 페이지는 비동기 프로브 완료 후 창이 생성된다.
                await store.receive(\.windowManager.defaultStartPageResolved)
            }
            let newWindowID = try XCTUnwrap(store.state.windowManager.focusedWindowID)

            await store.send(.windowManager(.file(.newTab)))
            await store.receive { action in
                guard case let .windowManager(.windows(.element(
                    id,
                    action: .window(.request(.openNewContentTab(source: .menuCommand))),
                ))) = action else { return false }
                return id == newWindowID
            }

            await store.send(.windowManager(.windows(.element(
                id: newWindowID,
                action: .window(.sidebar(.delegate(.openContentTab))),
            ))))
        }

        XCTAssertTrue(metricNames.value.allSatisfy { !$0.contains(directoryPath) })
    }

    // FLOW-PATH: check_for_updates_delegation

    /// set.settings_general: check_for_updates_delegation
    func testCheckForUpdatesRoutesFromSettingsToRootUpdater() async {
        let checkForUpdatesCalls = LockIsolated(0)
        var initialState = AppRootFeature.State()
        initialState.updater.didConfigure = true
        initialState.updater.didStartAtLaunch = true
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.updaterClient.checkForUpdates = {
                checkForUpdatesCalls.withValue { $0 += 1 }
            }
        }
        // store.exhaustivity = .off: Settings child action이 root UpdaterFeature로 위임되는 경계만 검증한다.
        store.exhaustivity = .off

        await store.send(.settings(.general(.checkForUpdates)))
        await store.receive(\.updater.checkForUpdates)
        await store.finish()

        XCTAssertEqual(checkForUpdatesCalls.value, 1)
    }
}
