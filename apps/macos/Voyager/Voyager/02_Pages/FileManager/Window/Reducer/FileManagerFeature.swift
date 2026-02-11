import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct FileManagerFeature {
    @Dependency(\.fileManagerNavigationClient)
    var navigationClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.collectionFileClient)
    var collectionFileClient
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.registryClient)
    var registryClient

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            FileManagerContentNavigationFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

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

                state.content.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)
                state.sidebar.sidebarVisible = userDefaultsClient.object(SettingsKeys.sidebarVisible) as? Bool ?? true
                state.content.sortKey = SortKey(rawValue: userDefaultsClient.string("sortKey") ?? "") ?? .name
                state.content
                    .sortOrder = SortOrder(rawValue: userDefaultsClient.string("sortOrder") ?? "") ?? .ascending
                state.content.entries
                    .groupKey = GroupKey(rawValue: userDefaultsClient.string("groupKey") ?? "") ?? .none
                state.content.viewLayout = ContentViewLayout(
                    rawValue: userDefaultsClient.string(SettingsKeys.viewLayout) ?? "",
                ) ?? .list
                state.content.entries.isListView = state.content.viewLayout == .list
                state.content.syncComposerCollectionState()

                if userDefaultsClient.object("columnWidthName") != nil {
                    state.content.columnWidths = ListColumnWidthsUtils(
                        name: CGFloat(userDefaultsClient.double("columnWidthName")),
                        date: CGFloat(userDefaultsClient.double("columnWidthDate")),
                        size: CGFloat(userDefaultsClient.double("columnWidthSize")),
                        kind: CGFloat(userDefaultsClient.double("columnWidthKind")),
                    )
                }

                if let listIconSize = userDefaultsClient.object(SettingsKeys.listIconSize) as? CGFloat {
                    state.content.listIconSize = listIconSize
                }
                if let gridIconSize = userDefaultsClient.object(SettingsKeys.gridIconSize) as? CGFloat {
                    state.content.gridIconSize = gridIconSize
                }

                if let listTextSize = userDefaultsClient.object(SettingsKeys.listTextSize) as? CGFloat {
                    state.content.listTextSize = listTextSize
                }
                if let gridTextSize = userDefaultsClient.object(SettingsKeys.gridTextSize) as? CGFloat {
                    state.content.gridTextSize = gridTextSize
                }

                return .merge(
                    .send(.content(.entries(.setShowHidden(state.content.showHiddenFiles)))),
                    .send(.content(.entries(.setSortKey(state.content.sortKey)))),
                    .send(.content(.entries(.setSortOrder(state.content.sortOrder)))),
                    .send(.content(.entries(.onAppear))),
                    .send(.content(.entries(.loadItems(path: state.content.currentPath)))),
                    .send(.sidebar(.loadFavorites)),
                    .send(.sidebar(.loadLocations)),
                    .send(.sidebar(.loadTags)),
                    .run { [userDefaultsClient] send in
                        for await _ in NotificationCenter.default.notifications(
                            named: UserDefaults.didChangeNotification,
                        ) {
                            if let listIconSize = userDefaultsClient.object("listIconSize") as? CGFloat {
                                await send(.content(.updateListIconSize(listIconSize)))
                            }
                            if let gridIconSize = userDefaultsClient.object("gridIconSize") as? CGFloat {
                                await send(.content(.updateGridIconSize(gridIconSize)))
                            }
                            if let listTextSize = userDefaultsClient.object("listTextSize") as? CGFloat {
                                await send(.content(.updateListTextSize(listTextSize)))
                            }
                            if let gridTextSize = userDefaultsClient.object("gridTextSize") as? CGFloat {
                                await send(.content(.updateGridTextSize(gridTextSize)))
                            }
                            let showHiddenFiles = userDefaultsClient.bool("showHiddenFiles")
                            await send(.content(.setShowHiddenFiles(showHiddenFiles)))
                        }
                    },
                )

            case .sidebar(.favoritesLoaded),
                 .sidebar(.locationsLoaded),
                 .sidebar(.tagsLoaded):
                syncSidebarSelection(state: &state)
                return .none

            case let .sidebar(.openFavorite(favorite)):
                if favorite.url.pathExtension.lowercased() == "voycoll" {
                    state.sidebar.pendingSidebarSelectionRestore = state.sidebar.selectedSidebarItem
                    state.sidebar.selectedSidebarItem = favorite.displayName
                    return .send(.openCollectionFile(favorite.url))
                }
                return .send(.navigateTo(favorite.url.path))

            case let .sidebar(.openLocation(location)):
                return .send(.navigateTo(location.url.path))

            case let .sidebar(.showTag(tag)):
                return .send(.showTag(tag.name))

            case .sidebar(.showRecents):
                return .send(.showRecents)

            case .sidebar(.showComputer):
                return .send(.showComputer)

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

            case let .content(.entries(.navigateFolder(id: id))):
                guard let entry = state.content.entries.displayItems[id: id] else {
                    return .none
                }
                return .send(.navigateTo(entry.fullPath))

            case let .content(.entries(.openCollectionFile(url))):
                return .send(.openCollectionFile(url))

            case let .content(.performPendingNavigation(pending)):
                return .send(.navigation(.performNavigation(
                    pending,
                    currentSnapshot: state.content.makeContentPageHistory(),
                )))

            case .content(.closeWindow):
                return .send(.closeWindow)

            case let .navigation(action):
                return handleNavigationAction(action, state: &state)

            case .content(.composer(.searchResponse(.failure))),
                 .content(.composer(.filtersResponse(.failure))):
                if state.sidebar.pendingSidebarSelectionRestore != nil {
                    return .send(.sidebar(.restoreSidebarSelection))
                }
                return .none

            case let .navigateTo(path):
                let effect = handleNavigateTo(path, state: &state)
                syncSidebarSelection(state: &state)
                return effect

            case .showRecents:
                let effect = handleShowRecents(state: &state)
                syncSidebarSelection(state: &state)
                return effect

            case .showComputer:
                let effect = handleShowComputer(state: &state)
                syncSidebarSelection(state: &state)
                return effect

            case let .showTag(tagName):
                let effect = handleShowTag(tagName, state: &state)
                syncSidebarSelection(state: &state)
                return effect

            case let .openCollectionFile(url):
                return handleOpenCollectionFile(url, state: &state)

            case let .collectionFileLoaded(result):
                return handleCollectionFileLoaded(result, state: &state)

            case let .navigateToCollection(navigation):
                return handleNavigateToCollection(navigation, state: &state)

            case .content(.composer(.searchResponse(.success))),
                 .content(.composer(.filtersResponse(.success))),
                 .content(.discardCollectionChanges):
                syncSidebarSelection(state: &state)
                return .none

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
