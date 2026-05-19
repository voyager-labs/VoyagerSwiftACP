// swiftlint:disable file_length
// ONB-002: Core License 인증/권한 마이그레이션은 의도적으로 후속 범위다 (프로젝트 f946b2b9-0e41-4975-a55a-d5aacc11fcbd)
// 이 파일은 ONB-002 게이트웨이 에러 코드 매핑·재시도·복구 동작을 검증합니다.
// 범위 내: gateway 에러 코드 → reason 매핑, 재시도 스케줄링, 복구 경로.
// 범위 외(후속): Core License 인증 토큰 발급/갱신.

import ComposableArchitecture
@testable import VoyagerFeaturesBetaAccess
import XCTest

/// 스레드 안전한 호출 카운터 — 비동기 재시도 테스트에서 검증 클라이언트가 몇 번 호출되었는지 추적합니다.
///
/// `@unchecked Sendable`로 선언된 이유: Swift 6 strict concurrency에서
/// `@Sendable` 클로저 내부에서 mutable `var`를 직접 캡처할 수 없기 때문입니다.
/// `NSLock`으로 `_value` 접근을 보호하여 스레드 안전성을 수동으로 보장합니다.
/// 재시도 스케줄링이 깨지면 `counter.value` 단언이 실패하여 회귀를 감지합니다.
private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.withLock { _value }
    }

    func increment() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
}

// swiftlint:disable type_body_length
@MainActor
final class OnboardingBetaAccessFeatureTests: XCTestCase {
    // MARK: - ONB-002-start_access_unlock_recovery

    // 추적 사양: ONB-002-start_access_unlock_recovery
    // 검증 대상: 게이트웨이 에러 코드 → BetaAccessFailureReason 매핑,
    //   재시도 후 복구, 반복 재시도, 타임아웃 처리.
    // 계약 경계: gateway 에러 매핑·재시도 동작은 범위 내.
    //   Core License auth entitlement는 범위 외(후속).

