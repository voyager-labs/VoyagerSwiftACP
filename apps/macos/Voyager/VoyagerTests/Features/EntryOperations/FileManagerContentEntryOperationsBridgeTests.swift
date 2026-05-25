import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
/// 콘텐츠 엔트리 조작 브릿지 — 컬렉션 모드 및 저장 자격 조건 판별을 검증.
final class FileManagerContentEntryOpsBridgeTests: XCTestCase {
    /// testIsCollectionModeOnLayoutState 테스트 동작을 검증한다.
    func testIsCollectionModeOnLayoutState() {
        var state = FileManagerContentState()

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.entryViewLayout.isCollectionMode)
    }

    /// testCanSaveCollectionRequiresIsCollectionMode 테스트 동작을 검증한다.
    func testCanSaveCollectionRequiresIsCollectionMode() {
        var state = FileManagerContentState()
        state.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.canSaveCollection)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.canSaveCollection)
    }

    /// testCanSaveCollectionFalseWhenNotInCollectionMode 테스트 동작을 검증한다.
    func testCanSaveCollectionFalseWhenNotInCollectionMode() {
        var state = FileManagerContentState()
        state.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)
        XCTAssertFalse(state.canSaveCollection)
    }
}
