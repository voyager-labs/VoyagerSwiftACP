// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-005-auth_network_client spec-owner 테스트

 AuthNetworkClient의 3개 메서드(exchangeHandoff, fetchAccessStatus, refreshToken)의
 계약을 mock closure로 검증한다. 네트워크 동작은 모의(mock)하고, 각 메서드가
 올바른 입출력 계약을 따르는지 확인한다.
 */

@MainActor
final class ACC005AuthNetworkClientTests: XCTestCase {
    // MARK: - ACC-005-exchange_handoff

    /// ACC-005-exchange_handoff: exchangeHandoff 성공 시 AccountSession을 반환한다.
    /// mock exchangeHandoff closure가 정상 응답을 반환할 때 호출자에게 세션이 전달되는지 검증한다.
    /// - 검증 내용: 반환된 AccountSession의 accessToken/refreshToken/status 일치
    /// - 사전 조건: AuthNetworkClient.exchangeHandoff mock이 유효한 AccountSession 반환
    /// - 기대 결과: 반환된 세션이 mock이 설정한 값과 일치
    func testExchangeHandoffSuccessReturnsSession() async throws {
        let expectedSession = AccountSession(
            accessToken: "ex-access",
            status: .coreLicenseActive,
            refreshToken: "ex-refresh",
        )
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in expectedSession },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )

        let session = try await client.exchangeHandoff("ticket", "state", .onboarding)

        XCTAssertEqual(session.accessToken, "ex-access")
        XCTAssertEqual(session.refreshToken, "ex-refresh")
        XCTAssertEqual(session.status, .coreLicenseActive)
    }

    /// ACC-005-exchange_handoff: ticketAlreadyUsed 에러를 전파한다.
    /// exchangeHandoff가 ticketAlreadyUsed 에러를 throw할 때 호출자에게 그대로 전파되는지 검증한다.
    /// - 검증 내용: AppHandoffExchangeError.ticketAlreadyUsed 전파
    /// - 사전 조건: mock exchangeHandoff가 ticketAlreadyUsed throw
    /// - 기대 결과: 동일한 ticketAlreadyUsed 에러가 throw됨
    func testExchangeHandoffTicketAlreadyUsedThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AppHandoffExchangeError.ticketAlreadyUsed },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.exchangeHandoff("ticket", "state", .onboarding)
            XCTFail("ticketAlreadyUsed 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AppHandoffExchangeError, .ticketAlreadyUsed)
        }
    }

    /// ACC-005-exchange_handoff: stateMismatch 에러를 전파한다.
    /// exchangeHandoff가 stateMismatch 에러를 throw할 때 호출자에게 그대로 전파되는지 검증한다.
    /// - 검증 내용: AppHandoffExchangeError.stateMismatch 전파
    /// - 사전 조건: mock exchangeHandoff가 stateMismatch throw
    /// - 기대 결과: 동일한 stateMismatch 에러가 throw됨
    func testExchangeHandoffStateMismatchThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AppHandoffExchangeError.stateMismatch },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.exchangeHandoff("ticket", "state", .onboarding)
            XCTFail("stateMismatch 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AppHandoffExchangeError, .stateMismatch)
        }
    }

    /// ACC-005-exchange_handoff: networkFailure 에러를 전파한다.
    /// exchangeHandoff가 networkFailure를 throw할 때 호출자에게 전파되는지 검증한다.
    /// - 검증 내용: AppHandoffExchangeError.networkFailure 전파
    /// - 사전 조건: mock exchangeHandoff가 networkFailure throw
    /// - 기대 결과: 동일한 networkFailure 에러가 throw됨
    func testExchangeHandoffNetworkFailureThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AppHandoffExchangeError.networkFailure },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.exchangeHandoff("ticket", "state", .onboarding)
            XCTFail("networkFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AppHandoffExchangeError, .networkFailure)
        }
    }

    /// ACC-005-exchange_handoff: invalidOrExpiredTicket 에러를 전파한다.
    /// exchangeHandoff가 invalidOrExpiredTicket 에러를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AppHandoffExchangeError.invalidOrExpiredTicket 전파
    /// - 사전 조건: mock exchangeHandoff가 invalidOrExpiredTicket throw
    /// - 기대 결과: 동일한 invalidOrExpiredTicket 에러가 throw됨
    func testExchangeHandoffInvalidTicketThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AppHandoffExchangeError.invalidOrExpiredTicket },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.exchangeHandoff("ticket", "state", .onboarding)
            XCTFail("invalidOrExpiredTicket 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AppHandoffExchangeError, .invalidOrExpiredTicket)
        }
    }

    // MARK: - ACC-005-refresh_token

    /// ACC-005-refresh_token: refreshToken 성공 시 새 AccountSession을 반환한다.
    /// mock refreshToken closure가 정상 응답을 반환할 때 호출자에게 세션이 전달되는지 검증한다.
    /// - 검증 내용: 반환된 AccountSession의 accessToken/refreshToken/status 일치
    /// - 사전 조건: AuthNetworkClient.refreshToken mock이 유효한 AccountSession 반환
    /// - 기대 결과: 반환된 세션이 mock이 설정한 값과 일치
    func testRefreshTokenSuccessReturnsNewSession() async throws {
        let newSession = AccountSession(
            accessToken: "refreshed-access",
            status: .none,
            refreshToken: "refreshed-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
        )
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { newSession },
        )

        let session = try await client.refreshToken()

        XCTAssertEqual(session.accessToken, "refreshed-access")
        XCTAssertEqual(session.refreshToken, "refreshed-refresh")
        XCTAssertEqual(session.status, .none)
    }

    /// ACC-005-refresh_token: networkFailure 에러를 전파한다.
    /// refreshToken이 networkFailure를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.networkFailure 전파
    /// - 사전 조건: mock refreshToken이 AccessError.networkFailure throw
    /// - 기대 결과: 동일한 networkFailure 에러가 throw됨
    func testRefreshTokenNetworkFailureThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.networkFailure },
        )

        do {
            _ = try await client.refreshToken()
            XCTFail("networkFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .networkFailure)
        }
    }

    /// ACC-005-refresh_token: decodingFailure 에러를 전파한다.
    /// refreshToken이 decodingFailure를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.decodingFailure 전파
    /// - 사전 조건: mock refreshToken이 AccessError.decodingFailure throw
    /// - 기대 결과: 동일한 decodingFailure 에러가 throw됨
    func testRefreshTokenDecodingFailureThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.decodingFailure },
        )

        do {
            _ = try await client.refreshToken()
            XCTFail("decodingFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .decodingFailure)
        }
    }

    /// ACC-005-refresh_token: refreshToken이 unauthorized를 throw한다.
    /// mock refreshToken closure가 unauthorized를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.unauthorized 전파
    /// - 사전 조건: mock refreshToken이 AccessError.unauthorized throw
    /// - 기대 결과: 동일한 unauthorized 에러가 throw됨
    func testRefreshTokenUnauthorizedThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.unauthorized },
        )

        do {
            _ = try await client.refreshToken()
            XCTFail("unauthorized 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .unauthorized)
        }
    }

    // MARK: - ACC-005-fetch_access_status

    /// ACC-005-fetch_access_status: fetchAccessStatus 성공 시 AccessStatusResponse를 반환한다.
    /// mock fetchAccessStatus closure가 정상 응답을 반환할 때 호출자에게 응답이 전달되는지 검증한다.
    /// - 검증 내용: 반환된 AccessStatusResponse의 hasAccess/status/currentPeriodEnd 일치
    /// - 사전 조건: AuthNetworkClient.fetchAccessStatus mock이 유효한 AccessStatusResponse 반환
    /// - 기대 결과: 반환된 응답이 mock이 설정한 값과 일치
    func testFetchAccessStatusSuccess() async throws {
        let expectedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let expectedResponse = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            currentPeriodEnd: expectedDate,
            source: "polar",
        )
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { expectedResponse },
            refreshToken: { throw AccessError.notConfigured },
        )

        let response = try await client.fetchAccessStatus()

        XCTAssertTrue(response.hasAccess)
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.reason, "active_entitlement")
        XCTAssertEqual(response.productKey, "core")
        XCTAssertEqual(response.currentPeriodEnd?.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(response.source, "polar")
    }

    /// ACC-005-fetch_access_status: fetchAccessStatus가 networkFailure를 throw한다.
    /// mock fetchAccessStatus closure가 networkFailure를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.networkFailure 전파
    /// - 사전 조건: mock fetchAccessStatus가 AccessError.networkFailure throw
    /// - 기대 결과: 동일한 networkFailure 에러가 throw됨
    func testFetchAccessStatusNetworkFailureThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.networkFailure },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.fetchAccessStatus()
            XCTFail("networkFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .networkFailure)
        }
    }

    /// ACC-005-fetch_access_status: fetchAccessStatus가 decodingFailure를 throw한다.
    /// mock fetchAccessStatus closure가 decodingFailure를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.decodingFailure 전파
    /// - 사전 조건: mock fetchAccessStatus가 AccessError.decodingFailure throw
    /// - 기대 결과: 동일한 decodingFailure 에러가 throw됨
    func testFetchAccessStatusDecodingFailureThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.decodingFailure },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.fetchAccessStatus()
            XCTFail("decodingFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .decodingFailure)
        }
    }

    /// ACC-005-fetch_access_status: fetchAccessStatus가 notConfigured를 throw한다.
    /// mock fetchAccessStatus closure가 notConfigured를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.notConfigured 전파
    /// - 사전 조건: mock fetchAccessStatus가 AccessError.notConfigured throw
    /// - 기대 결과: 동일한 notConfigured 에러가 throw됨
    func testFetchAccessStatusNotConfiguredThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.fetchAccessStatus()
            XCTFail("notConfigured 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .notConfigured)
        }
    }

    /// ACC-005-fetch_access_status: fetchAccessStatus가 unauthorized를 throw한다.
    /// mock fetchAccessStatus closure가 unauthorized를 throw할 때 전파되는지 검증한다.
    /// - 검증 내용: AccessError.unauthorized 전파
    /// - 사전 조건: mock fetchAccessStatus가 AccessError.unauthorized throw
    /// - 기대 결과: 동일한 unauthorized 에러가 throw됨
    func testFetchAccessStatusUnauthorizedThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.unauthorized },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.fetchAccessStatus()
            XCTFail("unauthorized 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .unauthorized)
        }
    }

    // MARK: - ACC-005-test_value

    /// ACC-005-test_value: testValue의 모든 closure가 notConfigured를 throw한다.
    /// DependencyKey.testValue가 안전한 기본값을 제공하는지 검증한다.
    /// - 검증 내용: exchangeHandoff/fetchAccessStatus/refreshToken 모두 notConfigured throw
    /// - 사전 조건: AuthNetworkClient.testValue 사용
    /// - 기대 결과: 3개 메서드 모두 AccessError.notConfigured throw
    func testTestValueIsSafeDefault() async {
        let client = AuthNetworkClient.testValue

        do {
            _ = try await client.exchangeHandoff("t", "s", .onboarding)
            XCTFail("testValue exchangeHandoff가 notConfigured를 throw해야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .notConfigured)
        }

        do {
            _ = try await client.fetchAccessStatus()
            XCTFail("testValue fetchAccessStatus가 notConfigured를 throw해야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .notConfigured)
        }

        do {
            _ = try await client.refreshToken()
            XCTFail("testValue refreshToken이 notConfigured를 throw해야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .notConfigured)
        }
    }
}

// swiftlint:enable force_unwrapping
