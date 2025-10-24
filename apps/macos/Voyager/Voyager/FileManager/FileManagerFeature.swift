import AppKit
import ComposableArchitecture
import Foundation

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
        var currentPath: String = Settings.shared.defaultTabPath
        var backHistory: [String] = []
        var forwardHistory: [String] = []
        var fsItems: FSItemsFeature.State = .init()
        var viewLayout: ViewLayout = .list
        var showHiddenFiles: Bool = UserDefaults.standard.bool(forKey: "showHiddenFiles")
        var selectedSidebarItem: String?
        var locations: [SidebarUtils.LocationItem] = []

        var sortKey: SortKey = .init(rawValue: UserDefaults.standard.string(forKey: "sortKey") ?? "") ?? .name
        var sortOrder: SortOrder =
            .init(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .ascending

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
            // 선택된 아이템 중 하나라도 폴더면 열 수 있음
            return fsItems.selectedIds.contains { selectedId in
                fsItems.items.first(where: { $0.id == selectedId })?.isDirectory == true
            }
        }

        var pathComponents: [(name: String, fullPath: String)] {
            var result: [(String, String)] = []
            let fileManager = FileManager.default

            if currentPath.hasPrefix("/") {
                result.append((fileManager.displayName(atPath: "/"), "/"))
            }

            let components = currentPath.split(separator: "/").map(String.init)
            var accumulated = "/"

            for component in components {
                accumulated += component
                result.append((fileManager.displayName(atPath: accumulated), accumulated))
                accumulated += "/"
            }

            return result
        }

        var windowTitle: String {
            FileManagerFeature.makeWindowTitle(for: currentPath)
        }
    }

    enum ViewLayout: String, Equatable, Codable {
        case list
        case grid
    }

    enum Action: Equatable {
        case onAppear
        case navigateTo(String)
        case openItem(id: String)
        case openSelectedItem
        case goBack
        case goForward
        case goToHistoryIndex(Int, isBackHistory: Bool)
        case goToEnclosingDirectory
        case changeLayout(ViewLayout)
        case toggleShowHiddenFiles
        case showRecents
        case showShared
        case loadLocations
        case locationsLoaded([SidebarUtils.LocationItem])
        case openLocation(SidebarUtils.LocationItem)

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
                return .merge(
                    .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                    .send(.fsItems(.setSortKey(state.sortKey))),
                    .send(.fsItems(.setSortOrder(state.sortOrder))),
                    .send(.fsItems(.loadItems(path: state.currentPath)))
                )

            case let .navigateTo(path):
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.currentPath = path
                return .send(.fsItems(.loadItems(path: path)))

            case let .openItem(id):
                guard let item = state.fsItems.items.first(where: { $0.id == id }) else {
                    return .none
                }

                if item.isDirectory {
                    state.backHistory.append(state.currentPath)
                    state.forwardHistory = []
                    state.currentPath = item.fullPath
                    return .send(.fsItems(.loadItems(path: item.fullPath)))
                } else {
                    return .none
                }

            case .openSelectedItem:
                guard !state.fsItems.selectedIds.isEmpty else {
                    return .none
                }

                var selectedFolders: [FSItem] = []
                for selectedId in state.fsItems.selectedIds {
                    if let item = state.fsItems.items.first(where: { $0.id == selectedId }), item.isDirectory {
                        selectedFolders.append(item)
                    }
                }

                if selectedFolders.count == 1 {
                    return .send(.openItem(id: selectedFolders[0].id))
                } else if selectedFolders.count > 1 {
                    for folder in selectedFolders {
                        AppDelegate.shared?.createNewWindow(path: folder.fullPath)
                    }
                    return .none
                } else {
                    return .none
                }

            case .goBack:
                guard let previousPath = state.backHistory.popLast() else {
                    return .none
                }
                state.forwardHistory.append(state.currentPath)
                state.currentPath = previousPath
                return .send(.fsItems(.loadItems(path: previousPath)))

            case .goForward:
                guard let nextPath = state.forwardHistory.popLast() else {
                    return .none
                }
                state.backHistory.append(state.currentPath)
                state.currentPath = nextPath
                return .send(.fsItems(.loadItems(path: nextPath)))

            case let .goToHistoryIndex(index, isBackHistory):
                if isBackHistory {
                    guard index < state.backHistory.count else { return .none }
                    let targetPath = state.backHistory[state.backHistory.count - 1 - index]

                    for idx in (state.backHistory.count - index) ..< state.backHistory.count {
                        state.forwardHistory.append(state.backHistory[idx])
                    }
                    state.forwardHistory.append(state.currentPath)

                    state.backHistory.removeLast(index + 1)
                    state.currentPath = targetPath
                    return .send(.fsItems(.loadItems(path: targetPath)))
                } else {
                    guard index < state.forwardHistory.count else { return .none }
                    let targetPath = state.forwardHistory[state.forwardHistory.count - 1 - index]

                    for idx in (state.forwardHistory.count - index) ..< state.forwardHistory.count {
                        state.backHistory.append(state.forwardHistory[idx])
                    }
                    state.backHistory.append(state.currentPath)

                    state.forwardHistory.removeLast(index + 1)
                    state.currentPath = targetPath
                    return .send(.fsItems(.loadItems(path: targetPath)))
                }

            case .goToEnclosingDirectory:
                let url = URL(fileURLWithPath: state.currentPath)
                let parentURL = url.deletingLastPathComponent()

                guard parentURL.path != state.currentPath else {
                    return .none
                }

                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.currentPath = parentURL.path

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

            case .showRecents:
                state.selectedSidebarItem = "Recents"
                state.currentPath = "Recents"
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                return .send(.fsItems(.loadRecentItems))

            case .showShared:
                state.selectedSidebarItem = "Shared"
                // Shared 섹션은 빈 상태로 유지 (네트워크 리소스 기능은 미구현)
                return .none

            case .loadLocations:
                return .run { send in
                    let locations = await SidebarUtils.loadLocations()
                    await send(.locationsLoaded(locations))
                }

            case let .locationsLoaded(locations):
                state.locations = locations
                return .none

            case let .openLocation(location):
                // AirDrop은 기능 미구현으로 아무 동작하지 않음
                if location.name == "AirDrop" {
                    state.selectedSidebarItem = location.name
                    return .none
                }

                state.selectedSidebarItem = location.name
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.currentPath = location.url.path
                return .send(.fsItems(.loadItems(path: location.url.path)))

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

            case .fsItems:
                return .none
            }
        }
    }
}
