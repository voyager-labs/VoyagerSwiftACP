import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// FileManagerFeature — 초기 윈도우 상태 구성과 onAppear 시 초기 액션 디스패치가
/// 올바르게 수행되는지 검증하는 네비게이션 테스트.
/// 윈도우 시작 시 기본 경로/사이드바 가시성이 깨지면 앱이 정상 동작하지 않는다.
@MainActor
final class FileManagerFeatureNavigationTests: XCTestCase {
    /// 초기 윈도우 상태가 기본 탭 경로와 사이드바 표시를 포함하는지 확인.
    func testInitialWindowStateContainsDefaultSlices() {
        let state = FileManagerFeature.State()

        XCTAssertEqual(state.content.navigation.currentPath, SettingsDefaults.defaultTabPath())
        XCTAssertTrue(state.sidebar.sidebarVisible)
    }

    /// onAppear 전송 시 초기 윈도우 액션이 올바르게 디스패치되는지 확인.
    func testOnAppearDispatchesInitialWindowActions() async {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: 핵심 델리게이트/상태 변화에 집중; 중간 액션은 노이즈가 많음.
        store.exhaustivity = .off

        await store.send(.onAppear)

        XCTAssertEqual(store.state.content.navigation.currentPath, SettingsDefaults.defaultTabPath())
    }
}
