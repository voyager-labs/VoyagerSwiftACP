import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerShared

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

            case let .request(command):
                return handleRequestedCommand(command, state: &state)

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

            case let .content(.openPathInNewWindow(path)):
                return .send(.delegate(.openPathInNewWindow(path)))

            case let .content(.openPathInNewTab(path)):
                return .send(.delegate(.openPathInNewTab(path)))

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

    private func handleRequestedCommand(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .newFolder,
             .openSelectedItem,
             .quickLookSelectedItem,
             .toggleShowHiddenFiles,
             .cut,
             .copy,
             .paste,
             .duplicate,
             .makeAlias,
             .selectAll,
             .copyAbsolutePaths,
             .copyURLs:
            handleEntryRequest(command, state: &state)

        case .saveCollection,
             .saveCollectionAs,
             .toggleComposer:
            handleComposerRequest(command, state: &state)

        case .goBack,
             .goForward,
             .goToEnclosingDirectory:
            handleNavigationRequest(command)

        case .toggleSidebar,
             .setViewLayout,
             .setGroupKey,
             .setSortKey,
             .setSortOrder:
            handleLayoutRequest(command, state: &state)

        case .requestUndo,
             .requestRedo:
            handleUndoRedoRequest(command)
        }
    }

    private func handleEntryRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .newFolder:
            .send(.content(.entries(.createNewFolder(currentPath: state.content.navigation.currentPath))))
        case .openSelectedItem:
            .send(.content(.entries(.openSelectedItem)))
        case .quickLookSelectedItem:
            .send(.content(.entries(.quickLookSelectedItem)))
        case .toggleShowHiddenFiles:
            .send(.content(.entries(.toggleShowHiddenFiles)))
        case .cut:
            .send(.content(.entries(.cutSelectedItems)))
        case .copy:
            .send(.content(.entries(.copySelectedItems)))
        case .paste:
            .send(.content(.entries(.pasteItems(destinationPath: state.content.navigation.currentPath))))
        case .duplicate:
            .send(.content(.entries(.duplicateSelectedItems)))
        case .makeAlias:
            .send(.content(.entries(.createAliasForSelectedItems)))
        case .selectAll:
            .send(.content(.entries(.selectAll)))
        case .copyAbsolutePaths:
            .send(.content(.entries(.copySelectedAbsolutePaths)))
        case .copyURLs:
            .send(.content(.entries(.copySelectedURLs)))
        default:
            .none
        }
    }

    private func handleComposerRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .saveCollection:
            .send(.content(.composer(.saveCollection)))
        case .saveCollectionAs:
            .send(.content(.composer(.saveCollectionAs)))
        case .toggleComposer:
            .send(.content(.composer(.setPresented(!state.content.composer.isPresented))))
        default:
            .none
        }
    }

    private func handleNavigationRequest(_ command: Action.WindowCommand) -> Effect<Action> {
        switch command {
        case .goBack:
            .send(.navigation(.goBack))
        case .goForward:
            .send(.navigation(.goForward))
        case .goToEnclosingDirectory:
            .send(.navigation(.goToEnclosingDirectory))
        default:
            .none
        }
    }

    private func handleLayoutRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .toggleSidebar:
            .send(.sidebar(.setSidebarVisible(!state.sidebar.sidebarVisible)))
        case let .setViewLayout(layout):
            .send(.content(.changeLayout(layout)))
        case let .setGroupKey(key):
            .send(.content(.entryArrangements(.setGroupKey(key))))
        case let .setSortKey(key):
            .send(.content(.entryArrangements(.setSortKey(key))))
        case let .setSortOrder(order):
            .send(.content(.entryArrangements(.setSortOrder(order))))
        default:
            .none
        }
    }

    private func handleUndoRedoRequest(_ command: Action.WindowCommand) -> Effect<Action> {
        switch command {
        case .requestUndo:
            .send(.content(.entryOperations(.requestUndo)))
        case .requestRedo:
            .send(.content(.entryOperations(.requestRedo)))
        default:
            .none
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
