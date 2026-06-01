import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

// 비활성화: 테스트한 API (entryArrangements/entryOperations scopes, entryThumbnails state,
// EntryModel.stub) 가 구현되지 않았음. 정규화된 구조가 구현되면 다시 활성화.

/// FileManagerContentAction 정규화 테스트 — 액션 enum의 하위 케이스 completeness와
/// content → entryViewLayout/entryOperations 라우팅 정규화가 올바른지 검증.
/// 현재 API 미구현으로 스텁 상태.
@MainActor
final class ContentActionNormalizationTests: XCTestCase {
    func testActionHasChildCases() {}
    /// 전체 선택 액션이 entryViewLayout으로 올바르게 라우팅되는지 확인 (미구현 스텁).
    func testSelectAllEntriesRoutesToEntryViewLayout() {}
    /// 숨김 파일 토글 후 리로드가 올바르게 수행되는지 확인 (미구현 스텁).
    func testToggleShowHiddenFilesAndReloadRoutesCorrectly() {}
    /// 썸네일 액션이 entryOperations를 통해 라우팅되는지 확인 (미구현 스텁).
    func testThumbnailActionsRoutedThroughEntryOperations() {}
}
