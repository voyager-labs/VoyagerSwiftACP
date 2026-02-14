import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct FileManagerFeature {
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.collectionFileClient)
    var collectionFileClient
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.registryClient)
    var registryClient

    private let userDefaultsObserverCancelID = "fileManager.userDefaultsObserver"

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

        FileManagerWindowNavigationFeature()

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

                state.content.entries.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)
                state.sidebar.sidebarVisible = userDefaultsClient.object(SettingsKeys.sidebarVisible) as? Bool ?? true
                if let sidebarWidth = userDefaultsClient.object(SettingsKeys.sidebarWidth) as? Double,
                   sidebarWidth > 0
                {
                    state.sidebar.sidebarWidth = CGFloat(sidebarWidth)
                }
                let persistedSortKey = SortKey(
                    rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortKey) ?? "",
                ) ?? .name
                let persistedSortOrder = SortOrder(
                    rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortOrder) ?? "",
                ) ?? .ascending
                let persistedGroupKey = GroupKey(
                    rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.groupKey) ?? "",
                ) ?? .none
                state.content.viewLayout = ContentViewLayout(
                    rawValue: userDefaultsClient.string(SettingsKeys.viewLayout) ?? "",
                ) ?? .list
                state.content.syncComposerCollectionState()

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
                    .send(.content(.entries(.setShowHidden(state.content.entries.showHiddenFiles)))),
                    .send(.content(.entryArrangements(.setSortKey(persistedSortKey)))),
                    .send(.content(.entryArrangements(.setSortOrder(persistedSortOrder)))),
                    .send(.content(.entryArrangements(.setGroupKey(persistedGroupKey)))),
                    .send(.content(.entries(.onAppear))),
                    .send(.content(.entries(.loadItems(path: state.content.navigation.currentPath)))),
                    .send(.sidebar(.loadFavorites)),
                    .send(.sidebar(.loadLocations)),
                    .send(.sidebar(.loadTags)),
                    .run { [userDefaultsClient] send in
                        for await _ in NotificationCenter.default.notifications(
                            named: UserDefaults.didChangeNotification,
                        ) {
                            if let listIconSize = userDefaultsClient.object("listIconSize") as? CGFloat {
                                await send(.content(.entries(.setListIconSize(listIconSize))))
                            }
                            if let gridIconSize = userDefaultsClient.object("gridIconSize") as? CGFloat {
                                await send(.content(.entries(.setGridIconSize(gridIconSize))))
                            }
                            if let listTextSize = userDefaultsClient.object("listTextSize") as? CGFloat {
                                await send(.content(.entries(.setListTextSize(listTextSize))))
                            }
                            if let gridTextSize = userDefaultsClient.object("gridTextSize") as? CGFloat {
                                await send(.content(.entries(.setGridTextSize(gridTextSize))))
                            }
                            let showHiddenFiles = userDefaultsClient.bool("showHiddenFiles")
                            await send(.content(.entries(.applyShowHiddenFiles(showHiddenFiles))))
                        }
                    }
                    .cancellable(id: userDefaultsObserverCancelID, cancelInFlight: true),
                )

            case .onDisappear:
                return .cancel(id: userDefaultsObserverCancelID)

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
                return .merge(
                    .cancel(id: userDefaultsObserverCancelID),
                    .run { _ in
                        await MainActor.run {
                            NSApp.keyWindow?.close()
                        }
                    },
                )

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

// TODO(shared): 공유 유틸 성격이 강하므로 분리 필요
private func currentDateKey() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}
