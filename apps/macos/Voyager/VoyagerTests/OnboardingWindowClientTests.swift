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

    /// closeWindow 후 presentation gate가 리셋되어 showIfNeeded가 다시 showWindow를 호출하는지 검증.
    /// - 검증 내용: closeWindow 이후 showIfNeeded 호출 시 showWindow가 한 번 더 실행됨
    /// - 사전 조건: showIfNeeded로 온보딩 윈도우 표시 후 closeWindow로 닫기
    /// - 기대 결과: showWindow 총 호출 횟수 == 2 (최초 1 + close 후 재오픈 1)
    func testCloseWindowResetsPresentationGateAllowingReopen() async {
        let counter = AsyncCounter()
        let firstShowExpectation = expectation(description: "first showWindow")
        let secondShowExpectation = expectation(description: "second showWindow after close")

        var showCallIndex = 0
        let client = OnboardingWindowClient.makeClient(
            progressClient: OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            ),
            openMainWindow: { _ in true },
            showWindow: {
                showCallIndex += 1
                await counter.increment()
                if showCallIndex == 1 {
                    firstShowExpectation.fulfill()
                } else {
                    secondShowExpectation.fulfill()
                }
            },
            closeWindow: {},
        )

        XCTAssertTrue(client.showIfNeeded())
        await fulfillment(of: [firstShowExpectation], timeout: 1.0)

        await client.closeWindow()

        XCTAssertTrue(client.showIfNeeded())
        await fulfillment(of: [secondShowExpectation], timeout: 1.0)

        let showCount = await counter.value()
        XCTAssertEqual(showCount, 2, "closeWindow 후 showIfNeeded가 다시 showWindow를 호출해야 한다")
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
