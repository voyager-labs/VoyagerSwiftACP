// FLOW-ID: set.settings_general
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class SettingsGeneralFlowTests: XCTestCase {
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
                defaultHomePath: { "/flow-home" },
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
            $0.settings.generalSettings.selectedDirectoryOption = .custom("/flow-home")
        }
    }

    // FLOW-PATH: check_for_updates_delegation

    /// set.settings_general: check_for_updates_delegation
    func testCheckForUpdatesRoutesFromSettingsToRootUpdater() async {
        let checkForUpdatesCalls = LockIsolated(0)
        var initialState = AppRootFeature.State()
        initialState.updater.isAccessEligible = true
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
