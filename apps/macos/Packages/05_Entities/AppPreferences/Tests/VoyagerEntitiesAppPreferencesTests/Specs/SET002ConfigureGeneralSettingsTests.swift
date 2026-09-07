import VoyagerEntitiesAppPreferences
import VoyagerShared
import XCTest

/*
 SET-002-configure_initial_page 증거 계약 (AppPreferences 엔티티 레벨)

 포함한 interaction_id:
 - SET-002-configure_initial_page: 집중 자동화 테스트
   `default_tab_path` legacy 마이그레이션과 `default_start_page_type`
   판별자별 기본 시작 페이지 해석을 검증한다.

 미지원 surface 분류:
 - General tab UI 바인딩과 directory picker 상호작용은
   02_Pages/Settings 의 SET002ConfigureGeneralSettingsTests 가 소유한다.
 - 가용성 probe 런타임 동작은 같은 스펙의 StartPageResolution 확장이 소유한다.
 */

final class SET002ConfigureGeneralSettingsTests: XCTestCase {
    // MARK: - SET-002-configure_initial_page

    /// SET-002-configure_initial_page: 저장된 legacy default_tab_path를 바이트 그대로 반환한다.
    /// 기존 저장값의 손상 없이 로드 경로만 수행하는지 확인한다.
    /// - 검증 내용: defaultTabPath 조회가 저장 문자열과 동일한 값을 반환하고 저장값을 변경하지 않는다.
    /// - 사전 조건: UserDefaults에 legacy 경로(유니코드 포함)가 저장되어 있다.
    /// - 기대 결과: 반환값과 저장값 모두 legacy 경로와 동일하다.
    func testDefaultTabPathReturnsStoredLegacyValueByteForByte() {
        let legacyPath = "/tmp/voy-744/legacy folder/日本語"
        let client = UserDefaultsClient.testValue
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultTabPath(userDefaultsClient: client), legacyPath)
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    /// SET-002-configure_initial_page: 판별자와 legacy 경로가 모두 없으면 home을 기본값으로 저장한다.
    /// 빈 저장소 첫 로드 시 home이 기록되는 초기화 경로를 확인한다.
    /// - 검증 내용: defaultStartPage가 .home을 반환하고 판별자 키에 "home"을 기록한다.
    /// - 사전 조건: UserDefaults에 관련 키가 없다.
    /// - 기대 결과: 결과는 .home이고 저장된 판별자는 "home"이다.
    func testMissingDiscriminatorAndLegacyPathPersistHome() {
        let client = UserDefaultsClient.testValue

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "home")
    }

    /// SET-002-configure_initial_page: 판별자가 없고 legacy 경로가 있으면 directory로 마이그레이션한다.
    /// VOY-744 이전 저장값의 마이그레이션 경로를 확인한다.
    /// - 검증 내용: defaultStartPage가 .directory(legacyPath)를 반환하고 판별자를 "directory"로 기록한다.
    /// - 사전 조건: default_tab_path에 비어 있지 않은 legacy 경로만 저장되어 있다.
    /// - 기대 결과: 결과는 .directory(legacyPath)이고 판별자와 경로 저장값이 유지된다.
    func testMissingDiscriminatorMigratesNonemptyLegacyPathToDirectory() {
        let legacyPath = "/tmp/voy-744/legacy"
        let client = UserDefaultsClient.testValue
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .directory(legacyPath))
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "directory")
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    /// SET-002-configure_initial_page: 명시적 home 판별자는 남아 있는 legacy 경로 payload를 무시한다.
    /// 사용자가 home을 선택한 뒤 경로 잔재가 남아 있는 경우를 확인한다.
    /// - 검증 내용: defaultStartPage가 .home을 반환하고 legacy 경로 저장값을 건드리지 않는다.
    /// - 사전 조건: 판별자는 "home", default_tab_path에는 임의 경로가 저장되어 있다.
    /// - 기대 결과: 결과는 .home이고 legacy 경로 저장값은 그대로 남는다.
    func testExplicitHomeIgnoresRetainedLegacyDirectoryPayload() {
        let legacyPath = "/tmp/voy-744/retained"
        let client = UserDefaultsClient.testValue
        client.setString("home", SettingsKeys.defaultStartPageType)
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    /// SET-002-configure_initial_page: 명시적 directory 판별자는 legacy 경로를 재기록 없이 그대로 사용한다.
    /// 사용자가 선택한 디렉터리 설정이 보존되는지 확인한다.
    /// - 검증 내용: defaultStartPage가 .directory(legacyPath)를 반환하고 저장값을 다시 쓰지 않는다.
    /// - 사전 조건: 판별자는 "directory", default_tab_path에 유효 경로가 저장되어 있다.
    /// - 기대 결과: 결과는 .directory(legacyPath)이고 경로 저장값은 동일하게 유지된다.
    func testExplicitDirectoryUsesRetainedLegacyPathWithoutRewritingIt() {
        let legacyPath = "/tmp/voy-744/explicit"
        let client = UserDefaultsClient.testValue
        client.setString("directory", SettingsKeys.defaultStartPageType)
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .directory(legacyPath))
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    /// SET-002-configure_initial_page: 미지원 판별자는 home으로 폴백하고 legacy 경로는 유지한다.
    /// 미래 버전 판별자 값에 대한 하위 호환 경로를 확인한다.
    /// - 검증 내용: defaultStartPage가 .home을 반환하고 판별자를 "home"으로 되돌리며 경로는 유지된다.
    /// - 사전 조건: 판별자에 미지원 값("future")과 legacy 경로가 저장되어 있다.
    /// - 기대 결과: 결과는 .home, 판별자는 "home", 경로 저장값은 legacy 경로 그대로다.
    func testUnknownDiscriminatorFallsBackToHomeAndRetainsLegacyPath() {
        let legacyPath = "/tmp/voy-744/unknown"
        let client = UserDefaultsClient.testValue
        client.setString("future", SettingsKeys.defaultStartPageType)
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "home")
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    /// SET-002-configure_initial_page: 빈 판별자와 빈 경로 payload도 home으로 폴백한다.
    /// 공백 문자열이 저장된 손상 상태에 대한 방어 경로를 확인한다.
    /// - 검증 내용: defaultStartPage가 .home을 반환하고 판별자를 "home"으로 기록한다.
    /// - 사전 조건: 판별자와 default_tab_path에 모두 빈 문자열이 저장되어 있다.
    /// - 기대 결과: 결과는 .home이고 판별자는 "home", 경로 저장값은 빈 문자열로 유지된다.
    func testEmptyDiscriminatorAndLegacyPayloadFallBackToHome() {
        let client = UserDefaultsClient.testValue
        client.setString("", SettingsKeys.defaultStartPageType)
        client.setString("", SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "home")
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), "")
    }

    /// SET-002-configure_initial_page: 마이그레이션된 스냅샷은 재로드에서도 안정적으로 유지된다.
    /// 반복 조회 시 결과와 저장값이 변하지 않는 멱등성을 확인한다.
    /// - 검증 내용: 두 번의 defaultStartPage 조회가 동일한 .directory 결과를 반환하고 저장값이 고정된다.
    /// - 사전 조건: default_tab_path에 legacy 경로만 저장되어 있다.
    /// - 기대 결과: 첫/두 번째 결과가 동일하고 판별자는 "directory", 경로는 legacy 값 그대로다.
    func testMigratedSnapshotIsStableAcrossReloads() {
        let legacyPath = "/tmp/voy-744/stable"
        let client = UserDefaultsClient.testValue
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        let first = SettingsDefaults.defaultStartPage(userDefaultsClient: client)
        let second = SettingsDefaults.defaultStartPage(userDefaultsClient: client)

        XCTAssertEqual(first, .directory(legacyPath))
        XCTAssertEqual(second, first)
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "directory")
    }
}
