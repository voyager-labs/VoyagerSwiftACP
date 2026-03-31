import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ComposerFeedbackResetTests: XCTestCase {
    func testTypingClearsFeedbackImmediately() async {
        let feedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "boom")
        let store = TestStore(initialState: ComposerState(transientFeedback: feedback)) {
            ComposerFeature()
        }

        await store.send(.setText("abc")) {
            $0.text = "abc"
            $0.transientFeedback = nil
        }
    }

    func testCancelSearchClearsFeedbackImmediately() async {
        let feedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "boom")
        let store = TestStore(initialState: ComposerState(
            transientFeedback: feedback,
            isLoadingSearch: true,
            activeSearchRequestID: UUID(),
            queryRenderPhase: .searching,
        )) {
            ComposerFeature()
        }

        await store.send(.cancelSearch) {
            $0.transientFeedback = nil
            $0.isLoadingSearch = false
            $0.activeSearchRequestID = nil
            $0.queryRenderPhase = .idle
        }
    }

    func testDuplicateFailureKeepsExistingFeedbackAndTimer() async {
        let clock = TestClock()
        let requestID = UUID()
        let initialFeedback = ComposerTransientFeedback(
            id: UUID(),
            kind: .error,
            message: "Search couldn't be completed. Check Helper/Gateway and try again.",
        )
        let store = TestStore(initialState: ComposerState(
            transientFeedback: initialFeedback,
            isLoadingSearch: true,
            activeSearchRequestID: requestID,
            queryRenderPhase: .searching,
        )) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(requestID, .failure(MockLocalizedError("HELPER_UNAVAILABLE: disconnected")))) {
            $0.isLoadingSearch = false
            $0.activeSearchRequestID = nil
            $0.queryRenderPhase = .failed
            $0.searchStartedAt = nil
        }

        XCTAssertEqual(store.state.transientFeedback, initialFeedback)

        await clock.advance(by: .seconds(4))
        await store.receive(.dismissTransientFeedback(id: initialFeedback.id)) {
            $0.transientFeedback = nil
        }
    }

    func testStaleDismissActionDoesNotClearReplacementFeedback() async {
        let oldFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "old")
        let newFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "new")
        let store = TestStore(initialState: ComposerState(transientFeedback: newFeedback)) {
            ComposerFeature()
        }

        await store.send(.dismissTransientFeedback(id: oldFeedback.id))

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
