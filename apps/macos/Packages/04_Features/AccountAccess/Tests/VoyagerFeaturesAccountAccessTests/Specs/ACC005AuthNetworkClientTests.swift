@preconcurrency import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-005-auth_network_client spec-owner 테스트

 AuthNetworkClient의 메서드(exchangeHandoff, fetchAccessStatus, bindDevice, refreshToken)의
 계약을 mock closure로 검증한다. 네트워크 동작은 모의(mock)하고, 각 메서드가
 올바른 입출력 계약을 따르는지 확인한다.
 */

@MainActor
final class ACC005AuthNetworkClientTests: XCTestCase {
    private struct LegacySyncUnknownError: Error {}

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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
            refreshToken: { throw AccessError.decodingFailure },
        )

        do {
            _ = try await client.refreshToken()
            XCTFail("decodingFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .decodingFailure)
        }
    }

    /// ACC-005-refresh_token: malformed 200 응답은 decodingFailure로 매핑한다.
    func testRefreshResponseDecodingFailureMapsToAccessError() {
        do {
            _ = try AuthNetworkClient.decodeRefreshSuccessResponse(Data("{}".utf8))
            XCTFail("malformed refresh response는 decodingFailure를 throw해야 함")
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
        let expectedResponse = AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", reason: "active_entitlement",
        productKey: "core",
        currentPeriodEnd: expectedDate,
        source: "polar",)
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { expectedResponse },
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.fetchAccessStatus()
            XCTFail("decodingFailure 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AccessError, .decodingFailure)
        }
    }

    /// ACC-005-fetch_access_status: malformed 200 응답은 decodingFailure로 매핑한다.
    func testAccessStatusDecodingFailureMapsToAccessError() {
        do {
            _ = try AuthNetworkClient.decodeAccessStatusResponse(Data("{}".utf8))
            XCTFail("malformed access status response는 decodingFailure를 throw해야 함")
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            bindDevice: { _ in DeviceBindingResponse(ok: true) },
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

    /// ACC-005-bind_device: bindDevice 성공 시 DeviceBindingResponse를 반환한다.
    /// mock bindDevice closure가 정상 응답을 반환할 때 호출자에게 응답이 전달되는지 검증한다.
    func testBindDeviceSuccessReturnsResponse() async throws {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            bindDevice: { request in
                XCTAssertEqual(request.deviceId, "device-1")
                return DeviceBindingResponse(ok: true)
            },
            refreshToken: { throw AccessError.notConfigured },
        )

        let response = try await client.bindDevice(DeviceBindingRequest(deviceId: "device-1"))

        XCTAssertTrue(response.ok)
    }

    /// ACC-005-bind_device: bindDevice가 seat capacity 오류를 전파한다.
    func testBindDeviceSeatCapacityExceededThrows() async {
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            bindDevice: { _ in throw DeviceBindingError.seatCapacityExceeded },
            refreshToken: { throw AccessError.notConfigured },
        )

        do {
            _ = try await client.bindDevice(DeviceBindingRequest(deviceId: "device-1"))
            XCTFail("seatCapacityExceeded 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? DeviceBindingError, .seatCapacityExceeded)
        }
    }

    /// ACC-005-bind_device: Gateway request body는 snake_case 필드를 사용한다.
    func testDeviceBindingRequestEncodesSnakeCaseFields() throws {
        let request = DeviceBindingRequest(
            deviceId: "device-1",
            deviceName: "Mac Studio",
            appVersion: "1.2.3",
            osVersion: "Version 15.0",
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["device_id"], "device-1")
        XCTAssertEqual(object["device_name"], "Mac Studio")
        XCTAssertEqual(object["app_version"], "1.2.3")
        XCTAssertEqual(object["os_version"], "Version 15.0")
        XCTAssertNil(object["deviceId"])
    }

    /// ACC-005-bind_device: HTTP status/error code를 recovery 가능한 binding error로 매핑한다.
    func testMappedDeviceBindingErrors() {
        XCTAssertEqual(
            mappedDeviceBindingError(statusCode: 401, code: "missing_token"),
            .unauthorized,
        )
        XCTAssertEqual(
            mappedDeviceBindingError(statusCode: 403, code: "no_active_access"),
            .noActiveAccess,
        )
        XCTAssertEqual(
            mappedDeviceBindingError(statusCode: 409, code: "seat_capacity_exceeded"),
            .seatCapacityExceeded,
        )
        XCTAssertEqual(
            mappedDeviceBindingError(statusCode: 503, code: "device_binding_failed"),
            .serverFailure,
        )
    }

    /// ACC-005-auth_network_client: legacy sync는 typed failure를 recovery policy에 맞게 구분한다.
    /// - 검증 내용: unauthorized는 invalidCredential, capability absence는 capabilityMiss, network/decoding/unknown은
    /// upstream(0), storage는 storageFailure다.
    /// - 사전 조건: AccessError, DeviceBindingError, SessionSyncError와 unknown error를 각각 mapping helper에 전달한다.
    /// - 기대 결과: cancellation 외 typed failure가 capabilityMiss로 뭉개지지 않는다.
    func testLegacySessionSyncErrorMappingPreservesFailureKinds() {
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: AccessError.unauthorized), .invalidCredential)
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: AccessError.notConfigured), .capabilityMiss)
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: DeviceBindingError.notConfigured), .capabilityMiss)
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: AccessError.networkFailure), .upstream(0))
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: AccessError.decodingFailure), .upstream(0))
        XCTAssertEqual(
            AuthNetworkClient.legacySessionSyncError(for: AccessError.unknownGatewayCode("legacy")),
            .upstream(0),
        )
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: SessionSyncError.storageFailure), .storageFailure)
        XCTAssertEqual(AuthNetworkClient.legacySessionSyncError(for: LegacySyncUnknownError()), .upstream(0))
    }

    /// ACC-005-auth_network_client: legacy refresh 결과는 CAS로 저장한 session expiry를 전달한다.
    /// - 검증 내용: refresh intent의 legacy result가 rotated status와 refreshed session expiry를 함께 보존한다.
    /// - 사전 조건: expiry가 없는 refresh 응답과 현재 source token file.
    /// - 기대 결과: SessionSyncResult.sessionExpiresAt이 CAS에 실제 저장된 fallback expiry와 일치한다.
    func testLegacyRefreshResultIncludesPersistedSessionExpiry() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let source = AccountTokensFile(
            updatedAtMs: 1,
            accessToken: "source-access-token",
            accessTokenExpiresAtMs: 1_700_000_000_000,
            accessTokenExpiresIn: 900_000,
            refreshToken: "source-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_000_000,
        )
        try await store.write(source)
        let refreshedSession = AccountSession(
            accessToken: "rotated-access-token",
            status: .coreLicenseActive,
            refreshToken: "rotated-refresh-token",
            expiresAt: nil,
        )
        let persistedSession = try await AuthNetworkClient.persistLegacyRefreshedSession(
            (session: refreshedSession, source: source),
            store: store,
        )
        let storedValue = try await store.read()
        let storedTokens = try XCTUnwrap(storedValue)
        let storedSession = try XCTUnwrap(AccountTokenSessionMapper.tokensFileToSession(storedTokens))

        let result = AuthNetworkClient.legacySessionSyncResult(
            intent: .refresh,
            access: AccessStatusResponse(hasAccess: true, status: "active"),
            outcome: .bound,
            refreshedSession: persistedSession,
        )

        XCTAssertEqual(result.sessionStatus, .rotated)
        XCTAssertNotNil(result.sessionExpiresAt)
        XCTAssertEqual(result.sessionExpiresAt, persistedSession.expiresAt)
        XCTAssertEqual(result.sessionExpiresAt, storedSession.expiresAt)
    }

    /// ACC-005-auth_network_client: legacy refresh CAS 불일치는 expiry 결과를 만들지 않는다.
    /// - 검증 내용: source token이 교체된 뒤의 refresh commit을 storage failure로 거부한다.
    /// - 사전 조건: refresh가 읽은 source와 현재 저장된 token file이 다르다.
    /// - 기대 결과: storageFailure를 throw하고 현재 token file을 유지한다.
    func testLegacyRefreshCasMismatchRejectsExpiryResult() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let source = AccountTokensFile(
            updatedAtMs: 1,
            accessToken: "source-access-token",
            accessTokenExpiresAtMs: 1_700_000_000_000,
            accessTokenExpiresIn: 900_000,
            refreshToken: "source-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_000_000,
        )
        let current = AccountTokensFile(
            updatedAtMs: 2,
            accessToken: "newer-access-token",
            accessTokenExpiresAtMs: 1_700_000_000_000,
            accessTokenExpiresIn: 900_000,
            refreshToken: "source-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_000_000,
        )
        try await store.write(current)
        let refreshedSession = AccountSession(
            accessToken: "rotated-access-token",
            status: .coreLicenseActive,
            refreshToken: "rotated-refresh-token",
            expiresAt: nil,
        )

        do {
            _ = try await AuthNetworkClient.persistLegacyRefreshedSession(
                (session: refreshedSession, source: source),
                store: store,
            )
            XCTFail("CAS mismatch는 storageFailure를 throw해야 함")
        } catch {
            XCTAssertEqual(error as? SessionSyncError, .storageFailure)
        }

        let storedTokens = try await store.read()
        XCTAssertEqual(storedTokens, current)
    }

    /// ACC-005-auth_network_client: legacy sync의 device-binding unauthorized는 credential recovery를 시작한다.
    func testLegacyDeviceBindingUnauthorizedMapsToInvalidCredential() {
        XCTAssertEqual(
            AuthNetworkClient.legacySessionSyncError(for: .unauthorized),
            .invalidCredential,
        )
        XCTAssertNil(AuthNetworkClient.legacySessionSyncError(for: .seatCapacityExceeded))
    }

    /// ACC-005-auth_network_client: 취소된 네트워크 작업은 재시도 가능한 네트워크 오류로 변환하지 않는다.
    func testCancellationErrorsRemainCancellation() {
        XCTAssertTrue(AuthNetworkClient.isCancellationError(CancellationError()))
        XCTAssertTrue(AuthNetworkClient.isCancellationError(URLError(.cancelled)))
        XCTAssertFalse(AuthNetworkClient.isCancellationError(URLError(.timedOut)))
        XCTAssertNil(AuthNetworkClient.exchangeError(for: CancellationError()))
        XCTAssertNil(AuthNetworkClient.exchangeError(for: URLError(.cancelled)))
        XCTAssertEqual(AuthNetworkClient.exchangeError(for: URLError(.timedOut)), .networkFailure)
    }
}

