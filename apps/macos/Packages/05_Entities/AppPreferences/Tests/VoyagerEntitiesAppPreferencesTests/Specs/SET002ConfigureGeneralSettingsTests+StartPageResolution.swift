import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared
import XCTest

/*
 SET-002-configure_initial_page 증거 계약 (StartPageResolution 확장)

 포함한 interaction_id:
 - SET-002-configure_initial_page: 집중 자동화 테스트
   StartPageResolver의 가용성 probe 연동과 실패 폴백,
   저장 비침입(no-persistence) 경로를 검증한다.

 마이그레이션 근거:
 - 레거시 StartPageResolverTests의 4개 테스트를 그대로 보존하며
   fixture/double은 Support/StartPageResolutionTestSupport.swift 로 이동했다.
 */

extension SET002ConfigureGeneralSettingsTests {
    // MARK: - SET-002-configure_initial_page

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
}
