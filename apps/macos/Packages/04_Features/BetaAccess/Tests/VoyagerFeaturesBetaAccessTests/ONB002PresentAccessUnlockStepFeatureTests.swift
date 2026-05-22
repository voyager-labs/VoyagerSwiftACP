// swiftlint:disable file_length
// ONB-002: Core License 인증/권한 마이그레이션은 후속 범위 (프로젝트 f946b2b9-0e41-4975-a55a-d5aacc11fcbd)
// 이 파일은 ONB-002 BetaAccess 리듀서의 상태 표시·검증 결과 적용·복구 동작을 검증합니다.
// 범위 내: BetaAccess 리듀서 상태/상태 메시지, 검증 요청·응답, 재시도, 입력 가드,
//   게이트웨이 에러 코드 매핑, 재시도 스케줄링, 복구 경로.
// 범위 외(후속): Core License 인증/권한 엔타이틀먼트 마이그레이션.

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
final class ONB002PresentAccessUnlockStepFeatureTests: XCTestCase { // swiftlint:disable:this type_name
    // MARK: - ONB-002-show_access_unlock_status

    // 추적 사양: ONB-002-show_access_unlock_status
    // 검증 대상: BetaAccess 리듀서가 초기/미활성 상태를 올바르게 표시하는지,
    //   입력 가드가 네트워크 호출을 차단하는지, 로딩 상태 전환이 정상인지.
    // 계약 경계: 로컬 BetaAccess 상태·상태 메시지·입력 가드는 범위 내.
    //   Core License/auth 엔타이틀먼트 마이그레이션은 범위 외(후속).

