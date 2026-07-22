import Foundation
import VoyagerShared
import XCTest

final class FSH001FilterSearchXPCServiceConstantsTests: XCTestCase {
    // MARK: - FSH-001-mach_service_name_resolution

    /// FSH-001-mach_service_name_resolution: FilterSearchXPC 서비스 이름은 Info.plist 또는 fallback으로 결정됨
    /// XPC Mach service name이 Info.plist-driven resolution으로 올바르게 제공되는지 검증한다.
    /// - 검증 내용: `FilterSearchXPCServiceConstants.machServiceName`이 빈 문자열이 아님
    /// - 사전 조건: 없음
    /// - 기대 결과: 항상 유효한 Mach service name 문자열 반환
    func testMachServiceNameReturnsNonEmptyString() {
        let name = FilterSearchXPCServiceConstants.machServiceName
        XCTAssertFalse(name.isEmpty, "Mach service name must not be empty")
    }

    /// FSH-001-mach_service_name_resolution: Info.plist에 XPC_MACH_SERVICE_NAME이 없으면 legacy fallback 반환
    /// fallback 문자열이 예상된 legacy 값과 일치하는지 검증한다.
    /// - 검증 내용: 반환된 Mach service name이 예상된 값들 중 하나와 일치
    /// - 사전 조건: 없음
    /// - 기대 결과: Info.plist-driven 값 또는 legacy fallback 문자열 반환
    func testMachServiceNameFallbackIsCorrect() {
        let name = FilterSearchXPCServiceConstants.machServiceName
        let expectedLegacy = "fm.voyager.Voyager.FilterSearchXPC"
        let expectedDev = "fm.voyager.Voyager.FilterSearchXPC.dev"
        // Info.plist에 XPC_MACH_SERVICE_NAME이 있으면 그 값을, 없으면 fallback을 반환
        // 테스트 호스트의 Info.plist에 따라 값이 달라질 수 있으므로 두 경우 모두 허용
        XCTAssertTrue(
            name == expectedLegacy || name == expectedDev,
            "Expected '\(expectedLegacy)' or '\(expectedDev)', got '\(name)'",
        )
    }
}
