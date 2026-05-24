@testable import VoyagerPagesOnboarding
import XCTest

/// 온보딩 윈도우 클라이언트 — 프레젠테이션 대기 중 멱등성(idempotency)을 검증.
@MainActor
final class OnboardingWindowClientTests: XCTestCase {
    /// testShowIfNeededIsIdempotentWhilePresentationIsPending 테스트 동작을 검증한다.
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