extension ACC005AuthNetworkClientTests {
    // MARK: - ACC-005-auth_network_client

    /// ACC-005-auth_network_client: rotated token persistence는 기존 session binding을 유지한다.
    /// refresh session-sync가 새 token을 저장해도 trusted snapshot 소유 binding이 바뀌지 않는지 검증한다.
    /// - 검증 내용: rotated token file이 access/refresh token을 갱신하고 previous sessionBindingID를 보존한다.
    /// - 사전 조건: binding을 가진 current token file과 rotated session-sync response가 있다.
    /// - 기대 결과: CAS 저장 뒤 token은 rotated 값이고 sessionBindingID는 source binding과 같다.
    func testSessionSyncRotationPreservesPreviousSessionBinding() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let binding = UUID()
        let source = AccountTokensFile(
            updatedAtMs: 1,
            accessToken: "source-access-token",
            accessTokenExpiresAtMs: 1_700_000_000_000,
            accessTokenExpiresIn: 900_000,
            refreshToken: "source-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_000_000,
            sessionBindingID: binding,
        )
        try await store.write(source)

        let result = try await AuthNetworkClient.sessionSyncResult(
            data: rotatedSessionSyncResponseData(),
            intent: .refresh,
            source: source,
            store: store,
        )

        let storedValue = try await store.read()
        let persisted = try XCTUnwrap(storedValue)
        XCTAssertEqual(result.sessionStatus, .rotated)
        XCTAssertEqual(result.syncStatus, .complete)
        XCTAssertEqual(result.accessStatus, AccessStatusResponse(hasAccess: true, status: "active"))
        XCTAssertEqual(result.sessionExpiresAt, Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertEqual(persisted.accessToken, "rotated-access-token")
        XCTAssertEqual(persisted.refreshToken, "rotated-refresh-token")
        XCTAssertEqual(persisted.sessionBindingID, binding)
    }

