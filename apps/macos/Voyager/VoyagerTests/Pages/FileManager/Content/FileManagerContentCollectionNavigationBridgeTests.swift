import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class ContentCollectionNavBridgeTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

    // MARK: - Non-Collection Navigation: clearCollectionPresentation + Load

    /// testFolderNavigationSendsClearCollectionPresentationThenLoadItems 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFolderNavigationSendsClearCollectionPresentationThenLoadItems() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder("/tmp/voyager")))) {
            $0.entryViewLayout.currentPath = "/tmp/voyager"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden)))) = action
            else { return false }
            return path == "/tmp/voyager" && showHidden == false
        }
    }

    /// testRecentsNavigationSendsClearCollectionPresentationThenLoadRecents 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRecentsNavigationSendsClearCollectionPresentationThenLoadRecents() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.recents))) {
            $0.entryViewLayout.currentPath = "Recents"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden)))) = action
            else { return false }
            return showHidden == false
        }
    }

    /// testTagsNavigationSendsClearCollectionPresentationThenLoadTagItems 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testTagsNavigationSendsClearCollectionPresentationThenLoadTagItems() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.tags("Work")))) {
            $0.entryViewLayout.currentPath = "Work"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadTagItems(tagName, showHidden)))) = action
            else { return false }
            return tagName == "Work" && showHidden == false
        }
    }

    /// testComputerNavigationSendsClearCollectionPresentationThenLoadComputerItems 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testComputerNavigationSendsClearCollectionPresentationThenLoadComputerItems() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.computer))) {
            $0.entryViewLayout.currentPath = ""
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadComputerItems))) = action else { return false }
            return true
        }
    }

    // MARK: - 컬렉션 내비게이션: setCollectionMode만

    /// testCollectionNavigationSendsSetCollectionModeTrueOnly 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testCollectionNavigationSendsSetCollectionModeTrueOnly() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        let collectionNavigation = ContentPageCollectionNavigation(
            kind: .temporary,
            context: CollectionContext(query: "test", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        )

        await store.send(.internal(.applyNavigationState(.collection(collectionNavigation)))) {
            $0.entryViewLayout.currentPath = "New Collection"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.setCollectionMode(true))) = action else { return false }
            return true
        }
    }

    // MARK: - handleEntryOperationsAction: 로딩 액션에 대해 None 반환

    /// testItemsLoadedReturnsNoneFromPageLevelHandler 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testItemsLoadedReturnsNoneFromPageLevelHandler() async {
        let store = TestStore(initialState: EntryOperationsBridgeHarness.State(content: .init())) {
            EntryOperationsBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(EntryOperationsBridgeHarness.Action.bridge(.loading(.itemsLoaded([]))))
        await store.finish()
    }

    // MARK: - operationFinished: 리로드만, 재적용 없음

    /// testOperationFinishedTriggersReloadWithoutReapply 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testOperationFinishedTriggersReloadWithoutReapply() async {
        var initialState = EntryOperationsBridgeHarness.State(content: .init())
        initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.content.navigation.navigationState = .folder("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            EntryOperationsBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(EntryOperationsBridgeHarness.Action.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager",
            OperationKind.rename,
            Result<Void, FileOpError>.success(()),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden))))) =
                action else { return false }
            return path == "/tmp/voyager" && showHidden == false
        }
        await store.finish()
    }

    // MARK: - makeEntryOperationsCommandContext: entryViewLayout.entries 사용

    /// testCommandContextUsesEntryViewLayoutEntries 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testCommandContextUsesEntryViewLayoutEntries() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/file.txt", name: "file.txt")
        var state = makeInitialState()
        state.entryViewLayout.entries = [entry]
        state.entryViewLayout.selectedIds = [entry.id]

        let context = reducer.makeEntryOperationsCommandContext(state: state)

        XCTAssertEqual(
            context.displayItems.map(\.id),
            [entry.id],
            "makeEntryOperationsCommandContext must read displayItems from entryViewLayout.entries",
        )
        XCTAssertEqual(context.selectedIds, [entry.id])
    }

    // MARK: - 도우미 메서드

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }
}

// MARK: - Test Harnesses

@MainActor
private struct EntryOperationsBridgeHarness: Reducer {
    @MainActor
    struct State: Equatable {
        var content: FileManagerContentState
    }

    enum Action: Sendable {
        case bridge(EntryOperationsAction)
        case forwarded(FileManagerContentAction)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .bridge(entryAction):
                FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                    entryAction,
                    state: &state.content,
                )
                .map(Action.forwarded)
            case .forwarded:
                .none
            }
        }
    }
}
