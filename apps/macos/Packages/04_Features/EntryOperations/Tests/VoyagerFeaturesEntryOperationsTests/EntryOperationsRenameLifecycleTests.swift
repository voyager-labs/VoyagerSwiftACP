import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryOperationsRenameLifecycleTests: XCTestCase {
    // MARK: - 테스트: itemsLoaded가 이름 변경 중인 항목이 사라질 때 rename 취소

    func testItemsLoadedCancelsRenameWhenRenamingItemDisappears() async {
        // 설정: file1.txt와 file2.txt로 항목 생성
        let file1 = EntryModel.temporaryFolder(id: "/tmp/file1.txt", name: "file1.txt")
        let file2 = EntryModel.temporaryFolder(id: "/tmp/file2.txt", name: "file2.txt")

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            // 사용자가 file2.txt 이름을 변경 중
            state.renamingItemId = file2.id
            state.renamingText = "new_name.txt"
            // 초기 항목에 file2 포함
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [file1, file2])
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        // 액션: itemsLoaded가 file2 없이 새 항목을 받음 (외부에서 삭제됨)
        let newItems = [file1] // file2가 누락됨

        await store.send(.loading(.itemsLoaded(newItems))) {
            // 항목이 업데이트됨
            $0.loadingContext.items = IdentifiedArrayOf(uniqueElements: newItems)
            $0.isLoading = false
            $0.isReloading = false
        }

        // 효과: cancelRename이 트리거됨
        await store.receive(\.edit.cancelRename) {
            $0.renamingItemId = nil
            $0.renamingText = ""
        }

        await store.finish()
    }

    // MARK: - 테스트: 이름 변경 중 항목이 여전히 존재할 때 itemsLoaded가 rename 유지

    func testItemsLoadedPreservesRenameWhenRenamingItemStillExists() async {
        // 설정: file1.txt와 file2.txt로 항목 생성
        let file1 = EntryModel.temporaryFolder(id: "/tmp/file1.txt", name: "file1.txt")
        let file2 = EntryModel.temporaryFolder(id: "/tmp/file2.txt", name: "file2.txt")
        let file3 = EntryModel.temporaryFolder(id: "/tmp/file3.txt", name: "file3.txt")

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            // 사용자가 file2.txt 이름을 변경 중
            state.renamingItemId = file2.id
            state.renamingText = "new_name.txt"
            // 초기 항목에 file2 포함
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [file1, file2])
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        // 액션: itemsLoaded가 file2를 여전히 포함한 새 항목을 받음
        let newItems = [file1, file2, file3]

        await store.send(.loading(.itemsLoaded(newItems))) {
            // 항목이 업데이트됨
            $0.loadingContext.items = IdentifiedArrayOf(uniqueElements: newItems)
            $0.isLoading = false
            $0.isReloading = false
        }

        // cancelRename이 전송되지 않아야 함
        await store.finish()
    }
}
