import ComposableArchitecture
import Foundation
import IdentifiedCollections

@ObservableState
struct EntryState: Equatable {
    var items: IdentifiedArrayOf<Entry> = [] // Entry 상태인데 이게 필요할까? 이거는 더 상위 상태 아닌가?
    var collectionItems: IdentifiedArrayOf<Entry> = [] // Collection으로 빼야함
    var isCollectionMode: Bool = false // Collection으로 빼야함
    var selectedIds: Set<String> = [] // Entry 상태인데 이게 필요할까? 이거는 더 상위 상태 아닌가?
    var lastSelectedId: String? // Entry 상태인데 이게 필요할까? 이거는 더 상위 상태 아닌가?
    var rangeAnchorId: String? // 이거 뭔 상태임?
    var isLoading: Bool = false
    var isReloading: Bool = false
    var showHiddenFiles: Bool = false // 이거는 Content Pane의 상태 아닌가?
    var shouldScrollToSelection: Bool = false // 이거는 Content Pane의 상태 아닌가?

    var isDragDropOperation: Bool = false // 이건 왜 여기에 있어? 상위 상태인 것 같음
    var isDropTargeted: Bool = false

    var renamingItemId: String? // Id String이 아니라 Boolean 아닌가
    var renamingText: String = ""
    var creatingNewFolderId: String? // Entry 상태 아님. 이것도 상위 상태
    var creatingNewFolderPath: String? // Entry 상태 아님. 이것도 상위 상태
    var creatingNewFolderOriginalName: String? // Entry 상태 아님. 이것도 상위 상태
    var selectAfterLoadFileNames: [String] = [] // 이건 뭔상태야?

    var currentFolderPath: String? // 이건 Page 상태
    var isVirtualFolder: Bool = false // 이건 뭐야
    var gridColumnCount: Int = 1 // 이건 왜 여기에 있어? 더 상위 상태인 듯

    var isRenaming: Bool {
        renamingItemId != nil // 이렇게 Computed Property로 할필요 없음
    }

    var displayItems: IdentifiedArrayOf<Entry> {
        isCollectionMode ? collectionItems : items
    }

    var displayOrderItems: [Entry] {
        Array(displayItems)
    }

    mutating func clearSelection() { // Entry 상태가 아님. 더 상위 상태
        selectedIds = []
        lastSelectedId = nil
        rangeAnchorId = nil
    }

    mutating func clearRenaming() { // 이건 상태가 아님. 이펙트임
        renamingItemId = nil
        renamingText = ""
    }

    mutating func clearCreatingFolder() { // 이건 상태가 아님. 이펙트임
        creatingNewFolderId = nil
        creatingNewFolderPath = nil
        creatingNewFolderOriginalName = nil
    }
}
