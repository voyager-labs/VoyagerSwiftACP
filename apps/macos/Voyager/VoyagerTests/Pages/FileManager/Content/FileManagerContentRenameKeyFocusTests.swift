import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// 리스트 및 그리드 모드에서 키 커맨드 포커스 복원 정책을 테스트합니다.
///
/// 이 테스트는 이름 변경 액션의 리듀서 수준 키 커맨드 처리를 검증합니다.
/// XCTest에서는 뷰 레벨 포커스를 직접 검증할 수 없으므로 키 커맨드
/// 라우팅 로직이 리스트 및 그리드 레이아웃에서 올바르게 동작하는지 확인합니다.
@MainActor
final class FileManagerContentRenameKeyFocusTests: XCTestCase {
    // MARK: - 키 커맨드 포커스 복원 정책 테스트

    /// 선택 변경이 진행 중인 이름 변경 세션에 영향을 주지 않음을 검증합니다.
    /// renamingItemId가 non-nil일 때 키 커맨드 핸들러는 새 이름 변경을 시작하지 않아야 합니다.
    func testSelectionChangeDoesNotInterfereWithActiveRename() async {
        for layout in [EntryViewLayoutState.Mode.list, .grid] {
            for keyCode in [36, 76] { // Return 및 Keypad Enter
                let selected = makeEntry(name: "selected.txt", fullPath: "/tmp/voyager/selected.txt")

                var initialState = FileManagerContentState()
                initialState.entryViewLayout.mode = layout
                initialState.navigation.seedInitialFolderPath("/tmp/voyager")
                initialState.entryViewLayout.entries = [selected]
                initialState.entryViewLayout.entryOperations.items = [selected]
                initialState.entryViewLayout.selectedIds = [selected.id]
                // 활성 이름 변경 세션 시뮬레이션
                initialState.entryViewLayout.entryOperations.renamingItemId = selected.id

                let store = TestStore(initialState: initialState) {
                    FileManagerContentFeature()
                }

                // 활성 이름 변경 중 Return/Enter를 누르면 아무 일도 일어나지 않아야 함
                await store.send(.view(.handleKeyCommand(
                    KeyCommand(
                        keyCode: UInt16(keyCode),
                        modifiers: [],
                        characters: nil,
                        charactersIgnoringModifiers: nil,
                    ),
                )))
                await store.finish()
            }
        }
    }

    /// 리스트 모드에서 Return 및 Keypad Enter 키 명령이 이름 변경 경로에 도달하는지 검증합니다.
    /// 이 테스트는 리스트 레이아웃에서 리듀서 수준 처리가 제대로 작동함을 확인합니다.
    func testListModeReturnAndKeypadEnterReachRenamePath() async {
        for keyCode in [36, 76] { // Return 및 Keypad Enter
            let selected = makeEntry(name: "document", fullPath: "/tmp/voyager/document.txt", fileExtension: "txt")

            var initialState = FileManagerContentState()
            initialState.entryViewLayout.mode = .list
            initialState.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.entryViewLayout.entries = [selected]
            initialState.entryViewLayout.entryOperations.items = [selected]
            initialState.entryViewLayout.selectedIds = [selected.id]

            let store = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.handleKeyCommand(
                KeyCommand(keyCode: UInt16(keyCode), modifiers: [], characters: nil, charactersIgnoringModifiers: nil),
            )))

            await store.receive { action in
                guard case let .entryViewLayout(.delegate(.startRename(item, text))) = action else { return false }
                return item.id == selected.id && text == "document"
            }

            await store.finish()
        }
    }

    /// 그리드 모드에서 Return 및 Keypad Enter 키 명령이 이름 변경 경로에 도달하는지 검증합니다.
    /// 이 테스트는 그리드 레이아웃이 이전과 동일하게 계속 작동하는지 확인합니다.
    func testGridModeReturnAndKeypadEnterReachRenamePath() async {
        for keyCode in [36, 76] { // Return 및 Keypad Enter
            let selected = makeEntry(
                name: "spreadsheet",
                fullPath: "/tmp/voyager/spreadsheet.xlsx",
                fileExtension: "xlsx",
            )

            var initialState = FileManagerContentState()
            initialState.entryViewLayout.mode = .grid
            initialState.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.entryViewLayout.entries = [selected]
            initialState.entryViewLayout.entryOperations.items = [selected]
            initialState.entryViewLayout.selectedIds = [selected.id]

            let store = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.handleKeyCommand(
                KeyCommand(keyCode: UInt16(keyCode), modifiers: [], characters: nil, charactersIgnoringModifiers: nil),
            )))

            await store.receive { action in
                guard case let .entryViewLayout(.delegate(.startRename(item, text))) = action else { return false }
                return item.id == selected.id && text == "spreadsheet"
            }

            await store.finish()
        }
    }

    /// 진행 중인 이름 변경 상태에서 레이아웃 변경이 이름 변경을 취소하는지 검증합니다.
    /// 이를 통해 포커스 정책이 오래된 이름 변경 상태를 남기지 않음을 보장합니다.
    func testLayoutChangeDuringActiveRenameCancelsRename() async {
        let selected = makeEntry(name: "file.txt", fullPath: "/tmp/voyager/file.txt")

        var initialState = FileManagerContentState()
        initialState.entryViewLayout.mode = .list
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [selected]
        initialState.entryViewLayout.entryOperations.items = [selected]
        initialState.entryViewLayout.selectedIds = [selected.id]
        initialState.entryViewLayout.entryOperations.renamingItemId = selected.id

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.changeLayout(.grid)))

        // 레이아웃 변경이 활성 이름 변경을 취소해야 함
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.edit(.cancelRename))) = action else { return false }
            return true
        }

        await store.finish()
    }

    // MARK: - 도우미 메서드

    private func makeEntry(
        name: String,
        fullPath: String,
        isFolder: Bool = false,
        fileExtension: String? = nil,
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ext = fileExtension ?? (name.components(separatedBy: ".").last ?? "")
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: ext,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
