import ComposableArchitecture
import Foundation

/// 파일 시스템 아이템 목록 및 선택 관리 (FSV 영역)
@Reducer
struct FSItemsFeature {
    @ObservableState
    struct State: Equatable {
        var items: [FSItemModel] = []
        var selectedIds: Set<String> = []
        var isLoading: Bool = false
    }

    enum Action: Equatable {
        case loadItems(path: String)
        case itemsLoaded([FSItemModel])
        case selectItem(id: String, isCommandPressed: Bool)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
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
            }
        }
    }
}
