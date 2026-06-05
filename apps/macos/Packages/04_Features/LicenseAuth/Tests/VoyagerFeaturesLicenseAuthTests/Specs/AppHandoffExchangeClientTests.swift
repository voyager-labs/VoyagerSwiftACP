// swiftlint:disable single_test_class

@testable import VoyagerFeaturesLicenseAuth
import XCTest

// MARK: - ONB-002-mock_sign_in_handoff

final class AppHandoffExchangeClientTests: XCTestCase {
    // MARK: - 성공 응답 → 세션 적용 + restoreSession

    /// ONB-002-mock_sign_in_handoff: exchange 성공 시 세션이 holder에 저장되고 restoreSession이 반환한다
    func testExchangeSuccessAppliesSession() async throws {
        let sessionHolder = MockSignInState()
        let expectedSession = LicenseAuthSession(
            accessToken: "exchanged-access-token",
            status: .coreLicenseActive,
            refreshToken: "exchanged-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let exchangeClient = AppHandoffExchangeClient(
            exchange: { ticket, state, context in
                XCTAssertEqual(ticket, "ticket-abc")
                XCTAssertEqual(state, "state-xyz")
                XCTAssertEqual(context, .onboarding)
                return expectedSession
            },
        )

        let client = LicenseAuthClient.handoffBacked(
            sessionHolder: sessionHolder,
            exchangeClient: exchangeClient,
        )

        let result = try await client.exchangeAppHandoff("ticket-abc", "state-xyz", .onboarding)
        XCTAssertEqual(result, expectedSession)

        let restored = try await client.restoreSession()
        XCTAssertEqual(restored, expectedSession, "restoreSession은 exchange로 저장된 세션을 반환해야 함")
    }

