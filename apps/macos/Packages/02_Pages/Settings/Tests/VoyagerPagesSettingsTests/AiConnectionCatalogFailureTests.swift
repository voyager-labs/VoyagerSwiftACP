import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class AiConnectionCatalogFailureTests: XCTestCase {
    actor LoadCounter {
        var value = 0

        func increment() -> Int {
            value += 1
            return value
        }

        func currentValue() -> Int {
            value
        }
    }

    func testCatalogLoadFailure_setsFailedPhaseAndPreservesRows() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    func testCatalogLoadFailure_retryRerunsLoadAndSucceedsOnSecondAttempt() async {
        let successfulFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test-valid")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
                ),
            ]
        )

        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                let loadCalls = await loadCounter.increment()
                if loadCalls == 1 {
                    throw NSError(domain: "test", code: -1)
                }
                return successfulFile
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.send(.retryBootstrapTapped) { state in
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.bootstrapPhase = .loaded
        }

        await store.finish()

        let loadCalls = await loadCounter.currentValue()
        // Retry performs one bootstrap load, then verification persistence reloads the latest file before saving.
        XCTAssertEqual(loadCalls, 3)
        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connected)
    }

    func testCatalogLoadFailure_onAppearAfterFailureDoesNotRetryAutomatically() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                _ = await loadCounter.increment()
                throw NSError(domain: "test", code: -1)
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.send(.onAppear)
        await store.finish()

        let loadCalls = await loadCounter.currentValue()
        XCTAssertEqual(loadCalls, 1)
        XCTAssertEqual(store.state.bootstrapPhase, .failed)
    }
}
