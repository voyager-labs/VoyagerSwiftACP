import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesUpdateVersion
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class AppRootCompositionTests: XCTestCase {
    func testAppPreferencesUpdatedRoutesToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        var preferences = Voyager.AppPreferencesState()
        preferences.showHiddenFiles = true
        preferences.viewLayout = EntryViewLayoutState.Mode.grid
        preferences.sidebarVisible = false

        await store.send(.appPreferences(.delegate(.updated(preferences)))) {
            $0.appPreferences = preferences
        }
        await store.receive(\.windowManager.lifecycle.applyAppPreferences) {
            $0.windowManager.appPreferences = preferences
        }
    }

    func testMenuCommandRoutesToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(\.updater.checkForUpdates)
    }
}
