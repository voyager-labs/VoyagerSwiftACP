import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
/// 윈도우 엔트리 조작 계약 — 기본 상태와 컬렉션 모드 인식 조작 동작을 검증.
final class FileManagerWindowEntryOpsContractTests: XCTestCase {
    /// testMakeInitialCreatesStateWithoutWindowID 테스트 동작을 검증한다.
    func testMakeInitialCreatesStateWithoutWindowID() {
        let state = FileManagerWindowState.makeInitial(path: nil)

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// testMakeInitialSeedsPathThroughNavigationState 테스트 동작을 검증한다.
    func testMakeInitialSeedsPathThroughNavigationState() {
        let path = "/Users/test/Documents"
        let state = FileManagerWindowState.makeInitial(path: path)

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// testContentStateCanSaveCollectionUsesLayoutIsCollectionMode 테스트 동작을 검증한다.
    func testContentStateCanSaveCollectionUsesLayoutIsCollectionMode() {
        var state = FileManagerWindowState()

        XCTAssertFalse(state.content.canSaveCollection)

        state.content.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])
        state.content.entryViewLayout.isCollectionMode = true

        XCTAssertTrue(state.content.canSaveCollection)
    }

    /// testWindowDefaultStateHasNoCollectionMode 테스트 동작을 검증한다.
    func testWindowDefaultStateHasNoCollectionMode() {
        let state = FileManagerWindowState()

        XCTAssertFalse(state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// testContentEntryOperationsResetClearsWindowID 테스트 동작을 검증한다.
    func testContentEntryOperationsResetClearsWindowID() {
        let windowID = UUID()
        var state = FileManagerWindowState.makeInitial(path: nil)
        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)

        state.content.entryViewLayout.entryOperations = EntryOperationsState()
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)

        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
    }
}
