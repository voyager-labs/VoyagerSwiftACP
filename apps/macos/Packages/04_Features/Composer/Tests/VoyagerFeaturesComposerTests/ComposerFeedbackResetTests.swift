import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class ComposerFeedbackResetTests: XCTestCase {
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

    func testDuplicateFailureKeepsExistingFeedbackAndTimer() async throws {
        let clock = TestClock()
        let requestID = UUID()
        var initialState = ComposerState()
        initialState.isLoadingSearch = true
        initialState.activeSearchRequestID = requestID
        initialState.queryRenderPhase = .searching
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.searchClient.applyFilters = { _ in
                throw MockLocalizedError("HELPER_UNAVAILABLE: disconnected")
            }
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

        let feedbackID = try XCTUnwrap(store.state.transientFeedback?.id)

        await clock.advance(by: .seconds(4))
        await store.receive { action in
            guard case let .internal(.dismissTransientFeedback(id)) = action else { return false }
            return id == feedbackID
        } assert: {
            $0.transientFeedback = nil
        }
    }

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
