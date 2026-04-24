@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class OnboardingWindowClientTests: XCTestCase {
    func testShowIfNeededIsIdempotentWhilePresentationIsPending() async {
        let counter = AsyncCounter()
        let showExpectation = expectation(description: "showWindow called once")
        showExpectation.expectedFulfillmentCount = 1

        let client = OnboardingWindowClient.makeClient(
            progressClient: OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            ),
            openMainWindow: { _ in true },
            showWindow: {
                await counter.increment()
                showExpectation.fulfill()
            },
            closeWindow: {},
        )

        XCTAssertTrue(client.showIfNeeded())
        XCTAssertTrue(client.showIfNeeded())

        await fulfillment(of: [showExpectation], timeout: 1.0)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let showCount = await counter.value()
        XCTAssertEqual(showCount, 1)
    }
}

private actor AsyncCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