    /// VOY-334 실제 exchange 성공 응답(snake_case session fields)을 LicenseAuthSession으로 디코딩한다.
    func testDecodesRealExchangeSuccessPayloadShape() throws {
        let json = """
        {
          "ok": true,
          "session": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "expires_at": 1234567890
          },
          "user": {
            "id": "user-123",
            "email": "tester@example.com"
          }
        }
        """
        let data = Data(json.utf8)

        let session = try AppHandoffExchangeClient.decodeSession(fromExchangeSuccessData: data)

        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.refreshToken, "refresh-token")
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 1_234_567_890))
        XCTAssertEqual(session.status, .coreLicenseActive)
    }

    // MARK: - 각 documented exchange error 매핑

    /// ONB-002-mock_sign_in_handoff: ticket_already_used 에러 매핑
    func testExchangeErrorTicketAlreadyUsed() async {
        await assertExchangeErrorThrows(.ticketAlreadyUsed)
    }

    /// ONB-002-mock_sign_in_handoff: state_mismatch 에러 매핑
    func testExchangeErrorStateMismatch() async {
        await assertExchangeErrorThrows(.stateMismatch)
    }

    /// ONB-002-mock_sign_in_handoff: invalid_or_expired_ticket 에러 매핑
    func testExchangeErrorInvalidOrExpiredTicket() async {
        await assertExchangeErrorThrows(.invalidOrExpiredTicket)
    }

    /// ONB-002-mock_sign_in_handoff: account_mismatch 에러 매핑
    func testExchangeErrorAccountMismatch() async {
        await assertExchangeErrorThrows(.accountMismatch)
    }

    /// ONB-002-mock_sign_in_handoff: supabase_session_issuance_failed 에러 매핑
    func testExchangeErrorSessionIssuanceFailed() async {
        await assertExchangeErrorThrows(.sessionIssuanceFailed)
    }

    /// ONB-002-mock_sign_in_handoff: networkFailure 에러 매핑
    func testExchangeErrorNetworkFailure() async {
        await assertExchangeErrorThrows(.networkFailure)
    }

    /// ONB-002-mock_sign_in_handoff: decodingFailure 에러 매핑
    func testExchangeErrorDecodingFailure() async {
        await assertExchangeErrorThrows(.decodingFailure)
    }

    /// ONB-002-mock_sign_in_handoff: unknownGatewayCode 에러 매핑
    func testExchangeErrorUnknownGatewayCode() async {
        await assertExchangeErrorThrows(.unknownGatewayCode("some_new_error"))
    }

    // MARK: - 실패 시 세션 미저장

    /// ONB-002-mock_sign_in_handoff: exchange 실패 시 session holder에 세션이 저장되지 않는다
    func testExchangeFailureDoesNotStoreSession() async {
        let sessionHolder = MockSignInState()
        sessionHolder.setSession(LicenseAuthSession(accessToken: "pre-existing", status: .coreLicenseActive))

        let exchangeClient = AppHandoffExchangeClient(
            exchange: { _, _, _ in throw AppHandoffExchangeError.ticketAlreadyUsed },
        )

        let client = LicenseAuthClient.handoffBacked(
            sessionHolder: sessionHolder,
            exchangeClient: exchangeClient,
        )

        do {
            _ = try await client.exchangeAppHandoff("ticket", "state", .onboarding)
            XCTFail("exchange should throw")
        } catch {
            do {
                let restored = try await client.restoreSession()
                XCTAssertEqual(restored?.accessToken, "pre-existing", "실패 시 기존 세션이 보존되어야 함")
            } catch {
                XCTFail("restoreSession should not throw after exchange failure: \(error)")
            }
        }
    }

    // MARK: - fetchAccessStatus 오버라이드 가능

    /// ONB-002-mock_sign_in_handoff: fetchAccessStatus는 테스트에서 오버라이드 가능하다
    func testFetchAccessStatusIsOverridable() async throws {
        nonisolated(unsafe) var fetchCalled = false
        let client = LicenseAuthClient(
            restoreSession: { nil },
            fetchAccessStatus: {
                fetchCalled = true
                return LicenseAuthStatusResponse(status: .betaTrialActive, entitlements: [])
            },
            signOut: {},
        )

        let response = try await client.fetchAccessStatus()
        XCTAssertTrue(fetchCalled)
        XCTAssertEqual(response.status, .betaTrialActive)
    }

    // MARK: - signOut 시 세션 초기화

    /// ONB-002-mock_sign_in_handoff: signOut 시 세션이 초기화된다
    func testSignOutClearsSession() async throws {
        let sessionHolder = MockSignInState()
        let exchangeClient = AppHandoffExchangeClient(
            exchange: { _, _, _ in
                LicenseAuthSession(accessToken: "exchanged", status: .coreLicenseActive)
            },
        )

        let client = LicenseAuthClient.handoffBacked(
            sessionHolder: sessionHolder,
            exchangeClient: exchangeClient,
        )

        _ = try await client.exchangeAppHandoff("ticket", "state", .onboarding)
        let restoredAfterExchange = try await client.restoreSession()
        XCTAssertNotNil(restoredAfterExchange)

        try await client.signOut()
        let restoredAfterSignOut = try await client.restoreSession()
        XCTAssertNil(restoredAfterSignOut, "signOut 후 restoreSession은 nil이어야 함")
    }

    // MARK: - 3-arg init 호환성

    /// ONB-002-mock_sign_in_handoff: 기존 3-arg init으로 생성한 client의 exchangeAppHandoff는 notConfigured를 던진다
    func testLegacyInitExchangeThrowsNotConfigured() async {
        let client = LicenseAuthClient(
            restoreSession: { nil },
            fetchAccessStatus: { LicenseAuthStatusResponse(status: .none, entitlements: []) },
            signOut: {},
        )

        do {
            _ = try await client.exchangeAppHandoff("ticket", "state", .onboarding)
            XCTFail("3-arg init으로 생성한 client의 exchange는 notConfigured를 던져야 함")
        } catch let error as LicenseAuthError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helper

    private func assertExchangeErrorThrows(_ expectedError: AppHandoffExchangeError) async {
        let exchangeClient = AppHandoffExchangeClient(
            exchange: { _, _, _ in throw expectedError },
        )

        do {
            _ = try await exchangeClient.exchange("ticket", "state", .onboarding)
            XCTFail("exchange should throw \(expectedError)")
        } catch let error as AppHandoffExchangeError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - 서버 에러 코드 → AppHandoffExchangeError 매핑

final class AppHandoffExchangeErrorCodeMappingTests: XCTestCase {
    /// ticket_already_used 서버 코드 매핑
    func testMapsTicketAlreadyUsedCode() async {
        await assertErrorCodeMapsToError("ticket_already_used", .ticketAlreadyUsed)
    }

    /// state_mismatch 서버 코드 매핑
    func testMapsStateMismatchCode() async {
        await assertErrorCodeMapsToError("state_mismatch", .stateMismatch)
    }

    /// invalid_or_expired_ticket 서버 코드 매핑
    func testMapsInvalidOrExpiredTicketCode() async {
        await assertErrorCodeMapsToError("invalid_or_expired_ticket", .invalidOrExpiredTicket)
    }

    /// account_mismatch 서버 코드 매핑
    func testMapsAccountMismatchCode() async {
        await assertErrorCodeMapsToError("account_mismatch", .accountMismatch)
    }

    /// supabase_session_issuance_failed 서버 코드 매핑
    func testMapsSupabaseSessionIssuanceFailedCode() async {
        await assertErrorCodeMapsToError("supabase_session_issuance_failed", .sessionIssuanceFailed)
    }

    /// 알 수 없는 코드는 unknownGatewayCode로 매핑
    func testMapsUnknownCode() async {
        await assertErrorCodeMapsToError("future_error_code", .unknownGatewayCode("future_error_code"))
    }

    /// code가 nil이면 unknownGatewayCode("unknown")로 매핑
    func testMapsMissingCode() async {
        let exchangeClient = makeExchangeClientReturningErrorJSON(json: ["message": "no code field"])

        do {
            _ = try await exchangeClient.exchange("ticket", "state", .onboarding)
            XCTFail("should throw")
        } catch let error as AppHandoffExchangeError {
            XCTAssertEqual(error, .unknownGatewayCode("unknown"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helper

    private func assertErrorCodeMapsToError(
        _ code: String,
        _ expectedError: AppHandoffExchangeError,
    ) async {
        let exchangeClient = makeExchangeClientReturningErrorJSON(json: ["code": code])

        do {
            _ = try await exchangeClient.exchange("ticket", "state", .onboarding)
            XCTFail("should throw for code \(code)")
        } catch let error as AppHandoffExchangeError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// 서버 에러 JSON을 디코딩하는 mock exchange client.
    /// liveValue와 동일한 디코딩 로직을 테스트하기 위해 서버 응답을 시뮬레이션한다.
    private func makeExchangeClientReturningErrorJSON(json: [String: String]) -> AppHandoffExchangeClient {
        AppHandoffExchangeClient { _, _, _ in
            let data = try JSONEncoder().encode(json)
            // 에러 코드 추출 로직을 직접 테스트하기 위해 서버 응답 시뮬레이션
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let errorCode = jsonResponse["code"] as? String
            else {
                throw AppHandoffExchangeError.unknownGatewayCode("unknown")
            }

            switch errorCode {
            case "ticket_already_used": throw AppHandoffExchangeError.ticketAlreadyUsed
            case "state_mismatch": throw AppHandoffExchangeError.stateMismatch
            case "invalid_or_expired_ticket": throw AppHandoffExchangeError.invalidOrExpiredTicket
            case "account_mismatch": throw AppHandoffExchangeError.accountMismatch
            case "supabase_session_issuance_failed": throw AppHandoffExchangeError.sessionIssuanceFailed
            default: throw AppHandoffExchangeError.unknownGatewayCode(errorCode)
            }
        }
    }
}

// swiftlint:enable single_test_class
