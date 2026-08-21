import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
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
}
