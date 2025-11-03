import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

struct BreadcrumbItem: Equatable {
    let name: String
    let fullPath: String
    let icon: NSImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.fullPath == rhs.fullPath
    }

    init(path: String) {
        fullPath = path
        name = FileManager.default.displayName(atPath: path)
        icon = NSWorkspace.shared.icon(forFile: path)
    }

    init(fsItem: FSItem) {
        fullPath = fsItem.fullPath
        name = fsItem.name
        icon = FSItemsIconUtils.icon(for: fsItem)
    }
}

// swiftlint:disable type_body_length
@Reducer
struct FileManagerFeature {
    static func makeWindowTitle(for path: String) -> String {
        if path == "/" {
            return FileManager.default.displayName(atPath: "/")
        }
        return FileManager.default.displayName(atPath: path)
    }

    @ObservableState
    struct State: Equatable {
        var navigationState: FileManagerNavigationUtils.NavigationState = .folder(Settings.shared.defaultTabPath)
        var currentPath: String {
            switch navigationState {
            case let .folder(path): return path
            case .recents: return "Recents"
            case .shared: return "Shared"
            case let .tags(tagName): return tagName
            }
        }

        var titlePath: String = Settings.shared.defaultTabPath

        var scrollPositions: [String: String] = [:]
        var scrollTargetId: String?

        var backHistory: [String] = []
        var forwardHistory: [String] = []
        var fsItems: FSItemsFeature.State = .init()
        var viewLayout: ViewLayout = .list
        var showHiddenFiles: Bool = false
        var sidebarVisible: Bool = true
        var selectedSidebarItem: String?
        var locations: [SidebarUtils.LocationItem] = []
        var tags: [SidebarUtils.TagItem] = []

        var sortKey: SortKey = .name
        var sortOrder: SortOrder = .ascending

        var canGoBack: Bool {
            !backHistory.isEmpty
        }

        var canGoForward: Bool {
            !forwardHistory.isEmpty
        }

        var canGoToEnclosingDirectory: Bool {
            let url = URL(fileURLWithPath: currentPath)
            let parent = url.deletingLastPathComponent()
            return parent.path != currentPath && currentPath != "/"
        }

        var canOpenSelectedItem: Bool {
            guard !fsItems.selectedIds.isEmpty else {
                return false
            }
            return fsItems.items.contains { fsItems.selectedIds.contains($0.id) }
        }

        var canQuickLookSelectedItem: Bool {
            guard fsItems.selectedIds.count == 1 else {
                return false
            }
            guard let selectedId = fsItems.selectedIds.first else {
                return false
            }
            return fsItems.items.contains(where: { $0.id == selectedId })
        }

        var breadcrumbItems: [BreadcrumbItem] {
            switch navigationState {
            case .recents, .shared, .tags:
                return []
            case let .folder(path):
                var result: [BreadcrumbItem] = []

                if path.hasPrefix("/") {
                    result.append(BreadcrumbItem(path: "/"))
                }

                let components = path.split(separator: "/").map(String.init)
                var accumulated = "/"

                for component in components {
                    accumulated += component
                    result.append(BreadcrumbItem(path: accumulated))
                    accumulated += "/"
                }

                return result
            }
        }

        var selectedBreadcrumbItem: BreadcrumbItem? {
            guard fsItems.selectedIds.count == 1,
                  let selectedItem = fsItems.items.first(where: { $0.id == fsItems.selectedIds.first })
            else { return nil }

            return BreadcrumbItem(fsItem: selectedItem)
        }

        var windowTitle: String {
            FileManagerFeature.makeWindowTitle(for: titlePath)
        }

        mutating func matchSidebarToPath(_ path: String, locations: [SidebarUtils.LocationItem]) {
            if !path.hasPrefix("/") {
                selectedSidebarItem = path
            } else if let matchingLocation = locations.first(where: { $0.url.path == path }) {
                selectedSidebarItem = matchingLocation.name
            } else {
                selectedSidebarItem = nil
            }
        }

        mutating func saveCurrentScrollPosition() {
            if let selectedId = fsItems.selectedIds.first {
                scrollPositions[currentPath] = selectedId
            }
        }
    }

