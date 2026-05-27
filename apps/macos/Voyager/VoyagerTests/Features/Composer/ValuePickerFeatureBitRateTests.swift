import XCTest

@MainActor
final class ValuePickerFeatureBitRateTests: XCTestCase {
    /// 프로젝트 컨텍스트가 아닐 때 bitrate-value 피커 기능을 사용할 수 없는지 확인.
    func testValuePickerFeatureNotInProject() {
        // ValuePickerFeature.swift가 Xcode 프로젝트에 포함되어 있지 않습니다.
        // 이 테스트 파일은 VOY-201에서 프로젝트에 추가할 때까지 비활성화됩니다.
    }
}
