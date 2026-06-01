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