    enum ViewLayout: String, Equatable, Codable {
        case list
        case grid
    }

    enum Action: Sendable {
        case onAppear
        case navigateTo(String)
        case openSelectedItem
        case quickLookSelectedItem
        case duplicateSelectedItems
        case goBack
        case goForward
        case goToHistoryIndex(Int, isBackHistory: Bool)
        case goToEnclosingDirectory
        case changeLayout(ViewLayout)
        case toggleShowHiddenFiles
        case setSidebarVisible(Bool)
        case showRecents
        case showShared
        case loadLocations
        case locationsLoaded([SidebarUtils.LocationItem])
        case openLocation(SidebarUtils.LocationItem)

        case loadTags
        case tagsLoaded([SidebarUtils.TagItem])
        case showTag(SidebarUtils.TagItem)

        case changeSortKey(SortKey)
        case changeSortOrder(SortOrder)
        case changeGroupKey(GroupKey)

        case fsItems(FSItemsFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.fsItems, action: \.fsItems) {
            FSItemsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.showHiddenFiles = UserDefaults.standard.bool(forKey: "showHiddenFiles")
                state.sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
                state.sortKey = SortKey(rawValue: UserDefaults.standard.string(forKey: "sortKey") ?? "") ?? .name
                state
                    .sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ??
                    .ascending

                return .merge(
                    .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                    .send(.fsItems(.setSortKey(state.sortKey))),
                    .send(.fsItems(.setSortOrder(state.sortOrder))),
                    .send(.fsItems(.loadItems(path: state.currentPath))),
                    .send(.loadLocations),
                    .send(.loadTags)
                )

            case let .navigateTo(path):
                state.saveCurrentScrollPosition()
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.navigationState = .folder(path)
                state.matchSidebarToPath(path, locations: state.locations)
                return .send(.fsItems(.loadItems(path: path)))

            case .openSelectedItem:
                return .send(.fsItems(.openSelectedItem))

            case .quickLookSelectedItem:
                return .send(.fsItems(.quickLookSelectedItem))

            case .duplicateSelectedItems:
                return .send(.fsItems(.duplicateSelectedItems))

            case .goBack:
                guard let previousPath = state.backHistory.popLast() else {
                    return .none
                }
                state.saveCurrentScrollPosition()
                state.forwardHistory.append(state.currentPath)

                state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(previousPath)
                state.matchSidebarToPath(previousPath, locations: state.locations)
                return FileManagerNavigationUtils.navigateToState(state.navigationState)

            case .goForward:
                guard let nextPath = state.forwardHistory.popLast() else {
                    return .none
                }
                state.saveCurrentScrollPosition()
                state.backHistory.append(state.currentPath)

                state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(nextPath)
                state.matchSidebarToPath(nextPath, locations: state.locations)
                return FileManagerNavigationUtils.navigateToState(state.navigationState)

            case let .goToHistoryIndex(index, isBackHistory):
                state.saveCurrentScrollPosition()
                if isBackHistory {
                    guard index < state.backHistory.count else { return .none }
                    let targetPath = state.backHistory[state.backHistory.count - 1 - index]

                    for idx in (state.backHistory.count - index) ..< state.backHistory.count {
                        state.forwardHistory.append(state.backHistory[idx])
                    }
                    state.forwardHistory.append(state.currentPath)

                    state.backHistory.removeLast(index + 1)

                    state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(targetPath)
                    state.matchSidebarToPath(targetPath, locations: state.locations)
                    return FileManagerNavigationUtils.navigateToState(state.navigationState)
                } else {
                    guard index < state.forwardHistory.count else { return .none }
                    let targetPath = state.forwardHistory[state.forwardHistory.count - 1 - index]

                    for idx in (state.forwardHistory.count - index) ..< state.forwardHistory.count {
                        state.backHistory.append(state.forwardHistory[idx])
                    }
                    state.backHistory.append(state.currentPath)

                    state.forwardHistory.removeLast(index + 1)

                    state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(targetPath)
                    state.matchSidebarToPath(targetPath, locations: state.locations)
                    return FileManagerNavigationUtils.navigateToState(state.navigationState)
                }

            case .goToEnclosingDirectory:
                let url = URL(fileURLWithPath: state.currentPath)
                let parentURL = url.deletingLastPathComponent()

                guard parentURL.path != state.currentPath else {
                    return .none
                }

                state.saveCurrentScrollPosition()
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.navigationState = .folder(parentURL.path)

                return .send(.fsItems(.loadItems(path: parentURL.path)))

            case let .changeLayout(layout):
                state.viewLayout = layout
                UserDefaults.standard.set(layout.rawValue, forKey: "viewLayout")
                return .none

            case .toggleShowHiddenFiles:
                state.showHiddenFiles.toggle()
                UserDefaults.standard.set(state.showHiddenFiles, forKey: "showHiddenFiles")
                return .merge(
                    .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                    .send(.fsItems(.loadItems(path: state.currentPath)))
                )

            case let .setSidebarVisible(visible):
                state.sidebarVisible = visible
                UserDefaults.standard.set(visible, forKey: "sidebarVisible")
                return .none

            case .showRecents:
                state.saveCurrentScrollPosition()
                state.selectedSidebarItem = "Recents"
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.navigationState = .recents
                return .send(.fsItems(.loadRecentItems))

            case .showShared:
                state.saveCurrentScrollPosition()
                state.selectedSidebarItem = "Shared"
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.navigationState = .shared
                // Shared 섹션은 빈 상태로 유지 (네트워크 리소스 기능은 미구현)
                return .none

            case .loadLocations:
                return .run { send in
                    let locations = await SidebarUtils.loadLocations()
                    await send(.locationsLoaded(locations))
                }

            case let .locationsLoaded(locations):
                state.locations = locations
                state.matchSidebarToPath(state.currentPath, locations: locations)
                return .none

            case let .openLocation(location):
                // AirDrop은 기능 미구현으로 아무 동작하지 않음
                if location.name == "AirDrop" {
                    state.selectedSidebarItem = location.name
                    return .none
                }

                if state.currentPath == location.url.path {
                    return .none
                }

                state.saveCurrentScrollPosition()
                state.selectedSidebarItem = location.name
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.navigationState = .folder(location.url.path)
                return .send(.fsItems(.loadItems(path: location.url.path)))

            case .loadTags:
                return .run { send in
                    let tags = await SidebarUtils.loadTags()
                    await send(.tagsLoaded(tags))
                }

            case let .tagsLoaded(tags):
                state.tags = tags
                return .none

            case let .showTag(tagItem):
                state.saveCurrentScrollPosition()
                state.selectedSidebarItem = tagItem.name
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.navigationState = .tags(tagItem.name)
                return .run { send in
                    let taggedItems = await SidebarUtils.loadFilesWithTag(tagItem.name)
                    await send(.fsItems(.itemsLoaded(taggedItems)))
                }

            case let .changeSortKey(key):
                state.sortKey = key
                UserDefaults.standard.set(key.rawValue, forKey: "sortKey")
                return .send(.fsItems(.setSortKey(key)))

            case let .changeSortOrder(order):
                state.sortOrder = order
                UserDefaults.standard.set(order.rawValue, forKey: "sortOrder")
                return .send(.fsItems(.setSortOrder(order)))

            case let .changeGroupKey(key):
                return .send(.fsItems(.setGroupKey(key)))

            case let .fsItems(action):
                switch action {
                case .itemsLoaded:
                    state.titlePath = state.currentPath

                    if let savedId = state.scrollPositions[state.currentPath],
                       state.fsItems.items.contains(where: { $0.id == savedId })
                    {
                        state.scrollTargetId = savedId
                    } else {
                        state.scrollTargetId = nil
                    }
                    return .none

                case let .navigateFolder(id):
                    guard let item = state.fsItems.items.first(where: { $0.id == id }) else {
                        return .none
                    }
                    state.saveCurrentScrollPosition()
                    state.backHistory.append(state.currentPath)
                    state.forwardHistory = []
                    state.navigationState = .folder(item.fullPath)
                    state.matchSidebarToPath(item.fullPath, locations: state.locations)
                    return .send(.fsItems(.loadItems(path: item.fullPath)))

                default:
                    return .none
                }
            }
        }
    }
}

// swiftlint:enable type_body_length
