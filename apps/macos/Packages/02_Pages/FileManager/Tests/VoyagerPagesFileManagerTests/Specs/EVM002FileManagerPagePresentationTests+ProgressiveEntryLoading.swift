@testable import VoyagerPagesFileManager
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-progressive_entry_loading

    /// EVM-002-progressive_entry_loading: 첫 core batch 뒤에는 모든 source가 interactive entries 정책으로 전환된다.
    /// ordinary directory와 saved collection이 first-batch 완료 후 뒤따르는 batch나 metadata 동안 추가 진행 UI 없이 기존 엔트리 조작을 허용한다.
    /// - 검증 내용: source-owned loading flags가 해제된 다음 `.entries`의 hit testing, accessibility, keyboard dispatch 정책
    /// - 사전 조건: ordinary directory 또는 collection의 first core batch가 적용되어 blocking/replacement flags가 false
    /// - 기대 결과: 두 source 모두 `.entries`이며 entry interaction과 keyboard dispatch가 가능하고 accessibility에서 숨겨지지 않는다.
    func testFirstBatchCompletionMakesOrdinaryAndCollectionEntriesInteractive() {
        let policies = [
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: false,
                isCollectionContentLoading: false,
                isEntryLoading: false,
                isCollectionMode: false,
            ),
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: false,
                isCollectionContentLoading: false,
                isEntryLoading: false,
                isCollectionMode: true,
            ),
        ]

        for policy in policies {
            XCTAssertEqual(policy, .entries)
            XCTAssertFalse(policy.replacesEntriesWithLoading)
            XCTAssertFalse(policy.showsInputBlocker)
            XCTAssertTrue(policy.allowsEntryInteraction)
            XCTAssertFalse(policy.hidesEntriesFromAccessibility)
            XCTAssertTrue(policy.allowsKeyboardCommandDispatch)
        }
    }

    /// EVM-002-progressive_entry_loading: host preset은 성공과 부분 실패 progressive QA 축을 제공한다.
    /// FileManagerHost가 기본/session-lapse preset을 유지한 채 deterministic progressive-entry-loading 시나리오를 선택할 수 있어야 한다.
    /// - 검증 내용: named preset 목록과 scenario mapping의 progressive loading 축
    /// - 사전 조건: FileManagerHostPreset의 전체 preset 조합
    /// - 기대 결과: success/failure preset이 모두 존재하고 각각 success 및 partial-failure scenario로 해석된다.
    func testProgressiveHostPresetsExposeSuccessAndPartialFailureScenarios() {
        XCTAssertEqual(
            Set(FileManagerHostPreset.allCases.map(\.rawValue)),
            [
                "default",
                "session-lapse-guard",
                "session-lapse-sign-in-failed",
                "progressive-entry-loading",
                "progressive-entry-loading-failure",
            ],
        )
        XCTAssertEqual(FileManagerHostPreset.default.scenario.sessionLapse, .none)
        XCTAssertEqual(FileManagerHostPreset.sessionLapseGuard.scenario.sessionLapse, .active)
        XCTAssertEqual(FileManagerHostPreset.sessionLapseSignInFailed.scenario.sessionLapse, .signInFailed)
        XCTAssertEqual(FileManagerHostPreset.progressiveEntryLoading.scenario.progressiveEntryLoading, .success)
        XCTAssertEqual(
            FileManagerHostPreset.progressiveEntryLoadingFailure.scenario.progressiveEntryLoading,
            .partialFailure,
        )
    }
}