    /// ACC-005-auth_network_client: stale source는 rotated token CAS를 거부한다.
    /// 동시 session-sync가 더 최신 token을 저장한 뒤 이전 source가 rotation을 commit하지 못하는지 검증한다.
    /// - 검증 내용: rotated file의 CAS가 false를 반환하고 더 최신 persisted token/binding을 유지한다.
    /// - 사전 조건: rotation source와 다른 current token file이 이미 storage에 있다.
    /// - 기대 결과: stale rotated token은 저장되지 않고 current token의 binding이 보존된다.
    func testSessionSyncRotationRejectsStaleSourceCas() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let sourceBinding = UUID()
        let currentBinding = UUID()
        let source = AccountTokensFile(
            updatedAtMs: 1,
            accessToken: "source-access-token",
            accessTokenExpiresAtMs: 1_700_000_000_000,
            accessTokenExpiresIn: 900_000,
            refreshToken: "source-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_000_000,
            sessionBindingID: sourceBinding,
        )
        let current = AccountTokensFile(
            updatedAtMs: 2,
            accessToken: "current-access-token",
            accessTokenExpiresAtMs: 1_700_000_100_000,
            accessTokenExpiresIn: 900_000,
            refreshToken: "current-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_100_000,
            sessionBindingID: currentBinding,
        )
        try await store.write(current)

