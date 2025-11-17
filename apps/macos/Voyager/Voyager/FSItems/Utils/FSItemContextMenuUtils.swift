import ComposableArchitecture
import Foundation
import IdentifiedCollections

enum FSItemContextMenuUtils {
    static func sendWithSelection(
        _ item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        action: @escaping () -> Void
    ) {
        if !fsStore.selectedIds.contains(item.id) {
            fsStore.send(.selectItem(id: item.id, isCommandPressed: false, isShiftPressed: false))
        }
        action()
    }

    static func calculateCompressExtractOptions(
        selectedItems: IdentifiedArrayOf<FSItem>
    ) -> (showCompress: Bool, showExtract: Bool) {
        let containsZipFiles = selectedItems.contains { $0.fileExtension.lowercased() == "zip" }
        let containsNonZipFiles = selectedItems.contains { $0.fileExtension.lowercased() != "zip" }

        let showCompress = !containsZipFiles
        let showExtract = containsZipFiles && !containsNonZipFiles

        return (showCompress, showExtract)
    }
}
