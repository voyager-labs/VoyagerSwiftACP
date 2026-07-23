import Foundation
import VoyagerShared
import XCTest

final class FSH001FilterSearchXPCServiceConstantsTests: XCTestCase {
    // MARK: - FSH-001-mach_service_name_resolution

    /// FSH-001-mach_service_name_resolution: Info.plist에서 주입된 XPC_MACH_SERVICE_NAME 값을 그대로 반환
    /// - 검증 내용: `machServiceName(infoDictionary:)`가 Info.plist의 값을 정확히 반환
    /// - 사전 조건: infoDictionary에 유효한 XPC_MACH_SERVICE_NAME 포함
    /// - 기대 결과: 전달한 값 그대로 반환
    func testMachServiceNameResolvesFromInfoDictionary() {
        let expected = "fm.voyager.Voyager.FilterSearchXPC.dev"
        let name = FilterSearchXPCServiceConstants.machServiceName(
            infoDictionary: ["XPC_MACH_SERVICE_NAME": expected],
        )
        XCTAssertEqual(name, expected)
    }

    /// FSH-001-mach_service_name_resolution: Prod-Release XPC service name 해석
    /// - 검증 내용: prod (suffix 없는) Mach service name이 올바르게 해석됨
    /// - 사전 조건: infoDictionary에 prod 값 포함
    /// - 기대 결과: `fm.voyager.Voyager.FilterSearchXPC` 반환
    func testMachServiceNameResolvesProdValue() {
        let expected = "fm.voyager.Voyager.FilterSearchXPC"
        let name = FilterSearchXPCServiceConstants.machServiceName(
            infoDictionary: ["XPC_MACH_SERVICE_NAME": expected],
        )
        XCTAssertEqual(name, expected)
    }

    /// FSH-001-mach_service_name_resolution: Prod-Debug XPC service name 해석
    /// - 검증 내용: proddebug suffix Mach service name이 올바르게 해석됨
    /// - 사전 조건: infoDictionary에 Prod-Debug 값 포함
    /// - 기대 결과: `fm.voyager.Voyager.FilterSearchXPC.proddebug` 반환
    func testMachServiceNameResolvesProdDebugValue() {
        let expected = "fm.voyager.Voyager.FilterSearchXPC.proddebug"
        let name = FilterSearchXPCServiceConstants.machServiceName(
            infoDictionary: ["XPC_MACH_SERVICE_NAME": expected],
        )
        XCTAssertEqual(name, expected)
    }
}
