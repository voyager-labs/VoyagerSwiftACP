import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
/// Composer 피드백 리셋 — 타이핑/취소/stale 이벤트에 따른 피드백 보존/초기화를 검증.
final class ComposerFeedbackResetTests: XCTestCase {
    /// testTypingClearsFeedbackImmediately 테스트 동작을 검증한다.
    func testTypingClearsFeedbackImmediately() async {
        let feedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "boom")
        var initialState = ComposerState()
        initialState.transientFeedback = feedback
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.setText("abc")) {
            $0.text = "abc"
            $0.transientFeedback = nil
        }
    }

    /// testCancelSearchClearsFeedbackImmediately 테스트 동작을 검증한다.
    func testCancelSearchClearsFeedbackImmediately() async {
        let feedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "boom")
        var initialState = ComposerState()
        initialState.transientFeedback = feedback
        initialState.isLoadingSearch = true
        initialState.activeSearchRequestID = UUID()
        initialState.queryRenderPhase = .searching
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.cancelSearch) {
            $0.transientFeedback = nil
            $0.isLoadingSearch = false
            $0.activeSearchRequestID = nil
            $0.queryRenderPhase = .idle
        }
    }

    /// testDuplicateFailureKeepsExistingFeedbackAndTimer 테스트 동작을 검증한다.
    func testDuplicateFailureKeepsExistingFeedbackAndTimer() async {
        let clock = TestClock()
        let requestID = UUID()
        let initialFeedback = ComposerTransientFeedback(
            id: UUID(),
            kind: .error,
            message: "Search couldn't be completed. Check Helper/Gateway and try again.",
        )
        var initialState = ComposerState()
        initialState.transientFeedback = initialFeedback
        initialState.isLoadingSearch = true
        initialState.activeSearchRequestID = requestID
        initialState.queryRenderPhase = .searching
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(
            requestID,
            .failure(MockLocalizedError("HELPER_UNAVAILABLE: disconnected")),
        )) {
            $0.isLoadingSearch = false
            $0.activeSearchRequestID = nil
            $0.queryRenderPhase = .failed
            $0.searchStartedAt = nil
        }

        XCTAssertEqual(store.state.transientFeedback, initialFeedback)

        await clock.advance(by: .seconds(4))
        await store.receive { action in
            guard case let .internal(.dismissTransientFeedback(id)) = action else { return false }
            return id == initialFeedback.id
        } assert: {
            $0.transientFeedback = nil
        }
    }

    /// testStaleDismissActionDoesNotClearReplacementFeedback 테스트 동작을 검증한다.
    func testStaleDismissActionDoesNotClearReplacementFeedback() async {
        let oldFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "old")
        let newFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "new")
        var initialState = ComposerState()
        initialState.transientFeedback = newFeedback
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.dismissTransientFeedback(id: oldFeedback.id))

        XCTAssertEqual(store.state.transientFeedback, newFeedback)
    }
}

private struct MockLocalizedError: LocalizedError, Equatable {
    let rawMessage: String

    init(_ rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var errorDescription: String? {
        rawMessage
    }
}