    /// 입력이 비어 있으면 검증을 시작하지 않는지 확인한다.
    ///
    /// - 검증 내용: `checkTapped`가 와도 입력 누락이면 즉시 가드되어야 한다.
    /// - 사전 조건: email/token이 모두 비어 있는 초기 상태.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isVerifying == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 누락 입력은 네트워크 요청보다 먼저 차단된다.
    func testMissingInputDoesNotVerify() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.checkTapped)

        XCTAssertEqual(store.state.status, .notActive)
        XCTAssertEqual(store.state.reason, .missingInput)

        await store.finish()
    }

    /// 초기 상태가 미활성 기본값인지 확인한다.
    ///
    /// - 검증 내용: 기본 생성 상태가 첫 진입 화면 기준과 일치해야 한다.
    /// - 사전 조건: `BetaAccessFeature.State()` 사용.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isVerifying == false`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 온보딩 초기 화면의 기준 상태.
    func testInitialStateShowsNotActiveStatus() {
        let state = BetaAccessFeature.State()
        XCTAssertEqual(state.status, .notActive)
        XCTAssertEqual(state.reason, .missingInput)
        XCTAssertFalse(state.isVerifying)
        XCTAssertFalse(state.isComplete)
    }

    /// active 상태의 제목과 메시지가 노출되고 완료로 오해되지 않는지 확인한다.
    ///
    /// - 검증 내용: `status == .active`일 때 표시 문구는 존재해야 한다.
    /// - 사전 조건: `State(status: .active)` 생성.
    /// - 기대 결과: `statusTitle == "Active"`, `statusMessage != nil`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — active 상태만으로 완료가 되지는 않는다.
    func testActiveStatusMessage() {
        let state = BetaAccessFeature.State(status: .active)
        XCTAssertEqual(state.status, .active)
        XCTAssertEqual(state.statusTitle, "Active")
        XCTAssertNotNil(state.statusMessage)
        // isComplete는 멤버와이즈 이니셜라이저가 아닌 updateStatus()를 통해서만 설정됨
        XCTAssertFalse(state.isComplete)
    }

    /// checkFailed 상태의 메시지가 실패 원인과 함께 유지되는지 확인한다.
    ///
    /// - 검증 내용: 실패 상태에서 제목과 메시지가 비어 있지 않아야 한다.
    /// - 사전 조건: `State(status: .checkFailed, reason: .networkError)`.
    /// - 기대 결과: `statusTitle == "Check failed"`, `statusMessage != nil`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 실패 상태는 재시도 전 안내를 제공한다.
    func testCheckFailedStatusMessage() {
        let state = BetaAccessFeature.State(status: .checkFailed, reason: .networkError)
        XCTAssertEqual(state.status, .checkFailed)
        XCTAssertEqual(state.statusTitle, "Check failed")
        XCTAssertNotNil(state.statusMessage)
        XCTAssertFalse(state.isComplete)
    }

    /// 미활성 상태에서 입력 누락 메시지가 생성되는지 확인한다.
    ///
    /// - 검증 내용: `.notActive`와 `.missingInput` 조합은 사용자 안내를 가져야 한다.
    /// - 사전 조건: `State(status: .notActive, reason: .missingInput)`.
    /// - 기대 결과: `statusMessage != nil`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 누락 입력 경고는 화면에 보여야 한다.
    func testNotActiveWithMissingInputMessage() {
        let state = BetaAccessFeature.State(status: .notActive, reason: .missingInput)
        XCTAssertNotNil(state.statusMessage)
        XCTAssertFalse(state.isComplete)
    }

    /// 검증 중 로딩 상태가 켜지고 응답 후 해제되는지 확인한다.
    ///
    /// - 검증 내용: `checkTapped` 직후 `isVerifying`가 true가 되고 응답 후 false가 되어야 한다.
    /// - 사전 조건: email/token이 채워져 있고 검증 클라이언트는 성공 응답.
    /// - 기대 결과: 응답 후 `status == .active`, `reason == .none`, `isComplete == true`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 요청/응답 동안 진행 상태를 보여준다.
    func testLoadingStateDuringVerification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        XCTAssertTrue(store.state.isVerifying)

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertFalse(store.state.isVerifying)
        await store.finish()
    }

    /// 화면 진입 시 입력이 있으면 자동 검증이 시작되는지 확인한다.
    ///
    /// - 검증 내용: `onAppear`가 검증 effect를 발생시켜야 한다.
    /// - 사전 조건: 유효한 email/token이 미리 입력됨.
    /// - 기대 결과: `isVerifying == true` 후 성공 응답으로 `status == .active`, `isComplete == true`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 재진입 시 기존 자격 증명을 검증한다.
    func testOnAppearTriggersVerificationWhenInputsPresent() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { email, token in
                XCTAssertEqual(email, "user@test.com")
                XCTAssertEqual(token, "valid-token")
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.onAppear) { state in
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

    /// 이메일이 비어 있으면 화면 진입 시에도 검증을 시작하지 않는지 확인한다.
    ///
    /// - 검증 내용: 입력이 완성되지 않은 상태에서는 `onAppear`가 effect를 만들지 않아야 한다.
    /// - 사전 조건: email만 비어 있고 token은 채워짐.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isVerifying == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 누락 입력은 자동 검증보다 우선한다.
    func testOnAppearDoesNotVerifyWhenEmailEmpty() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.status, .notActive)
        XCTAssertEqual(store.state.reason, .missingInput)
        XCTAssertFalse(store.state.isVerifying)

        await store.finish()
    }

    /// 검증 중에는 제출이 잠겨 있어야 하는지 확인한다.
    ///
    /// - 검증 내용: `isVerifying == true`이면 다시 제출할 수 없어야 한다.
    /// - 사전 조건: 검증 중 상태를 직접 구성.
    /// - 기대 결과: `canSubmit == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 중복 요청 방지.
    func testCanSubmitIsFalseWhenVerifying() {
        let state = BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
            isVerifying: true,
        )
        XCTAssertFalse(state.canSubmit)
    }

    /// 재시도 노출이 실패 상태에만 제한되는지 확인한다.
    ///
    /// - 검증 내용: 성공/미활성 상태에서는 `showsRetry`가 false여야 한다.
    /// - 사전 조건: 실패, 활성, 미활성 상태를 각각 생성.
    /// - 기대 결과: 실패 상태만 재시도 가능.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 복구는 실패 후에만 열린다.
    func testShowsRetryOnlyWhenCheckFailed() {
        let failed = BetaAccessFeature.State(status: .checkFailed, reason: .networkError)
        XCTAssertTrue(failed.showsRetry)

        let active = BetaAccessFeature.State(status: .active)
        XCTAssertFalse(active.showsRetry)

        let notActive = BetaAccessFeature.State(status: .notActive, reason: .missingInput)
        XCTAssertFalse(notActive.showsRetry)
    }

    /// 검증 중에는 제출이 잠기고 응답 후 다시 풀리는지 확인한다.
    ///
    /// - 검증 내용: `checkTapped` 직후 `canSubmit`이 false가 되어야 한다.
    /// - 사전 조건: email/token이 채워진 상태와 성공 응답.
    /// - 기대 결과: 검증 중에는 제출 불가, 응답 후 `status == .active`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 진행 중 중복 제출을 막는다.
    func testVerifyingStateDuringCheck() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        await store.finish()
    }

    /// invalid_token 오류가 미활성 사유로 보이는지 확인한다.
    ///
    /// - 검증 내용: `gatewayError(code: "invalid_token")`는 `.notActive`로 내려가야 한다.
    /// - 사전 조건: 유효한 입력이지만 게이트웨이가 invalid_token을 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .invalidToken`, `isComplete == false`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 무효 토큰은 활성 권한이 아니다.
    func testNotActiveStatusShowsReason() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
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

    /// 입력이 모두 채워지면 missingInput 사유가 해제되는지 확인한다.
    ///
    /// - 검증 내용: email/token이 모두 입력되면 `reason`이 `.none`이어야 한다.
    /// - 사전 조건: 초기에는 비어 있고 두 입력을 순차적으로 채움.
    /// - 기대 결과: `reason == .none`.
    /// - 관련 사양: ONB-002-show_access_unlock_status — 입력 충족 시 경고를 제거한다.
    func testInputChangeClearsMissingInputReasonWhenBothFilled() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("a@b.com")) { state in
            state.email = "a@b.com"
        }

        await store.send(.tokenChanged("tok")) { state in
            state.token = "tok"
            state.reason = .none
        }

        XCTAssertEqual(store.state.reason, .none)
        await store.finish()
    }

    // MARK: - ONB-002-apply_access_unlock_result

    // 추적 사양: ONB-002-apply_access_unlock_result
    // 검증 대상: 검증 응답(성공/실패)에 따른 상태 전환, 에러 매핑, 재시도 동작.
    // 계약 경계: 검증 결과 적용·에러 매핑은 범위 내.
    //   Core License 인증 토큰 발급/갱신은 범위 외(후속).

    /// 성공 응답이 상태 완료로 이어지는지 확인한다.
    ///
    /// - 검증 내용: 유효한 email/token으로 검증 성공 시 `.active`로 전환되어야 한다.
    /// - 사전 조건: 검증 클라이언트가 `ok: true`를 반환.
    /// - 기대 결과: `status == .active`, `reason == .none`, `isComplete == true`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 성공 결과 적용 계약.
    func testVerificationSuccess() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { email, token in
                XCTAssertEqual(email, "tester@example.com")
                XCTAssertEqual(token, "cbt-token")
                return BetaAccessVerifyResponse(ok: true)
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
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        await store.finish()
    }

    /// 응답 처리 후 active 상태와 완료 플래그가 함께 세워지는지 확인한다.
    ///
    /// - 검증 내용: 성공 응답은 `isVerifying`를 내리고 완료 상태를 세팅해야 한다.
    /// - 사전 조건: 성공 응답(`ok: true`).
    /// - 기대 결과: `status == .active`, `reason == .none`, `isComplete == true`, `isVerifying == false`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 최종 상태 반영.
    func testVerificationResponseOkSetsActiveAndComplete() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(store.state.status, .active)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.isVerifying)
        await store.finish()
    }

    /// 거짓 응답이 실패 상태로 처리되는지 확인한다.
    ///
    /// - 검증 내용: `ok: false`는 성공 완료가 아니라 실패 처리여야 한다.
    /// - 사전 조건: 검증 클라이언트가 `ok: false`를 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .internalError`, `isComplete == false`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 실패 응답은 완료가 아니다.
    func testVerificationResponseNotOkSetsCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: false)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .internalError
            state.isComplete = false
        }

        XCTAssertEqual(store.state.status, .checkFailed)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// 네트워크 오류가 실패 사유로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: 네트워크 예외는 재시도 가능한 실패로 내려가야 한다.
    /// - 사전 조건: 검증 클라이언트가 `networkError`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .networkError`, `isComplete == false`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 네트워크 실패는 복구 대상.
    func testVerificationFailureNetworkError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.networkError
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

    /// 디코딩 오류가 내부 오류로 수렴하는지 확인한다.
    ///
    /// - 검증 내용: 응답 파싱 실패는 내부 실패로 처리되어야 한다.
    /// - 사전 조건: 검증 클라이언트가 `decodingError`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .internalError`, `isComplete == false`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 파싱 실패는 정상 완료가 아님.
    func testVerificationFailureDecodingError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.decodingError
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .internalError
            state.isComplete = false
        }

        await store.finish()
    }

    /// 디바이스 식별자 부족이 전용 사유로 반영되는지 확인한다.
    ///
    /// - 검증 내용: 기기 식별이 불가능하면 별도 상태 사유가 보여야 한다.
    /// - 사전 조건: 검증 클라이언트가 `deviceIdUnavailable`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .deviceIdUnavailable`, `isComplete == false`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 기기 정보 의존 실패의 명시화.
    func testVerificationFailureDeviceIdUnavailable() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.deviceIdUnavailable
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .deviceIdUnavailable
            state.isComplete = false
        }

        await store.finish()
    }

    /// 잘못된 요청이 요청 오류로 분류되는지 확인한다.
    ///
    /// - 검증 내용: 형식이 잘못된 요청은 활성화가 아니라 실패 상태여야 한다.
    /// - 사전 조건: 검증 클라이언트가 `invalidRequest`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .invalidRequest`, `isComplete == false`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 요청 검증 실패 계약.
    func testVerificationFailureInvalidRequest() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.invalidRequest
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .invalidRequest
            state.isComplete = false
        }

        await store.finish()
    }

    /// active 상태 전환이 완료 플래그를 함께 세우는지 확인한다.
    ///
    /// - 검증 내용: 성공 응답 후 active와 complete가 같이 반영되어야 한다.
    /// - 사전 조건: 이메일·토큰이 채워진 상태에서 성공 응답.
    /// - 기대 결과: `status == .active`, `isComplete == true`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 성공 결과는 완료로 이어진다.
    func testActiveStatusSetsIsComplete() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
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

    /// 검증 결과 적용이 notActive에서 active로 전환되는지 확인한다.
    ///
    /// - 검증 내용: 이전 상태와 무관하게 성공 응답은 active로 바뀌어야 한다.
    /// - 사전 조건: `status == .notActive`, `reason == .missingInput`에서 성공 응답.
    /// - 기대 결과: `status == .active`, `isComplete == true`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 결과 적용은 최종 성공 상태를 반영한다.
    func testApplyVerificationResultTransitionsToActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
            status: .notActive,
            reason: .missingInput,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(store.state.status, .active)
        XCTAssertTrue(store.state.isComplete)

        await store.finish()
    }

    /// 기존 자격 증명이 검증 과정에서 보존되는지 확인한다.
    ///
    /// - 검증 내용: 검증 전후로 email/token 값이 바뀌면 안 된다.
    /// - 사전 조건: 이미 채워진 email/token으로 검증 실행.
    /// - 기대 결과: 입력값 보존, `status == .active`, `isComplete == true`.
    /// - 관련 사양: ONB-002-apply_access_unlock_result — 결과 적용은 입력을 손상시키지 않는다.
    func testApplyVerificationResultWithExistingCredentials() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        XCTAssertEqual(store.state.email, "tester@example.com")
        XCTAssertEqual(store.state.token, "cbt-token")

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(store.state.email, "tester@example.com")
        XCTAssertEqual(store.state.token, "cbt-token")

        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    // 추적 사양: ONB-002-start_access_unlock_recovery
    // 검증 대상: 게이트웨이 에러 코드 → BetaAccessFailureReason 매핑,
    //   재시도 후 복구, 반복 재시도, 타임아웃 처리.
    // 계약 경계: gateway 에러 매핑·재시도 동작은 범위 내.
    //   Core License auth entitlement는 범위 외(후속).

    /// 재시도 버튼이 검증을 다시 시작하는지 확인한다.
    ///
    /// - 검증 내용: 실패 상태에서 `retryTapped`는 새 검증 effect를 발생시켜야 한다.
    /// - 사전 조건: `.checkFailed`와 `.networkError` 상태.
    /// - 기대 결과: 재시도 후 `status == .active`, `reason == .none`, `isComplete == true`.
    /// - 관련 사양: ONB-002-start_access_unlock_recovery — 재시도는 실제 복구 경로여야 한다.
    func testRetryTappedTriggersReverification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
            status: .checkFailed,
            reason: .networkError,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
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

// swiftlint:enable file_length
