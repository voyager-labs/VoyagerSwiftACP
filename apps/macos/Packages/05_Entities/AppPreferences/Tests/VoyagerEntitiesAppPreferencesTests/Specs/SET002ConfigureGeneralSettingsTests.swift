import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesAppPreferences
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
 - 가용성 probe 런타임 동작은 같은 스펙 suite의 StartPageResolution 테스트가 소유한다.
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

    /// SET-002-configure_initial_page: home 시작 페이지는 가용성 probe 없이 해석된다.
    /// home 선택 시 불필요한 파일시스템 접근이 없는지 확인한다.
    /// - 검증 내용: 결과가 .home이고 fallbackReason이 nil이며 probe 클라이언트가 호출되지 않는다.
    /// - 사전 조건: probe 클라이언트가 호출 횟수를 기록하도록 주입되어 있다.
    /// - 기대 결과: effectiveStartPage는 .home, fallbackReason은 nil, probe 호출 횟수는 0이다.
    func testHomeDoesNotProbe() {
        let probeCount = Counter()
        let client = StartPageAvailabilityClient { _ in
            probeCount.value += 1
            return .missing
        }

        let result = withDependencies {
            $0.startPageAvailabilityClient = client
        } operation: {
            StartPageResolver.resolve(.home)
        }

        XCTAssertEqual(result.effectiveStartPage, .home)
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(probeCount.value, 0)
    }

    /// SET-002-configure_initial_page: 가용한 directory 시작 페이지는 경로 그대로 해석된다.
    /// 유효 디렉터리 선택이 저장 전 해석 단계에서 보존되는지 확인한다.
    /// - 검증 내용: 결과가 입력 경로의 .directory와 동일하고 fallbackReason은 nil이다.
    /// - 사전 조건: probe 클라이언트가 availableDirectory를 반환하도록 주입되어 있다.
    /// - 기대 결과: effectiveStartPage는 .directory(path), fallbackReason은 nil이다.
    func testAvailableDirectoryResolvesToDirectory() {
        let path = "/tmp/voy-744-available"
        let result = withDependencies {
            $0.startPageAvailabilityClient = StartPageAvailabilityClient { _ in .availableDirectory }
        } operation: {
            StartPageResolver.resolve(.directory(path))
        }

        XCTAssertEqual(result.effectiveStartPage, .directory(path))
        XCTAssertNil(result.fallbackReason)
    }

    /// SET-002-configure_initial_page: directory 판정 실패 시 home으로 폴백하고 저장하지 않는다.
    /// 모든 실패 유형에서 폴백·비저장·경로 비노출을 확인한다.
    /// - 검증 내용: missing/nonDirectory/permissionDenied/cloudPlaceholder 각각에 대해
    ///   home 폴백, 대응 fallbackReason, 쓰기 0회, 저장값 무변경, 결과 문자열에 경로 미포함을 검증한다.
    /// - 사전 조건: RecordingUserDefaults에 directory 설정값이 채워져 있고 probe가 각 실패를 반환한다.
    /// - 기대 결과: 네 실패 유형 모두 home 폴백이며 어떤 저장도 발생하지 않는다.
    func testDirectoryFailuresFallbackToHomeWithoutPersistence() {
        let failures: [StartPageDirectoryAvailability] = [
            .missing,
            .nonDirectory,
            .permissionDenied,
            .cloudPlaceholder,
        ]

        for failure in failures {
            let path = "/tmp/voy-744-canary-\(failure)"
            let storage = RecordingUserDefaults()
            storage.values[SettingsKeys.defaultStartPageType] = "directory"
            storage.values[SettingsKeys.defaultTabPath] = path
            let result = withDependencies {
                $0.startPageAvailabilityClient = StartPageAvailabilityClient { _ in failure }
                $0.userDefaultsClient = storage.client
            } operation: {
                StartPageResolver.resolve(.directory(path))
            }

            XCTAssertEqual(result.effectiveStartPage, .home)
            XCTAssertEqual(result.fallbackReason, .init(availability: failure))
            XCTAssertEqual(storage.writeCount, 0)
            XCTAssertEqual(storage.values[SettingsKeys.defaultStartPageType], "directory")
            XCTAssertEqual(storage.values[SettingsKeys.defaultTabPath], path)
            XCTAssertFalse(String(describing: result).contains(path))
        }
    }

    /// SET-002-configure_initial_page: live probe가 실제 존재하는 임시 디렉터리를 해석한다.
    /// mock이 아닌 live 가용성 클라이언트의 성공 경로를 확인한다.
    /// - 검증 내용: live 클라이언트가 실제 디렉터리를 availableDirectory로 판정해 경로 그대로 반환한다.
    /// - 사전 조건: FileManager 임시 위치에 실제 디렉터리 fixture가 생성되어 있다.
    /// - 기대 결과: effectiveStartPage는 fixture 경로의 .directory, fallbackReason은 nil이다.
    func testLiveProbeResolvesTemporaryDirectory() throws {
        let sandbox = try FileManagerFixtureSandbox()
        defer { sandbox.cleanup() }

        let result = withDependencies {
            $0.startPageAvailabilityClient = .liveValue
        } operation: {
            StartPageResolver.resolve(.directory(sandbox.directory.path))
        }

        XCTAssertEqual(result.effectiveStartPage, .directory(sandbox.directory.path))
        XCTAssertNil(result.fallbackReason)
    }

    /// SET-002-configure_initial_page: directory 열거 권한 오류는 home으로 폴백한다.
    /// stat 성공만으로 접근 가능하다고 판단하지 않고 권한 오류 폴백과 비저장을 확인한다.
    /// - 검증 내용: EACCES와 EPERM 각각에 대해 열거가 1회 호출되고 home 폴백, permissionDenied,
    ///   쓰기 0회, 기존 저장값 유지, 결과 문자열의 경로 비노출을 검증한다.
    /// - 사전 조건: 실제 임시 디렉터리가 생성되어 cloud metadata/stat은 성공하고 열거만 합성 권한 오류를 반환한다.
    /// - 기대 결과: 두 권한 오류 모두 effectiveStartPage는 .home이며 저장값과 결과 경로가 변하지 않는다.
    func testLiveProbePermissionErrorsFallbackToHomeWithoutPersistence() throws {
        let sandbox = try FileManagerFixtureSandbox()
        defer { sandbox.cleanup() }

        for code in [EACCES, EPERM] {
            let path = sandbox.directory.path
            let storage = RecordingUserDefaults()
            storage.values[SettingsKeys.defaultStartPageType] = "directory"
            storage.values[SettingsKeys.defaultTabPath] = path
            let enumerationCount = Counter()
            let result = withDependencies {
                $0.startPageAvailabilityClient = .live(contentsOfDirectory: { requestedPath in
                    if requestedPath == path {
                        enumerationCount.value += 1
                    }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
                })
                $0.userDefaultsClient = storage.client
            } operation: {
                StartPageResolver.resolve(.directory(path))
            }

            XCTAssertEqual(enumerationCount.value, 1)
            XCTAssertEqual(result.effectiveStartPage, StartPage.home)
            XCTAssertEqual(result.fallbackReason, StartPageFallbackReason.permissionDenied)
            XCTAssertEqual(storage.writeCount, 0)
            XCTAssertEqual(storage.values[SettingsKeys.defaultStartPageType], "directory")
            XCTAssertEqual(storage.values[SettingsKeys.defaultTabPath], path)
            XCTAssertFalse(String(describing: result).contains(path))
        }
    }
}
