import ComposableArchitecture
import Foundation

@Reducer
struct EntryIntentOperationReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .moveSelectedItemsToTrash:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }

                return .send(.delegate(.intent(.moveToTrash(items: selectedItems))))

            case .deleteSelectedItemsImmediately:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }

                return .send(.delegate(.intent(.deleteImmediately(items: selectedItems))))

            case .putBackSelectedItems:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }

                return .send(.delegate(.intent(.putBackFromTrash(items: selectedItems))))

            case .compressSelectedItems:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }

                return .send(.delegate(.intent(.compressItems(items: selectedItems))))

            case .extractSelectedItem:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard selectedItems.count == 1, let selectedItem = selectedItems.first else {
                    return .none
                }

                return .send(.delegate(.intent(.extractCompressedFile(file: selectedItem))))

            case let .toggleTagForSelectedItem(tag):
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }

                let targets = selectedItems.map { item in
                    let currentTags = item.tags?.map(\.name) ?? []
                    let nextTags: [String] = if currentTags.contains(tag) {
                        currentTags.filter { $0 != tag }
                    } else {
                        currentTags + [tag]
                    }

                    return TagChangeTarget(file: item, beforeTags: currentTags, afterTags: nextTags)
                }

                return .send(.delegate(.intent(.setTagsForItems(targets: targets))))

            case .emptyTrash:
                let trashItems = Array(state.displayItems)
                return .send(.delegate(.intent(.emptyTrash(items: trashItems))))

            default:
                return .none
            }
        }
    }
}
