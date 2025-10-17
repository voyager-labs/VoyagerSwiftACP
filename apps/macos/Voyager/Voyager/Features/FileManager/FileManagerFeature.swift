import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerFeature {
    @ObservableState
    struct State: Equatable {
        var currentPath: String = FileManager.default.homeDirectoryForCurrentUser.path
        var items: [FSItemModel] = []
        var selectedIds: Set<String> = []
        var isLoading: Bool = false
        var backHistory: [String] = []
        var forwardHistory: [String] = []

        var canGoBack: Bool {
            !backHistory.isEmpty
        }

        var canGoForward: Bool {
            !forwardHistory.isEmpty
        }
    }

    enum Action: Equatable {
        case onAppear
        case loadItems(path: String)
        case itemsLoaded([FSItemModel])
        case selectItem(id: String, isCommandPressed: Bool)
        case openItem(id: String)
        case goBack
        case goForward
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadItems(path: state.currentPath))

            case let .loadItems(path):
                state.isLoading = true
                return .run { send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let contents = (try? FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []

                    let mapped: [FSItemModel] = contents.map { itemURL in
                        let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?
                            .isDirectory ?? false
                        return FSItemModel(
                            name: itemURL.lastPathComponent,
                            fullPath: itemURL.path,
                            isDirectory: isDirectory
                        )
                    }

                    let items = mapped.sorted { item1, item2 in
                        if item1.isDirectory != item2.isDirectory {
                            return item1.isDirectory
                        }
                        return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                    }

                    await send(.itemsLoaded(items))
                }

            case let .itemsLoaded(items):
                state.items = items
                state.isLoading = false
                return .none

            case let .selectItem(id, isCommandPressed):
                if isCommandPressed {
                    if state.selectedIds.contains(id) {
                        state.selectedIds.remove(id)
                    } else {
                        state.selectedIds.insert(id)
                    }
                } else {
                    state.selectedIds = [id]
                }
                return .none

            case let .openItem(id):
                guard let item = state.items.first(where: { $0.id == id }) else {
                    return .none
                }

                if item.isDirectory {
                    // 히스토리에 현재 경로 추가
                    state.backHistory.append(state.currentPath)
                    state.forwardHistory = [] // 새 경로로 이동하면 forward 히스토리 초기화
                    state.currentPath = item.fullPath
                    state.selectedIds = []
                    return .send(.loadItems(path: item.fullPath))
                } else {
                    // 파일 열기 (나중에 구현)
                    return .none
                }

            case .goBack:
                guard let previousPath = state.backHistory.popLast() else {
                    return .none
                }
                state.forwardHistory.append(state.currentPath)
                state.currentPath = previousPath
                state.selectedIds = []
                return .send(.loadItems(path: previousPath))

            case .goForward:
                guard let nextPath = state.forwardHistory.popLast() else {
                    return .none
                }
                state.backHistory.append(state.currentPath)
                state.currentPath = nextPath
                state.selectedIds = []
                return .send(.loadItems(path: nextPath))
            }
        }
    }
}
