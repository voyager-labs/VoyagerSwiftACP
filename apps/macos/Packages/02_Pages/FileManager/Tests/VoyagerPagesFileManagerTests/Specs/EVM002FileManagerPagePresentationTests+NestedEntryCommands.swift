import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-nested_entry_commands

    /// EVM-002-nested_entry_commands: expanded child folder 선택의 open 명령은 nested entry를 navigation으로 전달한다.
    /// - 검증 내용: hierarchy outline projection이 nested folder를 command context에 포함한다.
    /// - 사전 조건: /root/folder가 expanded이고 /root/folder/child가 선택돼 있다.
    /// - 기대 결과: open command가 /root/folder/child navigation delegate를 발생시킨다.
    func testNestedFolderOpenCommandUsesHierarchySelectableEntries() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        let store = makeFileManagerContentFeatureStore(initialState: nestedCommandState(
            root: folder,
            child: child,
            selectedID: child.id,
        ))
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem"))))
        await store.receive(\.entryOperations.routing.executeCommand)
        await store.receive {
            guard case let .entryOperations(.delegate(.navigateToPath(path))) = $0 else {
                return false
            }
            return path == child.fullPath
        }
        await store.receive(\.internal.requestNavigation)
        await store.finish()
    }

    /// EVM-002-nested_entry_commands: expanded child file 선택의 Quick Look 명령은 nested path를 사용한다.
    /// - 검증 내용: hierarchy projection이 root entries에 없는 nested file을 command context에 제공한다.
    /// - 사전 조건: /root/folder가 expanded이고 /root/folder/file.txt가 선택돼 있다.
    /// - 기대 결과: Quick Look action이 nested file path 하나로 실행된다.
    func testNestedFileQuickLookCommandUsesHierarchySelectableEntries() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel(
            name: "file.txt",
            fullPath: "/root/folder/file.txt",
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
        let store = makeFileManagerContentFeatureStore(initialState: nestedCommandState(
            root: folder,
            child: child,
            selectedID: child.id,
        ))
        store.exhaustivity = .off // Quick Look success 후 root reload chain은 nested path routing 계약과 무관하다.

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem"))))
        await store.receive(\.entryOperations.routing.executeCommand)
        await store.receive {
            guard case let .entryOperations(.open(.quickLookFiles(paths))) = $0 else {
                return false
            }
            return paths == [child.fullPath]
        }
        await store.finish()
    }

    private func nestedCommandState(
        root: EntryModel,
        child: EntryModel,
        selectedID: EntryModel.ID,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [root]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [root.id],
            foldersByID: [
                root.id: .init(
                    children: [child],
                    phase: .loaded,
                    generation: 1,
                    expectedBatchIndex: 1,
                    coreFinished: true,
                ),
            ],
        )
        state.entryViewLayout.selectedIds = [selectedID]
        return state
    }
}
