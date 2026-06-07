@testable import VoyagerShared
import XCTest

final class SearchXPCTransportTimeoutPolicyTests: XCTestCase {
    func testProviderBackedQueryTimeoutCoversModelListAndStreamingExecution() {
        XCTAssertGreaterThanOrEqual(
            SearchXPCTransportTimeoutPolicy.providerBackedQuerySeconds,
            SearchXPCTransportTimeoutPolicy.providerModelListSeconds
                + SearchXPCTransportTimeoutPolicy.providerStreamingExecutionSeconds,
        )
    }

    func testProviderBackedQueryTimeoutStaysLongerThanDeterministicSearchTimeout() {
        XCTAssertGreaterThan(
            SearchXPCTransportTimeoutPolicy.providerBackedQuerySeconds,
            SearchXPCTransportTimeoutPolicy.deterministicSearchSeconds,
        )
        XCTAssertEqual(SearchXPCTransportTimeoutPolicy.warmupSeconds, 20)
    }
}