    /// 잘못된 게이트웨이 URL이 전용 실패 사유로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: `invalid_gateway_url`은 구성 오류로 `.invalidGatewayUrl`이어야 한다.
    /// - 사전 조건: email/token이 입력된 상태에서 gatewayError(code: "invalid_gateway_url") 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .invalidGatewayUrl`, `isComplete == false`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 게이트웨이 주소 오류는 복구 안내가 필요하다.
    func testInvalidGatewayURLMapsToInvalidGatewayReason() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "invalid_gateway_url")
            })
        }

        await store.send(.emailChanged("tester@example.com")) { state in
            state.email = "tester@example.com"
        }

        await store.send(.tokenChanged("cbt-token")) { state in
            state.token = "cbt-token"
            state.reason = .none
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .invalidGatewayUrl
            state.isComplete = false
        }

        await store.finish()
    }

    /// 토큰 누락 게이트웨이 오류가 실패 상태로 내려가는지 확인한다.
    ///
    /// - 검증 내용: missing_token은 활성화가 아니라 검증 실패여야 한다.
    /// - 사전 조건: 토큰이 존재하더라도 게이트웨이가 missing_token을 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .missingToken`, `isComplete == false`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 서버가 토큰 누락을 알리면 실패로 표시한다.
    func testGatewayErrorMissingTokenMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "missing_token")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .missingToken
            state.isComplete = false
        }

        await store.finish()
    }

    /// invalid_token이 미활성 상태로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: 토큰이 무효하면 완료가 아니라 미활성 사유로 분류해야 한다.
    /// - 사전 조건: 게이트웨이가 `invalid_token` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .invalidToken`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 무효 토큰은 활성 권한이 아니다.
    func testGatewayErrorInvalidTokenMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "invalid_token")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .invalidToken
            state.isComplete = false
        }

        await store.finish()
    }

    /// invalid_request가 미활성 사유로 처리되는지 확인한다.
    ///
    /// - 검증 내용: 요청 형식이 잘못되면 활성화가 아니라 입력/요청 실패로 보여야 한다.
    /// - 사전 조건: 게이트웨이가 `invalid_request` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .invalidRequest`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 잘못된 요청은 활성 상태가 아니다.
    func testGatewayErrorInvalidRequestMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "invalid_request")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .invalidRequest
            state.isComplete = false
        }

        await store.finish()
    }

    /// 이메일 불일치가 미활성 사유로 보이는지 확인한다.
    ///
    /// - 검증 내용: 계정 이메일이 맞지 않으면 활성화하지 않아야 한다.
    /// - 사전 조건: 게이트웨이가 `email_mismatch` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .emailMismatch`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 소유자 불일치는 활성 권한이 아니다.
    func testGatewayErrorEmailMismatchMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "email_mismatch")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .emailMismatch
            state.isComplete = false
        }

        await store.finish()
    }

    /// 디바이스 불일치가 미활성 사유로 보이는지 확인한다.
    ///
    /// - 검증 내용: 다른 기기에서의 토큰은 활성화가 아니라 거부로 처리되어야 한다.
    /// - 사전 조건: 게이트웨이가 `device_mismatch` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .deviceMismatch`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 기기 소유권이 맞아야 활성이다.
    func testGatewayErrorDeviceMismatchMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "device_mismatch")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .deviceMismatch
            state.isComplete = false
        }

        await store.finish()
    }

    /// auth_backend_error가 실패 상태로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: 백엔드 인증 오류는 복구 가능한 실패로 보여야 한다.
    /// - 사전 조건: 게이트웨이가 `auth_backend_error` 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .authBackendError`, `isComplete == false`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 백엔드 오류는 재시도 흐름의 대상이다.
    func testGatewayErrorAuthBackendErrorMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "auth_backend_error")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .authBackendError
            state.isComplete = false
        }

        await store.finish()
    }

    /// 알 수 없는 게이트웨이 코드를 네트워크 오류로 폴백하는지 확인한다.
    ///
    /// - 검증 내용: 매핑되지 않은 코드는 안전하게 일반 네트워크 실패로 처리해야 한다.
    /// - 사전 조건: 게이트웨이가 임의의 unknown code 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .networkError`, `isComplete == false`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 알 수 없는 오류는 재시도 가능한 실패로 수렴한다.
    func testGatewayErrorUnknownCodeMapsToNetworkError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "some_unknown_code")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.finish()
    }

    /// 게이트웨이 실패 뒤 재시도가 성공으로 복구되는지 확인한다.
    ///
    /// - 검증 내용: 첫 실패 후 retry가 실제로 두 번째 검증을 호출해야 한다.
    /// - 사전 조건: 첫 호출은 auth_backend_error, 두 번째 호출은 성공.
    /// - 기대 결과: 첫 실패는 `.checkFailed`, 재시도 후 `.active` / `isComplete == true`, 시도 횟수는 2회.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 실패 후 복구 경로가 실제로 동작해야 한다.
    func testRetryAfterGatewayFailureSucceeds() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum == 1 {
                    throw BetaAccessVerificationError.gatewayError(code: "auth_backend_error")
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .authBackendError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(counter.value, 2)
        await store.finish()
    }

    /// 네트워크 실패 뒤 재시도가 복구되는지 확인한다.
    ///
    /// - 검증 내용: 첫 네트워크 실패 후 retry가 다시 검증을 수행해야 한다.
    /// - 사전 조건: 첫 호출은 `networkError`, 두 번째 호출은 성공.
    /// - 기대 결과: 첫 실패는 `.checkFailed`, 재시도 후 `.active` / `isComplete == true`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 네트워크 실패는 재시도로 회복된다.
    func testRetryAfterNetworkFailureRecovers() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum == 1 {
                    throw BetaAccessVerificationError.networkError
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        await store.finish()
    }

    /// 여러 번 실패한 뒤에도 재시도가 계속 복구 가능한지 확인한다.
    ///
    /// - 검증 내용: 실패가 반복돼도 마지막 성공 응답까지 retry가 유지되어야 한다.
    /// - 사전 조건: 첫 두 호출은 네트워크 실패, 세 번째 호출은 성공.
    /// - 기대 결과: 최종적으로 `.active`, `isComplete == true`, 시도 횟수는 3회.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 반복 실패 후에도 복구 시도는 유지된다.
    func testRepeatedRetryStillRecoverable() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum < 3 {
                    throw BetaAccessVerificationError.networkError
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(counter.value, 3)
        await store.finish()
    }

    /// timeout 코드가 네트워크 실패로 수렴하는지 확인한다.
    ///
    /// - 검증 내용: 타임아웃은 재시도 가능한 일반 실패로 처리되어야 한다.
    /// - 사전 조건: email/token이 입력되고 gatewayError(code: "timeout") 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .networkError`, `isComplete == false`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 시간 초과는 복구 가능한 네트워크 실패다.
    func testGatewayTimeoutMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "timeout")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.finish()
    }

    /// 실패 후 복구 흐름이 다시 시도 가능하게 유지되는지 확인한다.
    ///
    /// - 검증 내용: 타임아웃 실패 뒤 retry가 다시 성공 응답으로 이어져야 한다.
    /// - 사전 조건: 첫 호출은 timeout, 두 번째 호출은 성공.
    /// - 기대 결과: 첫 실패는 `.checkFailed`, 재시도 후 `.active` / `isComplete == true`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 실패 후 재시도 버튼이 살아 있어야 한다.
    func testRecoveryAfterFailedVerificationAllowsRetry() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum == 1 {
                    throw BetaAccessVerificationError.gatewayError(code: "timeout")
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        await store.finish()
    }
    // swiftlint:enable type_body_length
}
