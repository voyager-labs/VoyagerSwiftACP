import XCTest

final class VoyagerUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 다양한 UI 구성(다크/라이트 모드 등)에서 앱이 정상적으로 런치되는지 검증하는 테스트.
    /// 각 타겟 애플리케이션 UI 구성별로 실행되어 런치 스크린샷을 수집한다.
    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // 앱 시작 후 스크린샷 촬영 전에 수행할 단계를 여기에 추가하세요.
        // 예: 테스트 계정으로 로그인하거나 앱 내에서 특정 위치로 이동하는 작업을 수행하세요.

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
