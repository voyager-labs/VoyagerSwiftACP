import ComposableArchitecture
import Foundation
import IdentifiedCollections

enum EntryContextMenuUtils {
    static func sendWithSelection(
        _ item: Entry,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        action: @escaping () -> Void,
    ) {
        if !fsStore.selectedIds.contains(item.id) {
            fsStore.send(.selectItem(id: item.id, isCommandPressed: false, isShiftPressed: false))
        }
        action()
    }

    static func calculateCompressExtractOptions(
        selectedItems: IdentifiedArrayOf<Entry>,
    ) -> (showCompress: Bool, showExtract: Bool) {
        let containsZipFiles = selectedItems.contains { $0.fileExtension.lowercased() == "zip" }
        let containsNonZipFiles = selectedItems.contains { $0.fileExtension.lowercased() != "zip" }

        let showCompress = !containsZipFiles
        let showExtract = containsZipFiles && !containsNonZipFiles

        return (showCompress, showExtract)
    }
}
