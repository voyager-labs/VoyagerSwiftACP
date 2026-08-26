import AppKit
import ComposableArchitecture
import Foundation
import PerceptionCore
import SwiftUI
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-type_scroll_input

    /// EVM-002-type_scroll_input: 커밋된 타자 입력은 표시 순서상 첫 매칭 엔트리로 type-scroll 타깃을 설정한다.
    /// 한글 입력 "가"가 이름이 "가"로 시작하는 엔트리의 setTypeScrollTarget으로 라우팅되는지 검증한다.
    /// - 검증 내용: .view(.handleTextInput("가"))가 첫 매칭 id의 setTypeScrollTarget을 발행한다.
    /// - 사전 조건: /root 폴더 페이지, "가나다"·"바나나" 엔트리
    /// - 기대 결과: setTypeScrollTarget("가나다") 수신
    func testHandleTextInputKoreanMatchesFirstEntry() async {
        let first = EntryModel.temporaryFolder(id: "/root/가나다", name: "가나다")
        let second = EntryModel.temporaryFolder(id: "/root/바나나", name: "바나나")
        let store = makeTypeScrollStore(entries: [first, second])

        await store.send(.view(.handleTextInput("가")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == first.id
        }
    }

    /// EVM-002-type_scroll_input: 표시 순서상 첫 매칭 엔트리가 선택된다.
    /// [Beta, Alpha, Charlie] 순서에서 "A"는 Alpha가 아니라 visible 순서 기준 첫 매칭인 Beta를 선택하지 않고
    /// 실제 "A"로 시작하는 첫 엔트리 Alpha를 선택한다.
    /// - 검증 내용: 입력 "A"가 visible 순서에서 이름이 A로 시작하는 첫 엔트리 id를 타깃으로 한다.
    /// - 사전 조건: /root 폴더 페이지, [Beta, Alpha, Charlie]
    /// - 기대 결과: setTypeScrollTarget(Alpha) 수신
    func testHandleTextInputSelectsFirstVisibleMatch() async {
        let beta = EntryModel.temporaryFolder(id: "/root/beta", name: "Beta")
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        let charlie = EntryModel.temporaryFolder(id: "/root/charlie", name: "Charlie")
        let store = makeTypeScrollStore(entries: [beta, alpha, charlie])

        await store.send(.view(.handleTextInput("A")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == alpha.id
        }
    }

    /// EVM-002-type_scroll_input: 발음구별부호·대소문자 정규화로 매칭한다.
    /// 입력 "é"가 이름이 "Été"로 시작하는 엔트리와 정규화 동등하게 매칭되는지 검증한다.
    /// - 검증 내용: diacritic/case folding 후 "é"가 "Été" 엔트리와 매칭된다.
    /// - 사전 조건: /root 폴더 페이지, "Été" 엔트리
    /// - 기대 결과: setTypeScrollTarget("Été") 수신
    func testHandleTextInputNormalizesDiacritics() async {
        let ete = EntryModel.temporaryFolder(id: "/root/ete", name: "Été")
        let store = makeTypeScrollStore(entries: [ete])

        await store.send(.view(.handleTextInput("é")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == ete.id
        }
    }

    /// EVM-002-type_scroll_input: 유효하지 않은 타자 입력은 type-scroll을 발행하지 않는다.
    /// 빈 문자열·다중 그래핌·공백은 no-op여야 한다.
    /// - 검증 내용: 각 no-op 입력이 setTypeScrollTarget을 발행하지 않는다.
    /// - 사전 조건: /root 폴더 페이지, 이름이 있는 엔트리
    /// - 기대 결과: 수신 액션 없음
    func testHandleTextInputNoOpForInvalidInputs() async {
        let entry = EntryModel.temporaryFolder(id: "/root/file", name: "file")
        let store = makeTypeScrollStore(entries: [entry])
        store.exhaustivity = .off

        for invalid in ["", "ab", "가나", " "] {
            await store.send(.view(.handleTextInput(invalid)))
        }
    }

    /// EVM-002-type_scroll_input: 매칭되는 엔트리가 없으면 type-scroll을 발행하지 않는다.
    /// - 검증 내용: 입력 "z"가 이름이 z로 시작하지 않는 엔트리 목록에서 no-op이다.
    /// - 사전 조건: /root 폴더 페이지, [Alpha, Beta]
    /// - 기대 결과: 수신 액션 없음
    func testHandleTextInputNoMatchEmitsNothing() async {
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        let beta = EntryModel.temporaryFolder(id: "/root/beta", name: "Beta")
        let store = makeTypeScrollStore(entries: [alpha, beta])
        store.exhaustivity = .off

        await store.send(.view(.handleTextInput("z")))
    }

    /// EVM-002-type_scroll_input: collection replacement loading 중 기존 pending target이 있어도
    /// 이후 유효한 unmatched 입력이 최신 의도가 되므로 stale target을 reset한다.
    /// - 사전 조건: collection replacement loading으로 List/Grid가 unmount됐고 Alpha target이 pending이다.
    /// - 기대 결과: 입력 "z"가 resetTypeScrollTarget을 발행해 pending target을 nil로 만든다.
    func testHandleTextInputUnmatchedResetsPendingTargetDuringCollectionReplacementLoading() async {
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [alpha]
        state.entryViewLayout.selectedIds = [alpha.id]
        state.entryViewLayout.pendingTypeScrollTargetId = alpha.id
        state.entryViewLayout.isCollectionMode = true
        state.entryViewLayout.isCollectionContentLoading = true
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        XCTAssertEqual(
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: false,
                isCollectionContentLoading: true,
                isEntryLoading: false,
                isCollectionMode: true,
            ),
            .collectionReplacementLoading,
        )
        XCTAssertTrue(ContentPagePresentationPolicy.collectionReplacementLoading.allowsKeyboardCommandDispatch)

        await store.send(.view(.handleTextInput("z")))
        await store.receive {
            guard case .entryViewLayout(.view(.resetTypeScrollTarget)) = $0 else { return false }
            return true
        }
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [alpha.id])
    }

    /// EVM-002-type_scroll_input: 기존 pending target 뒤의 matched 입력은 최신 matching target으로 교체한다.
    /// - 사전 조건: Alpha target이 pending이고 visible entries에 Beta가 있다.
    /// - 기대 결과: 입력 "b"가 setTypeScrollTarget(Beta)를 발행하고 selection은 유지된다.
    func testHandleTextInputMatchedReplacesExistingPendingTarget() async {
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        let beta = EntryModel.temporaryFolder(id: "/root/beta", name: "Beta")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [alpha, beta]
        state.entryViewLayout.selectedIds = [alpha.id]
        state.entryViewLayout.pendingTypeScrollTargetId = alpha.id
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleTextInput("b")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == beta.id
        }
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [alpha.id])
    }

    /// EVM-002-type_scroll_input: invalid/non-printable 입력은 기존 pending target을 보존한다.
    func testHandleTextInputInvalidPreservesExistingPendingTarget() async {
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [alpha]
        state.entryViewLayout.pendingTypeScrollTargetId = alpha.id
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleTextInput(" ")))

        XCTAssertEqual(store.state.entryViewLayout.pendingTypeScrollTargetId, alpha.id)
    }

    /// EVM-002-type_scroll_input: app shortcut은 type-scroll pending target을 변경하지 않는다.
    func testHandleAppShortcutPreservesExistingPendingTypeScrollTarget() async {
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [alpha]
        state.entryViewLayout.pendingTypeScrollTargetId = alpha.id
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 8,
            modifiers: [.command],
            characters: "c",
            charactersIgnoringModifiers: "c",
        ))))
        await store.receive {
            guard case .entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedItems"))) = $0 else {
                return false
            }
            return true
        }
        XCTAssertEqual(store.state.entryViewLayout.pendingTypeScrollTargetId, alpha.id)
    }

    /// EVM-002-type_scroll_input: context-changing modifier commands는 marked text 취소 정책을 반환한다.
    /// open, delete, paste, duplicate, visibility reload, undo/redo의 공통 composition invalidation을 검증한다.
    /// - 검증 내용: 선택이 있는 상태에서 각 KeyCommand의 typed composition policy.
    /// - 사전 조건: 일반 폴더 페이지에 선택된 엔트리가 있고 composer가 닫혀 있다.
    /// - 기대 결과: 모든 context-changing command가 `.cancelMarkedText`를 반환한다.
    func testContextChangingModifierCommandsCancelMarkedText() {
        let selected = EntryModel.temporaryFolder(id: "/root/selected", name: "selected")
        var state = FileManagerContentState()
        state.entryViewLayout.entries = [selected]
        state.entryViewLayout.selectedIds = [selected.id]
        let commands: [KeyCommand] = [
            .init(keyCode: 125, modifiers: [.command], characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}"),
            .init(keyCode: 51, modifiers: [.command], characters: "\u{007F}", charactersIgnoringModifiers: "\u{007F}"),
            .init(
                keyCode: 51,
                modifiers: [.command, .option],
                characters: "\u{007F}",
                charactersIgnoringModifiers: "\u{007F}",
            ),
            .init(keyCode: 47, modifiers: [.command, .shift], characters: ".", charactersIgnoringModifiers: "."),
            .init(keyCode: 9, modifiers: [.command], characters: "v", charactersIgnoringModifiers: "v"),
            .init(keyCode: 2, modifiers: [.command], characters: "d", charactersIgnoringModifiers: "d"),
            .init(keyCode: 6, modifiers: [.command], characters: "z", charactersIgnoringModifiers: "z"),
            .init(keyCode: 6, modifiers: [.command, .shift], characters: "Z", charactersIgnoringModifiers: "z"),
        ]

        for command in commands {
            XCTAssertEqual(
                FileManagerContentKeyCommandHandler.compositionPolicy(for: command, state: state),
                .cancelMarkedText,
            )
        }
    }

    /// EVM-002-type_scroll_input: non-mutating, unhandled, 실행 불가능한 modifier command는 marked text를 보존한다.
    /// copy/cut, Control-only, 알 수 없는 Command와 선택 없는 mutation command의 명시적 경계를 검증한다.
    /// - 검증 내용: 각 KeyCommand와 state 조합의 typed composition policy.
    /// - 사전 조건: 선택 유무와 composer 표시 상태를 command 의미에 맞게 구성한다.
    /// - 기대 결과: 실제 context mutation이 없는 모든 경로가 `.preserveMarkedText`를 반환한다.
    func testNonMutatingUnhandledAndUnavailableCommandsPreserveMarkedText() {
        let selected = EntryModel.temporaryFolder(id: "/root/selected", name: "selected")
        var selectedState = FileManagerContentState()
        selectedState.entryViewLayout.entries = [selected]
        selectedState.entryViewLayout.selectedIds = [selected.id]
        let preservingCommands: [KeyCommand] = [
            .init(keyCode: 8, modifiers: [.command], characters: "c", charactersIgnoringModifiers: "c"),
            .init(keyCode: 7, modifiers: [.command], characters: "x", charactersIgnoringModifiers: "x"),
            .init(keyCode: 12, modifiers: [.command], characters: "q", charactersIgnoringModifiers: "q"),
            .init(keyCode: 12, modifiers: [.control], characters: "q", charactersIgnoringModifiers: "q"),
        ]

        for command in preservingCommands {
            XCTAssertEqual(
                FileManagerContentKeyCommandHandler.compositionPolicy(for: command, state: selectedState),
                .preserveMarkedText,
            )
        }

        let emptySelectionState = FileManagerContentState()
        for command in [
            KeyCommand(
                keyCode: 125,
                modifiers: [.command],
                characters: "\u{F701}",
                charactersIgnoringModifiers: "\u{F701}",
            ),
            KeyCommand(
                keyCode: 51,
                modifiers: [.command],
                characters: "\u{007F}",
                charactersIgnoringModifiers: "\u{007F}",
            ),
            KeyCommand(keyCode: 2, modifiers: [.command], characters: "d", charactersIgnoringModifiers: "d"),
        ] {
            XCTAssertEqual(
                FileManagerContentKeyCommandHandler.compositionPolicy(for: command, state: emptySelectionState),
                .preserveMarkedText,
            )
        }

        var composerState = selectedState
        composerState.composer.isPresented = true
        XCTAssertEqual(
            FileManagerContentKeyCommandHandler.compositionPolicy(
                for: .init(keyCode: 6, modifiers: [.command], characters: "z", charactersIgnoringModifiers: "z"),
                state: composerState,
            ),
            .preserveMarkedText,
        )
    }

    /// EVM-002-type_scroll_input: 엔트리가 없으면 type-scroll을 발행하지 않는다.
    /// - 검증 내용: 빈 엔트리 목록에서 유효한 입력도 no-op이다.
    /// - 사전 조건: /root 폴더 페이지, 엔트리 없음
    /// - 기대 결과: 수신 액션 없음
    func testHandleTextInputEmptyEntriesEmitsNothing() async {
        let store = makeTypeScrollStore(entries: [])
        store.exhaustivity = .off

        await store.send(.view(.handleTextInput("a")))
    }

    /// EVM-002-type_scroll_input: rename 진행 중에는 type-scroll이 비활성화된다.
    /// rename이 우선권을 가지므로 renamingItemId가 설정되면 타자 입력을 무시한다.
    /// - 검증 내용: renamingItemId가 있는 상태에서 유효 입력 "a"가 no-op이다.
    /// - 사전 조건: /root 폴더 페이지, 매칭 엔트리 존재, renamingItemId 설정
    /// - 기대 결과: 수신 액션 없음
    func testHandleTextInputDisabledWhileRenaming() async {
        let alpha = EntryModel.temporaryFolder(id: "/root/alpha", name: "Alpha")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [alpha]
        state.entryViewLayout.entryOperations.renamingItemId = alpha.id
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }
        store.exhaustivity = .off

        await store.send(.view(.handleTextInput("a")))
    }

    /// EVM-002-type_scroll_input: collapsed group에 숨겨진 첫 매칭이 later visible 매칭을 막지 않는다.
    /// grouping 활성 + 그룹 "A"(collapsed, "Alices" 보유) + 그룹 "B"(expanded, "Aaron" 보유)에서
    /// 입력 "A"는 숨겨진 "Alices"가 아니라 visible한 "Aaron"을 type-scroll 타깃으로 삼아야 한다.
    /// - 사전 조건: /root 폴더 페이지, Name grouping 활성, "A" 그룹 collapsed
    /// - 기대 결과: setTypeScrollTarget(Aaron)
    func testHandleTextInputSkipsHiddenEntryInCollapsedGroup() async {
        let alices = EntryModel.temporaryFolder(id: "/root/alices", name: "Alices")
        let aaron = EntryModel.temporaryFolder(id: "/root/aaron", name: "Aaron")
        let store = makeGroupedTypeScrollStore(
            entries: [alices, aaron],
            groupedItems: [
                GroupedItems(groupName: "A", items: [alices]),
                GroupedItems(groupName: "B", items: [aaron]),
            ],
            collapsedGroups: ["A"],
        )

        await store.send(.view(.handleTextInput("A")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == aaron.id
        }
    }

    /// EVM-002-type_scroll_input: collapsed group의 hidden first match는 later visible match 도달을 막지 않는다.
    /// 위 시나리오에서 첫 매칭 후보("Alices")가 hidden이므로 visible한 "Aaron"이 타깃이 되어야 한다.
    /// - 사전 조건: /root 폴더 페이지, Name grouping 활성, "A" 그룹 collapsed
    /// - 기대 결과: setTypeScrollTarget(Aaron)
    func testHandleTextInputHiddenFirstMatchDoesNotBlockLaterVisibleMatch() async {
        let alices = EntryModel.temporaryFolder(id: "/root/alices", name: "Alices")
        let aaron = EntryModel.temporaryFolder(id: "/root/aaron", name: "Aaron")
        let store = makeGroupedTypeScrollStore(
            entries: [alices, aaron],
            groupedItems: [
                GroupedItems(groupName: "A", items: [alices]),
                GroupedItems(groupName: "B", items: [aaron]),
            ],
            collapsedGroups: ["A"],
        )

        await store.send(.view(.handleTextInput("A")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == aaron.id
        }
    }

    /// EVM-002-type_scroll_input: hierarchy(list) 모드에서는 outline projection의 visible selectable entries를 사용한다.
    /// expanded folder의 visible child가 입력과 매칭되면 그 child를 타깃으로 삼는다 (hierarchy 모드 비회귀).
    /// - 사전 조건: /root 폴더 페이지, list 모드, rootPath 설정, "Docs" folder expanded, "Alpha.txt" visible child
    /// - 기대 결과: setTypeScrollTarget(Alpha.txt)
    func testHandleTextInputUsesOutlineProjectionInHierarchyMode() async {
        let docs = EntryModel.temporaryFolder(id: "/root/docs", name: "Docs")
        let alphaChild = makeTypeScrollHierarchyFile(id: "/root/docs/alpha.txt", name: "Alpha.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [docs]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [
                docs.id: FolderNodeState(
                    children: [alphaChild],
                    loadPhase: .loaded,
                    generation: 1,
                    coreFinished: true,
                ),
            ],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([docs.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleTextInput("A")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == alphaChild.id
        }
    }

    /// EVM-002-type_scroll_input: 두 expanded group 중 첫 group의 matching entry를 타깃으로 삼는다.
    /// group 순서를 보존한 visible entries에서 첫 매칭이 선택된다.
    /// - 사전 조건: /root 폴더 페이지, Name grouping 활성, 그룹 "A"/"B" 모두 expanded
    /// - 기대 결과: setTypeScrollTarget(그룹 "A"의 "Anna")
    func testHandleTextInputUsesGroupedVisibleOrdering() async {
        let anna = EntryModel.temporaryFolder(id: "/root/anna", name: "Anna")
        let avery = EntryModel.temporaryFolder(id: "/root/avery", name: "Avery")
        let store = makeGroupedTypeScrollStore(
            entries: [anna, avery],
            groupedItems: [
                GroupedItems(groupName: "A", items: [anna]),
                GroupedItems(groupName: "B", items: [avery]),
            ],
            collapsedGroups: [],
        )

        await store.send(.view(.handleTextInput("A")))
        await store.receive {
            guard case let .entryViewLayout(.view(.setTypeScrollTarget(id))) = $0 else { return false }
            return id == anna.id
        }
    }

    /// type-scroll 테스트 전용 store: /root 폴더 페이지에 엔트리를 세팅한다.
    @MainActor
    private func makeTypeScrollStore(
        entries: [EntryModel],
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = entries
        return TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }
    }

    /// type-scroll 테스트 전용 grouped store: /root 폴더 페이지에 grouping 활성 상태로 세팅한다.
    @MainActor
    private func makeGroupedTypeScrollStore(
        entries: [EntryModel],
        groupedItems: [GroupedItems],
        collapsedGroups: Set<String>,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = entries
        state.entryViewLayout.entryArrangements.groupKey = .name
        state.entryViewLayout.entryArrangements.groupedItems = groupedItems
        state.entryViewLayout.entryArrangements.collapsedGroups = collapsedGroups
        return TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }
    }

    /// hierarchy type-scroll 테스트용 file entry: 임의 파일을 만든다.
    @MainActor
    private func makeTypeScrollHierarchyFile(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    /// EVM-002-type_scroll_input: marked 상태의 Cmd+Down open은 조합을 취소한다.
    func testMountedMarkedCommandDownCancelsCompositionBeforeOpen() async {
        let perceptionCheckingWasEnabled = disableTypeScrollPerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let target = EntryModel.temporaryFolder(id: "/root/가나다", name: "가나다")
        let fixture = await makeMountedTypeScrollFixture(entries: [target])
        guard let host = await activateTypeScrollHost(fixture) else {
            return XCTFail("Expected registered KeyCommandHostingView as first responder")
        }
        host.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        host.keyDown(with: makeTypeScrollKeyDown(
            keyCode: 125,
            characters: "\u{F701}",
            modifiers: [.command],
        ))
        await drainTypeScrollFocusUpdates()

        XCTAssertEqual(fixture.routedCommands(), ["navigation.openSelectedItem"])
        XCTAssertFalse(host.hasMarkedText())
        XCTAssertEqual(host.markedRange(), NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(host.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertNil(fixture.store.state.entryViewLayout.pendingTypeScrollTargetId)

        host.unmarkText()
        host.keyDown(with: makeTypeScrollKeyDown(keyCode: 49, characters: " "))
        host.keyDown(with: makeTypeScrollKeyDown(keyCode: 36, characters: "\r"))
        host.keyDown(with: makeTypeScrollKeyDown(keyCode: 125, characters: "\u{F701}"))
        await drainTypeScrollFocusUpdates()

        XCTAssertNil(fixture.store.state.entryViewLayout.pendingTypeScrollTargetId)
        XCTAssertEqual(
            fixture.routedCommands(),
            ["navigation.openSelectedItem", "navigation.quickLookSelectedItem", "rename", "selection"],
        )
    }

    /// EVM-002-type_scroll_input: marked 상태의 Cmd+Delete mutation은 조합을 취소한다.
    func testMountedMarkedCommandDeleteCancelsCompositionBeforeMutation() async {
        let perceptionCheckingWasEnabled = disableTypeScrollPerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let target = EntryModel.temporaryFolder(id: "/root/가나다", name: "가나다")
        let fixture = await makeMountedTypeScrollFixture(entries: [target])
        guard let host = await activateTypeScrollHost(fixture) else {
            return XCTFail("Expected registered KeyCommandHostingView as first responder")
        }
        host.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        host.keyDown(with: makeTypeScrollKeyDown(
            keyCode: 51,
            characters: "\u{007F}",
            modifiers: [.command],
        ))
        await drainTypeScrollFocusUpdates()

        XCTAssertEqual(fixture.routedCommands(), ["mutation.moveSelectedItemsToTrash"])
        XCTAssertFalse(host.hasMarkedText())
        XCTAssertEqual(host.markedRange(), NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(host.selectedRange(), NSRange(location: 0, length: 0))

        host.unmarkText()
        await drainTypeScrollFocusUpdates()
        XCTAssertNil(fixture.store.state.entryViewLayout.pendingTypeScrollTargetId)
    }

    /// EVM-002-type_scroll_input: copy와 unhandled Control shortcut은 marked state를 보존한다.
    func testMountedNonMutatingAndUnhandledShortcutsPreserveComposition() async {
        let perceptionCheckingWasEnabled = disableTypeScrollPerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let target = EntryModel.temporaryFolder(id: "/root/가나다", name: "가나다")
        let fixture = await makeMountedTypeScrollFixture(entries: [target])
        guard let host = await activateTypeScrollHost(fixture) else {
            return XCTFail("Expected registered KeyCommandHostingView as first responder")
        }
        host.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        host.keyDown(with: makeTypeScrollKeyDown(keyCode: 8, characters: "c", modifiers: [.command]))
        host.keyDown(with: makeTypeScrollKeyDown(keyCode: 12, characters: "q", modifiers: [.control]))
        await drainTypeScrollFocusUpdates()

        XCTAssertEqual(fixture.routedCommands(), ["clipboard.copySelectedItems"])
        XCTAssertTrue(host.hasMarkedText())
        XCTAssertEqual(host.markedRange(), NSRange(location: 0, length: 1))
        XCTAssertEqual(host.selectedRange(), NSRange(location: 0, length: 1))
        host.doCommandBy(#selector(NSResponder.cancelOperation(_:)))
    }

    private func makeMountedTypeScrollFixture(entries: [EntryModel]) async -> MountedTypeScrollFixture {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/root")
        initialState.entryViewLayout.entries = entries
        let routedCommands = LockIsolated<[String]>([])
        let store: Store<FileManagerContentState, FileManagerContentAction> = Store(
            initialState: initialState,
        ) {
            Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                switch action {
                case .view(.selectAllEntries):
                    state.entryViewLayout.selectedIds = Set(entries.map(\.id))
                case let .entryViewLayout(.delegate(.executeCommand(command))):
                    routedCommands.withValue { $0.append(command) }
                case .entryViewLayout(.delegate(.startRename)):
                    routedCommands.withValue { $0.append("rename") }
                case .entryViewLayout(.internal(.applySelectionOffset)):
                    routedCommands.withValue { $0.append("selection") }
                default:
                    break
                }
                return .none
            }
            FileManagerContentKeyCommandReducer()
            Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
                EntryViewLayoutFeature()
            }
        }
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        let hostingController = NSHostingController(
            rootView: ContentPageView(store: store)
                .environment(\.fileManagerKeyCommandFocusCoordinator, coordinator),
        )
        let containerController = NSViewController()
        containerController.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        containerController.addChild(hostingController)
        hostingController.view.frame = containerController.view.bounds
        containerController.view.addSubview(hostingController.view)
        let window = NSWindow(contentViewController: containerController)
        window.makeKey()
        await drainTypeScrollFocusUpdates()
        return MountedTypeScrollFixture(window: window, store: store, routedCommands: { routedCommands.value })
    }

    private func activateTypeScrollHost(_ fixture: MountedTypeScrollFixture) async -> KeyCommandHostingView? {
        let nonTextResponder = KeyCommandHostingView()
        fixture.window.contentView?.addSubview(nonTextResponder)
        guard fixture.window.makeFirstResponder(nonTextResponder) else { return nil }
        fixture.store.send(.view(.selectAllEntries))
        await drainTypeScrollFocusUpdates()
        guard let host = fixture.window.firstResponder as? KeyCommandHostingView, host !== nonTextResponder else {
            return nil
        }
        return host
    }

    private func makeTypeScrollKeyDown(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode,
        ) else {
            preconditionFailure("keyDown 이벤트 생성 실패")
        }
        return event
    }

    private func disableTypeScrollPerceptionChecking() -> Bool {
        let wasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        return wasEnabled
    }

    private func drainTypeScrollFocusUpdates() async {
        for _ in 0 ..< 8 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
            await Task.yield()
        }
    }
}

private struct MountedTypeScrollFixture {
    let window: NSWindow
    let store: Store<FileManagerContentState, FileManagerContentAction>
    let routedCommands: () -> [String]
}
