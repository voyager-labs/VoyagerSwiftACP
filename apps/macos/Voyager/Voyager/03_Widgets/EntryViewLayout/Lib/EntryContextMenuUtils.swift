import ComposableArchitecture
import Foundation
import IdentifiedCollections

enum EntryContextMenuUtils {
    static func sendWithSelection(
        _ item: EntryModel,
        selectedIds: Set<String>,
        contentStore: StoreOf<FileManagerContentFeature>,
        action: @escaping () -> Void,
    ) {
        if !selectedIds.contains(item.id) {
            contentStore.send(.entryViewLayout(.setSelectedIds(ids: [item.id], lastSelectedId: item.id)))
        }
        action()
    }

    static func calculateCompressExtractOptions(
        selectedItems: IdentifiedArrayOf<EntryModel>,
    ) -> (showCompress: Bool, showExtract: Bool) {
        let containsZipFiles = selectedItems.contains { $0.fileExtension.lowercased() == "zip" }
        let containsNonZipFiles = selectedItems.contains { $0.fileExtension.lowercased() != "zip" }

        let showCompress = !containsZipFiles
        let showExtract = containsZipFiles && !containsNonZipFiles

        return (showCompress, showExtract)
    }
}
