import XCTest

final class VoyagerUITests: XCTestCase {
    override func setUpWithError() throws {
        // 설정 코드를 여기에 작성합니다. 이 메서드는 클래스의 각 테스트 메서드 호출 전에 실행됩니다.

        // UI 테스트에서는 실패가 발생했을 때 즉시 중단하는 것이 일반적으로 좋습니다.
        continueAfterFailure = false

        // UI 테스트에서는 테스트에 필요한 초기 상태(예: 인터페이스 방향)를 설정하는 것이 중요합니다.
        // 실행하기 전에 작업을 설정하세요. setUp 메서드는 이를 위한 좋은 위치입니다.
    }

    override func tearDownWithError() throws {
        // 정리 코드를 여기에 작성합니다. 이 메서드는 클래스의 각 테스트 메서드 호출 후에 실행됩니다.
    }

    /// 앱이 정상적으로 실행되어 포그라운드 상태가 되는지 확인하는 스모크 테스트.
    /// 앱 크래시·런치 실패 등 치명적 회귀를 조기에 감지하기 위해 실행 상태와 스크린샷을 검증한다.
    @MainActor
    func testAppLaunchSmoke() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Voyager UI Smoke"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
