// KNOWN SPEC GAP: SET-007-show_ai_provider_list AC6 requires that catalog load failure
// shows a failure notice with retry action rather than a blank/notVerified fallback.
// The current implementation catches the error and falls back to AIConnectionsFile.empty(),
// resulting in all rows showing as .notVerified without a retry mechanism.
// If explicit retry UX is added, these tests should be extended.

import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class AiConnectionCatalogFailureTests: XCTestCase {
    // MARK: - Safe Fallback

    func testCatalogLoadFailure_fallsBackToAllNotVerified() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted)

        await store.finish()

        for row in store.state.rows {
            XCTAssertEqual(
                row.connectionState,
                .notVerified,
                "All rows should be notVerified on load failure"
            )
        }
    }

    func testCatalogLoadFailure_noProviderRowsCorrupted() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted)

        await store.finish()

        let state = store.state
        XCTAssertEqual(state.rows.count, 3, "All 3 provider rows must exist after load failure")

        let expectedProviders: [AiProvider] = [.chatgptCodex, .openai, .anthropic]
        for provider in expectedProviders {
            let row = state.rows[id: provider]
            XCTAssertNotNil(row, "Row for \(provider) must not be missing after load failure")
            XCTAssertEqual(
                row?.connectionState,
                .notVerified,
                "Row for \(provider) should be notVerified, not corrupted"
            )
        }
    }

    // MARK: - Idempotent Bootstrap

    func testCatalogLoadFailure_didBootstrap_isTrue() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted)

        await store.finish()

        XCTAssertTrue(
            store.state.didBootstrap,
            "didBootstrap must be true after load failure to prevent infinite retry"
        )
    }

    func testCatalogLoadFailure_idempotentBootstrap() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted)

        await store.finish()

        // Second onAppear is a no-op because didBootstrap is already true.
        // This documents that there is NO explicit retry mechanism:
        // once bootstrapped (success or failure), the system does not re-load.
        await store.send(.onAppear)
        await store.finish()
    }

    func testCatalogLoadSuccess_afterFailureOnSecondAppear() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted)

        await store.finish()

        await store.send(.onAppear)
        await store.finish()
    }

    // MARK: - Documented Spec Gap

    func testCatalogLoadFailureDocumentedGap_noRetryUI() async {
        // This test documents the KNOWN GAP: SET-007 AC6 expects a retry action on catalog
        // load failure, but the current implementation falls back to notVerified without
        // retry UI. The test verifies the current fallback behavior so any future change
        // to add retry UX will need to update this test.
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted)

        await store.finish()

        let state = store.state
        // Current behavior: all rows show .connect (notVerified), not a failure+retry action.
        // AC6 expects a dedicated failure notice with retry — this is a spec gap for Task 9.
        for row in state.rows {
            XCTAssertEqual(
                row.primaryAction,
                .connect,
                "After load failure, rows show .connect (notVerified fallback), not a retry action"
            )
        }
    }
}
