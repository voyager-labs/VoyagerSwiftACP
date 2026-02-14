import ComposableArchitecture
import Foundation

@Reducer
struct EntryIntentClipboardReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .copySelectedItems:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                return .send(.delegate(.intent(.copySelectedItems(files: selectedItems))))

            case .copySelectedAbsolutePaths:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }

                return .send(.delegate(.intent(.copyAbsolutePaths(paths: selectedItems.map(\.fullPath)))))

            case .copySelectedURLs:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else { return .none }

                return .send(.delegate(.intent(.copyURLs(paths: selectedItems.map(\.fullPath)))))

            case .cutSelectedItems:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                return .merge(
                    .send(.delegate(.intent(.copySelectedItems(files: selectedItems)))),
                    .send(.delegate(.intent(.setClipboardOperation(operation: .cut)))),
                )

            case let .pasteItems(destinationPath):
                return .send(.delegate(.intent(.pasteItemsFromClipboard(destinationPath: destinationPath))))

            case .duplicateSelectedItems:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }

                let parentPath = URL(fileURLWithPath: selectedItems[0].fullPath)
                    .deletingLastPathComponent().path

                return .send(.delegate(.intent(.pasteItems(
                    sourcePaths: selectedItems.map(\.fullPath),
                    destinationPath: parentPath,
                    operation: .copy,
                    actionKind: .duplicate,
                ))))

            case .createAliasForSelectedItems:
                let selectedItems = EntryReducerSupport.getSelectedItems(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )
                guard !selectedItems.isEmpty else {
                    return .none
                }
                return .send(.delegate(.intent(.createAliases(items: selectedItems))))

            default:
                return .none
            }
        }
    }
}
