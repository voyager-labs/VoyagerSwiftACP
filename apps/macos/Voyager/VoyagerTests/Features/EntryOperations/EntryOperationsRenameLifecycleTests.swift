import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryOperationsRenameLifecycleTests: XCTestCase {
    // MARK: - Test: itemsLoaded cancels rename when renaming item disappears

    func testItemsLoadedCancelsRenameWhenRenamingItemDisappears() async {
        // Setup: Create items with file1.txt and file2.txt
        let file1 = EntryModel.temporaryFolder(id: "/tmp/file1.txt", name: "file1.txt")
        let file2 = EntryModel.temporaryFolder(id: "/tmp/file2.txt", name: "file2.txt")

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            // User is renaming file2.txt
            state.renamingItemId = file2.id
            state.renamingText = "new_name.txt"
            // Initial items contain file2
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [file1, file2])
            return state
        }()) {
            EntryOperationsFeature()
        }

        // Action: itemsLoaded receives new items without file2 (it was deleted externally)
        let newItems = [file1] // file2 is missing

        await store.send(.loading(.itemsLoaded(newItems))) {
            // The items are updated
            $0.loadingContext.items = IdentifiedArrayOf(uniqueElements: newItems)
            $0.isLoading = false
            $0.isReloading = false
        }

        // Effect: cancelRename is triggered
        await store.receive(\.edit.cancelRename) {
            $0.renamingItemId = nil
            $0.renamingText = ""
        }

        await store.finish()
    }

    // MARK: - Test: itemsLoaded preserves rename when renaming item still exists

    func testItemsLoadedPreservesRenameWhenRenamingItemStillExists() async {
        // Setup: Create items with file1.txt and file2.txt
        let file1 = EntryModel.temporaryFolder(id: "/tmp/file1.txt", name: "file1.txt")
        let file2 = EntryModel.temporaryFolder(id: "/tmp/file2.txt", name: "file2.txt")
        let file3 = EntryModel.temporaryFolder(id: "/tmp/file3.txt", name: "file3.txt")

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            // User is renaming file2.txt
            state.renamingItemId = file2.id
            state.renamingText = "new_name.txt"
            // Initial items contain file2
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [file1, file2])
            return state
        }()) {
            EntryOperationsFeature()
        }

        // Action: itemsLoaded receives new items that still include file2
        let newItems = [file1, file2, file3]

        await store.send(.loading(.itemsLoaded(newItems))) {
            // The items are updated
            $0.loadingContext.items = IdentifiedArrayOf(uniqueElements: newItems)
            $0.isLoading = false
            $0.isReloading = false
        }

        // No cancelRename should be sent
        await store.finish()
    }
}