        do {
            _ = try await AuthNetworkClient.sessionSyncResult(
                data: rotatedSessionSyncResponseData(),
                intent: .refresh,
                source: source,
                store: store,
            )
            XCTFail("stale source rotation은 storageFailure를 throw해야 함")
        } catch {
            XCTAssertEqual(error as? SessionSyncError, .storageFailure)
        }

        let persisted = try await store.read()
        XCTAssertEqual(persisted, current)
    }

    private func rotatedSessionSyncResponseData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(SessionSyncResponse(
            syncStatus: .complete,
            session: .init(
                status: .rotated,
                accessToken: "rotated-access-token",
                refreshToken: "rotated-refresh-token",
                expiresAt: 1_700_003_600,
                expiresIn: 3_600_000,
                refreshTokenExpiresAt: 1_702_592_000,
            ),
            access: AccessStatusResponse(hasAccess: true, status: "active"),
            device: .init(outcome: .bound, connectedDeviceAvailability: .available),
            partial: nil,
        ))
    }
}

extension ACC005AuthNetworkClientTests {
    func testGatewayEnvironmentCanonicalizesEquivalentGatewayURLs() {
        let cases: [(raw: String, binding: String)] = [
            (" HTTPS://Gateway.Example.com:443/a//b/../c/ ", "https://gateway.example.com/a/c"),
            ("http://GATEWAY.example.com:80/", "http://gateway.example.com/"),
            ("https://gateway.example.com:8443/a/", "https://gateway.example.com:8443/a"),
            ("https://gateway.example.com/a/./b", "https://gateway.example.com/a/b"),
        ]

        for testCase in cases {
            let environment = GatewayEnvironment(rawValue: testCase.raw)

            XCTAssertEqual(environment.binding, testCase.binding)
            XCTAssertEqual(environment.baseURL?.absoluteString, testCase.binding)
        }
    }

    func testGatewayEnvironmentRejectsUnsafeOrInvalidURLs() {
        let invalidURLs = [
            "gateway.example.com",
            "ftp://gateway.example.com",
            "https:///missing-host",
            "https://user@gateway.example.com",
            "https://gateway.example.com/path?query=value",
            "https://gateway.example.com/path#fragment",
        ]

        for rawURL in invalidURLs {
            let environment = GatewayEnvironment(rawValue: rawURL)

            XCTAssertNil(environment.baseURL)
            XCTAssertEqual(environment.binding, "")
        }
    }

    /// ACC-005-test_value: testValue의 모든 closure가 notConfigured를 throw한다.
    /// DependencyKey.testValue가 안전한 기본값을 제공하는지 검증한다.
    /// - 검증 내용: exchangeHandoff/fetchAccessStatus/bindDevice/refreshToken 모두 notConfigured throw
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

        do {
            _ = try await client.bindDevice(DeviceBindingRequest(deviceId: "device-1"))
            XCTFail("testValue bindDevice가 notConfigured를 throw해야 함")
        } catch {
            XCTAssertEqual(error as? DeviceBindingError, .notConfigured)
        }
    }
}
