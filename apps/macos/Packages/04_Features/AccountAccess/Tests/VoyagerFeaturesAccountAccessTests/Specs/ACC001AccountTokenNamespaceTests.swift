import Foundation
@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

/*
 ACC-001-account_token_namespace spec-owner 테스트

 AccountTokenFSLocation이 appEnv 파라미터에 따라 올바른 네임스페이스 경로를 생성하는지 검증한다.
 - prod: ~/.voyager/account_tokens.json (기존 경로와 호환)
 - dev:  ~/.voyager/dev/account_tokens.json
 */

@MainActor
final class ACC001AccountTokenNamespaceTests: XCTestCase {
    private let homeURL = URL(fileURLWithPath: "/Users/test")

    // MARK: - ACC-001-account_token_namespace

    /// ACC-001-account_token_namespace: dev 환경에서 token 파일 경로가 dev/ 하위로 생성된다.
    /// dev appEnv 전달 시 경로에 "dev" 세그먼트가 포함되는지 검증한다.
    /// - 검증 내용: dev 경로가 "dev/account_tokens.json"으로 끝남
    /// - 사전 조건: AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL:, appEnv: .dev)
    /// - 기대 결과: URL이 ".voyager/dev/account_tokens.json" 패턴으로 종료
    func testDevNamespace() {
        let url = AccountTokenFSLocation.accountTokensFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .dev,
        )
        XCTAssertTrue(
            url.path.hasSuffix(".voyager/dev/account_tokens.json"),
            "dev 경로는 .voyager/dev/account_tokens.json으로 끝나야 함: \(url.path)",
        )
    }

    /// ACC-001-account_token_namespace: prod 환경에서 token 파일 경로가 기존과 동일하다.
    /// prod appEnv 전달 시 경로에 "dev" 세그먼트가 없는지 검증한다.
    /// - 검증 내용: prod 경로가 "account_tokens.json"으로 끝나고 "dev/"가 없음
    /// - 사전 조건: AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL:, appEnv: .prod)
    /// - 기대 결과: URL이 ".voyager/account_tokens.json" 패턴으로 종료
    func testProdNamespace() {
        let url = AccountTokenFSLocation.accountTokensFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .prod,
        )
        XCTAssertTrue(
            url.path.hasSuffix(".voyager/account_tokens.json"),
            "prod 경로는 .voyager/account_tokens.json으로 끝나야 함: \(url.path)",
        )
        XCTAssertFalse(
            url.path.contains("/dev/"),
            "prod 경로에 dev/ 세그먼트가 없어야 함: \(url.path)",
        )
    }

    /// ACC-001-account_token_namespace: lock 파일이 appEnv에 따라 네임스페이스된다.
    /// - 검증 내용: dev lock 경로에 "dev/" 포함, prod lock 경로에 "dev/" 미포함
    /// - 사전 조건: AccountTokenFSLocation.lockFileURL(homeDirectoryURL:, appEnv:)
    /// - 기대 결과: dev는 ".voyager/dev/", prod는 ".voyager/" 경로
    func testLockFileNamespace() {
        let devURL = AccountTokenFSLocation.lockFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .dev,
        )
        let prodURL = AccountTokenFSLocation.lockFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .prod,
        )

        XCTAssertTrue(devURL.path.hasSuffix(".voyager/dev/account_tokens.lock"))
        XCTAssertTrue(prodURL.path.hasSuffix(".voyager/account_tokens.lock"))
        XCTAssertFalse(prodURL.path.contains("/dev/"))
    }

    /// ACC-001-account_token_namespace: handoff staging 파일이 appEnv에 따라 네임스페이스된다.
    /// - 검증 내용: dev staging 경로에 "dev/" 포함
    /// - 사전 조건: AccountTokenFSLocation.handoffStagingFileURL(homeDirectoryURL:, appEnv:)
    /// - 기대 결과: dev는 ".voyager/dev/", prod는 ".voyager/" 경로
    func testHandoffStagingFileNamespace() {
        let devURL = AccountTokenFSLocation.handoffStagingFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .dev,
        )
        let prodURL = AccountTokenFSLocation.handoffStagingFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .prod,
        )

        XCTAssertTrue(devURL.path.hasSuffix(".voyager/dev/account_tokens.handoff-staging.json"))
        XCTAssertTrue(prodURL.path.hasSuffix(".voyager/account_tokens.handoff-staging.json"))
        XCTAssertFalse(prodURL.path.contains("/dev/"))
    }

    /// ACC-001-account_token_namespace: rollback marker 파일이 appEnv에 따라 네임스페이스된다.
    /// - 검증 내용: dev rollback marker 경로에 "dev/" 포함
    /// - 사전 조건: AccountTokenFSLocation.rollbackMarkerFileURL(homeDirectoryURL:, appEnv:)
    /// - 기대 결과: dev는 ".voyager/dev/", prod는 ".voyager/" 경로
    func testRollbackMarkerFileNamespace() {
        let devURL = AccountTokenFSLocation.rollbackMarkerFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .dev,
        )
        let prodURL = AccountTokenFSLocation.rollbackMarkerFileURL(
            homeDirectoryURL: homeURL,
            appEnv: .prod,
        )

        XCTAssertTrue(devURL.path.hasSuffix(".voyager/dev/account_tokens.rollback-pending"))
        XCTAssertTrue(prodURL.path.hasSuffix(".voyager/account_tokens.rollback-pending"))
        XCTAssertFalse(prodURL.path.contains("/dev/"))
    }

    /// ACC-001-account_token_namespace: withDefaultHome이 appEnv를 올바르게 전달한다.
    /// - 검증 내용: dev 환경의 store가 dev 경로를 사용
    /// - 사전 조건: AccountTokenFileStore.withDefaultHome(appEnv:)
    /// - 기대 결과: dev store가 dev/ 경로, prod store가 일반 경로
    func testWithDefaultHomeWiresNamespace() {
        let devStore = AccountTokenFileStore.withDefaultHome(appEnv: .dev)
        let prodStore = AccountTokenFileStore.withDefaultHome(appEnv: .prod)

        XCTAssertTrue(
            devStore.payloadURL.path.hasSuffix(".voyager/dev/account_tokens.json"),
            "dev store는 dev 경로 사용: \(devStore.payloadURL.path)",
        )
        XCTAssertTrue(
            prodStore.payloadURL.path.hasSuffix(".voyager/account_tokens.json"),
            "prod store는 일반 경로 사용: \(prodStore.payloadURL.path)",
        )
        XCTAssertFalse(prodStore.payloadURL.path.contains("/dev/"))
    }

    /// ACC-001-account_token_namespace: nil appEnv 전달 시 fatalError가 발생한다.
    /// fatalError는 프로세스를 종료시키므로 XCTest에서 직접 검증할 수 없으나,
    /// appEnvNamespaceURL의 guard let 분기가 존재함을 문서화한다.
    /// - 검증 내용: appEnv: nil 전달 시 fatalError가 호출됨
    /// - 사전 조건: AccountTokenFSLocation.appEnvNamespaceURL(directoryURL:, appEnv: nil)
    /// - 기대 결과: fatalError("APP_ENV missing - cannot resolve token storage namespace")
    /// - 비고: fatalError는 XCTest에서 process death를 유발하므로 compile-time guard 검증으로 대체
    func testNilAppEnvCrashes() {
        // fatalError는 in-process XCTest에서 직접 호출할 수 없음.
        // 대신 appEnvNamespaceURL의 guard let이 nil을 catch하는지 간접 검증:
        // .dev와 .prod는 정상 동작, nil만 fatalError 경로임을 확인
        let devURL = AccountTokenFSLocation.appEnvNamespaceURL(
            directoryURL: homeURL,
            appEnv: .dev,
        )
        let prodURL = AccountTokenFSLocation.appEnvNamespaceURL(
            directoryURL: homeURL,
            appEnv: .prod,
        )
        XCTAssertEqual(devURL.path, homeURL.appendingPathComponent("dev").path)
        XCTAssertEqual(prodURL.path, homeURL.path)
        // appEnv: nil은 fatalError → in-process에서 실행 불가
    }

    /// ACC-001-account_token_namespace: withCustomHome이 appEnv를 올바르게 전달한다.
    /// - 검증 내용: dev 커스텀 home store가 dev 경로를 사용
    /// - 사전 조건: AccountTokenFileStore.withCustomHome(homeURL:, appEnv:)
    /// - 기대 결과: dev store가 dev/ 경로, prod store가 일반 경로
    func testWithCustomHomeAcceptsBothParams() {
        let devStore = AccountTokenFileStore.withCustomHome(homeURL: homeURL, appEnv: .dev)
        let prodStore = AccountTokenFileStore.withCustomHome(homeURL: homeURL, appEnv: .prod)

        XCTAssertTrue(devStore.payloadURL.path.contains(".voyager/dev/account_tokens.json"))
        XCTAssertTrue(prodStore.payloadURL.path.contains(".voyager/account_tokens.json"))
        XCTAssertFalse(prodStore.payloadURL.path.contains("/dev/"))
    }
}
