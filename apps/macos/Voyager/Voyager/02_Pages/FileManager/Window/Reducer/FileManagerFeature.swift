import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct FileManagerFeature {
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        FileManagerWindowNavigationReducer()

        Reduce { state, action in
            switch action {
            case .onAppear:
                if shouldLogDailyFileManagerOpen(userDefaultsClient) {
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_file_manager_first_open",
                        value: 1,
                        tags: ["date": currentDateKey()],
                    )
                }

                return .merge(
                    .send(.content(.entryArrangements(.setSortKey(state.content.entryArrangements.sortKey)))),
                    .send(.content(.entryArrangements(.setSortOrder(state.content.entryArrangements.sortOrder)))),
                    .send(.content(.entryArrangements(.setGroupKey(state.content.entryArrangements.groupKey)))),
                    .send(.content(.entries(.loadItems(path: state.content.navigation.currentPath)))),
                    .send(.sidebar(.loadFavorites)),
                    .send(.sidebar(.loadLocations)),
                    .send(.sidebar(.loadTags)),
                )

            case .onDisappear:
                return .none

            case let .applyAppPreferences(preferences):
                state.sidebar.sidebarVisible = preferences.sidebarVisible
                state.sidebar.sidebarWidth = preferences.sidebarWidth

                state.content.viewLayout = preferences.viewLayout
                state.content.listIconSize = preferences.listIconSize
                state.content.gridIconSize = preferences.gridIconSize
                state.content.listTextSize = preferences.listTextSize
                state.content.gridTextSize = preferences.gridTextSize

                state.content.entryViewLayout.showHiddenFiles = preferences.showHiddenFiles
                state.content.entryArrangements.updateSortKey(preferences.sortKey)
                state.content.entryArrangements.updateSortOrder(preferences.sortOrder)
                state.content.entryArrangements.updateGroupKey(preferences.groupKey)
                state.content.syncComposerCollectionState()

                return .merge(
                    .send(.content(.entryArrangements(.setSortKey(preferences.sortKey)))),
                    .send(.content(.entryArrangements(.setSortOrder(preferences.sortOrder)))),
                    .send(.content(.entryArrangements(.setGroupKey(preferences.groupKey)))),
                )

            case let .sidebar(.dropItemsToSidebarFolder(providers, targetURL)):
                return .send(.content(.dropItemsToSidebarFolder(
                    providers: providers,
                    targetURL: targetURL,
                )))

            case let .sidebar(.dropItemsToTag(providers, tagName)):
                return .send(.content(.dropItemsToTag(
                    providers: providers,
                    tagName: tagName,
                )))

            case .content(.closeWindow):
                return .send(.closeWindow)

            case .closeWindow:
                return .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }

            default:
                return .none
            }
        }
    }
}

private func shouldLogDailyFileManagerOpen(_ userDefaultsClient: UserDefaultsClient) -> Bool {
    let key = "voyager.file_manager.first_open_date"
    let today = currentDateKey()
    let lastValue = userDefaultsClient.string(key)
    if lastValue == today {
        return false
    }
    userDefaultsClient.setString(today, key)
    return true
}

private func currentDateKey() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}
