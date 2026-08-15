// FLOW-ID: evm.arrange_entries_view
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class ArrangeEntriesViewFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.arrangement_preserves_page_identity

    /// EVM-004-sort_entries_by_property: arrangement 변경은 current page identity를 이동시키지 않는다.
    /// - 검증 내용: composed entries view에 sort intent를 전달한 뒤 route/history가 유지된다.
    /// - 사전 조건: `/flow/current` directory page가 name arrangement로 표시된다.
    /// - 기대 결과: sort projection은 date modified로 바뀌고 current page/history는 같다.
    func testArrangementPreservesPageIdentity() async {
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath("/flow/current")
        state.entryViewLayout.entryArrangements.sortKey = .name
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // flow는 comparator output을 재소유하지 않고 arrangement 이후 page identity만 검증한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        await store.send(.entryViewLayout(.entryArrangements(.setSortKey(.dateModified))))

        XCTAssertEqual(store.state.entryViewLayout.entryArrangements.sortKey, .dateModified)
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
    }
}
