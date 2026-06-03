import ComposableArchitecture
@testable import VoyagerFeaturesBetaAccess
import XCTest

@MainActor
final class ONB002PresentAccessUnlockStepTests: XCTestCase {
    // MARK: - ONB-002-show_access_unlock_status

    // BetaAccess 리듀서의 상태 표시·검증 요청·입력 가드 동작을 검증합니다.
    // 초기 상태, 로딩, onAppear 자동 검증, canSubmit/placelogic 등 상태 표시 관련 테스트를 포함합니다.

    /// ONB-002:show_access_unlock_status — 입력이 비어 있으면 검증을 시작하지 않는지 확인한다.
    ///
    /// - 검증 내용: `checkTapped`가 와도 입력 누락이면 즉시 가드되어야 한다.
    /// - 사전 조건: email/token이 모두 비어 있는 초기 상태.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isVerifying == false`.
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

    /// ONB-002:show_access_unlock_status — 초기 상태가 미활성 기본값인지 확인한다.
    ///
    /// - 검증 내용: 기본 생성 상태가 첫 진입 화면 기준과 일치해야 한다.
    /// - 사전 조건: `BetaAccessFeature.State()` 사용.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isVerifying == false`, `isComplete == false`.
    func testInitialStateShowsNotActiveStatus() {
        let state = BetaAccessFeature.State()
        XCTAssertEqual(state.status, .notActive)
        XCTAssertEqual(state.reason, .missingInput)
        XCTAssertFalse(state.isVerifying)
        XCTAssertFalse(state.isComplete)
    }

    /// ONB-002:show_access_unlock_status — active 상태의 제목과 메시지가 노출되고 완료로 오해되지 않는지 확인한다.
    ///
    /// - 검증 내용: `status == .active`일 때 표시 문구는 존재해야 한다.
    /// - 사전 조건: `State(status: .active)` 생성.
    /// - 기대 결과: `statusTitle == "Active"`, `statusMessage != nil`, `isComplete == false`.
    func testActiveStatusMessage() {
        let state = BetaAccessFeature.State(status: .active)
        XCTAssertEqual(state.status, .active)
        XCTAssertEqual(state.statusTitle, "Active")
        XCTAssertNotNil(state.statusMessage)
        // isComplete는 멤버와이즈 이니셜라이저가 아닌 updateStatus()를 통해서만 설정됨
        XCTAssertFalse(state.isComplete)
    }

    /// ONB-002:show_access_unlock_status — checkFailed 상태의 메시지가 실패 원인과 함께 유지되는지 확인한다.
    ///
    /// - 검증 내용: 실패 상태에서 제목과 메시지가 비어 있지 않아야 한다.
    /// - 사전 조건: `State(status: .checkFailed, reason: .networkError)`.
    /// - 기대 결과: `statusTitle == "Check failed"`, `statusMessage != nil`, `isComplete == false`.
    func testCheckFailedStatusMessage() {
        let state = BetaAccessFeature.State(status: .checkFailed, reason: .networkError)
        XCTAssertEqual(state.status, .checkFailed)
        XCTAssertEqual(state.statusTitle, "Check failed")
        XCTAssertNotNil(state.statusMessage)
        XCTAssertFalse(state.isComplete)
    }

    /// ONB-002:show_access_unlock_status — 미활성 상태에서 입력 누락 메시지가 생성되는지 확인한다.
    ///
    /// - 검증 내용: `.notActive`와 `.missingInput` 조합은 사용자 안내를 가져야 한다.
    /// - 사전 조건: `State(status: .notActive, reason: .missingInput)`.
    /// - 기대 결과: `statusMessage != nil`, `isComplete == false`.
    func testNotActiveWithMissingInputMessage() {
        let state = BetaAccessFeature.State(status: .notActive, reason: .missingInput)
        XCTAssertNotNil(state.statusMessage)
        XCTAssertFalse(state.isComplete)
    }

    /// ONB-002:show_access_unlock_status — 검증 중 로딩 상태가 켜지고 응답 후 해제되는지 확인한다.
    ///
    /// - 검증 내용: `checkTapped` 직후 `isVerifying`가 true가 되고 응답 후 false가 되어야 한다.
    /// - 사전 조건: email/token이 채워져 있고 검증 클라이언트는 성공 응답.
    /// - 기대 결과: 응답 후 `status == .active`, `reason == .none`, `isComplete == true`.
    func testLoadingStateDuringVerification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
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

    /// ONB-002:show_access_unlock_status — 화면 진입 시 입력이 있으면 자동 검증이 시작되는지 확인한다.
    ///
    /// - 검증 내용: `onAppear`가 검증 effect를 발생시켜야 한다.
    /// - 사전 조건: 유효한 email/token이 미리 입력됨.
    /// - 기대 결과: `isVerifying == true` 후 성공 응답으로 `status == .active`, `isComplete == true`.
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

    /// ONB-002:show_access_unlock_status — 이메일이 비어 있으면 화면 진입 시에도 검증을 시작하지 않는지 확인한다.
    ///
    /// - 검증 내용: 입력이 완성되지 않은 상태에서는 `onAppear`가 effect를 만들지 않아야 한다.
    /// - 사전 조건: email만 비어 있고 token은 채워짐.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isVerifying == false`.
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

    /// ONB-002:show_access_unlock_status — 검증 완료 상태에서 화면 재진입 시 재검증하지 않는지 확인한다.
    ///
    /// - 검증 내용: `onAppear`가 이미 `isComplete == true` && `status == .active`이면 verify를 호출하지 않아야 한다.
    /// - 사전 조건: email/token이 채워져 있고 `status == .active`, `isComplete == true`인 검증 완료 상태.
    /// - 기대 결과: `onAppear` 이후에도 `status == .active`, `reason == .none`, `isComplete == true`, `isVerifying == false`.
    func testOnAppearSkipsVerificationWhenAlreadyVerified() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                _ = counter.increment()
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.status, .active)
        XCTAssertEqual(store.state.reason, .none)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.isVerifying)
        XCTAssertEqual(counter.value, 0)

        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 완료 후 이메일을 변경하면 검증 상태가 무효화되는지 확인한다.
    ///
    /// - 검증 내용: `isComplete == true` 상태에서 email을 변경하면 `isComplete == false`가 되어야 한다.
    /// - 사전 조건: `status == .active`, `isComplete == true`인 검증 완료 상태.
    /// - 기대 결과: 이메일 변경 후 `isComplete == false`, `status == .notActive`, `reason == .none`.
    func testChangingInputAfterVerifiedInvalidatesState() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("new@test.com")) { state in
            state.email = "new@test.com"
            state.status = .notActive
            state.reason = .none
            state.isComplete = false
        }

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.status, .notActive)

        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 완료 후 토큰을 변경하면 검증 상태가 무효화되는지 확인한다.
    ///
    /// - 검증 내용: `isComplete == true` 상태에서 token을 변경하면 `isComplete == false`가 되어야 한다.
    /// - 사전 조건: `status == .active`, `isComplete == true`인 검증 완료 상태.
    /// - 기대 결과: 토큰 변경 후 `isComplete == false`, `status == .notActive`, `reason == .none`.
    func testChangingTokenAfterVerifiedInvalidatesState() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.tokenChanged("new-token")) { state in
            state.token = "new-token"
            state.status = .notActive
            state.reason = .none
            state.isComplete = false
        }

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.status, .notActive)

        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 완료 후 이메일을 비우면 missingInput 상태가 되는지 확인한다.
    ///
    /// - 검증 내용: 검증 완료 상태에서 email을 빈 문자열로 변경하면 `.missingInput`이어야 한다.
    /// - 사전 조건: `status == .active`, `isComplete == true`인 검증 완료 상태.
    /// - 기대 결과: `status == .notActive`, `reason == .missingInput`, `isComplete == false`.
    func testClearingEmailAfterVerifiedSetsMissingInput() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("")) { state in
            state.email = ""
            state.status = .notActive
            state.reason = .missingInput
            state.isComplete = false
        }

        XCTAssertEqual(store.state.reason, .missingInput)
        XCTAssertFalse(store.state.isComplete)

        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 완료 후 이메일 변경 후 재검증이 필요한지 확인한다.
    ///
    /// - 검증 내용: 입력 변경으로 무효화된 상태에서 재검증 시 성공하면 다시 `isComplete == true`가 되어야 한다.
    /// - 사전 조건: 검증 완료 → 이메일 변경 → 무효화 상태.
    /// - 기대 결과: `checkTapped` 후 성공 응답 시 `status == .active`, `isComplete == true`.
    func testReverificationAfterInputChangeSucceeds() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
        }

        await store.send(.emailChanged("new@test.com")) { state in
            state.email = "new@test.com"
            state.status = .notActive
            state.reason = .none
            state.isComplete = false
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

        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 완료 상태에서 같은 이메일로 다시 설정하면 검증 상태가 유지되는지 확인한다.
    ///
    /// - 검증 내용: 같은 값의 재발행(macos TextField Enter/commit)은 verified state를 보존해야 한다.
    /// - 사전 조건: `status == .active`, `isComplete == true`인 상태에서 같은 email 재설정.
    /// - 기대 결과: `isComplete == true`, `status == .active`, `reason == .none` 유지.
    func testSettingSameEmailAfterVerifiedPreservesState() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("user@test.com"))

        XCTAssertTrue(store.state.isComplete)
        XCTAssertEqual(store.state.status, .active)
        XCTAssertEqual(store.state.reason, .none)
        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 완료 상태에서 같은 토큰으로 다시 설정하면 검증 상태가 유지되는지 확인한다.
    ///
    /// - 검증 내용: macOS SwiftUI TextField Enter/commit이 같은 토큰을 재발행할 때 verified state가 보존되어야 한다.
    /// - 사전 조건: `status == .active`, `isComplete == true`인 상태에서 같은 token 재설정.
    /// - 기대 결과: `isComplete == true`, `status == .active`, `reason == .none` 유지.
    func testSettingSameTokenAfterVerifiedPreservesState() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.tokenChanged("valid-token"))

        XCTAssertTrue(store.state.isComplete)
        XCTAssertEqual(store.state.status, .active)
        XCTAssertEqual(store.state.reason, .none)
        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 미검증 상태에서 이메일/토큰 변경 시 invalidation이 발생하지 않는지 확인한다.
    ///
    /// - 검증 내용: `isComplete == false` 상태에서는 기존 handleInputChange 로직만 동작해야 한다.
    /// - 사전 조건: 초기 상태(email/token 비어 있음).
    /// - 기대 결과: `reason == .missingInput` 유지, `isComplete == false`.
    func testInputChangeOnNonVerifiedStateDoesNotTriggerInvalidation() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("a@b.com")) { state in
            state.email = "a@b.com"
        }

        XCTAssertEqual(store.state.status, .notActive)
        XCTAssertEqual(store.state.reason, .missingInput)
        XCTAssertFalse(store.state.isComplete)

        await store.finish()
    }

    /// ONB-002:show_access_unlock_status — 검증 중에는 제출이 잠겨 있어야 하는지 확인한다.
    ///
    /// - 검증 내용: `isVerifying == true`이면 다시 제출할 수 없어야 한다.
    /// - 사전 조건: 검증 중 상태를 직접 구성.
    /// - 기대 결과: `canSubmit == false`.
    func testCanSubmitIsFalseWhenVerifying() {
        let state = BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
            isVerifying: true,
        )
        XCTAssertFalse(state.canSubmit)
    }

    /// ONB-002:show_access_unlock_status — 재시도 노출이 실패 상태에만 제한되는지 확인한다.
    ///
    /// - 검증 내용: 성공/미활성 상태에서는 `showsRetry`가 false여야 한다.
    /// - 사전 조건: 실패, 활성, 미활성 상태를 각각 생성.
    /// - 기대 결과: 실패 상태만 재시도 가능.
    func testShowsRetryOnlyWhenCheckFailed() {
        let failed = BetaAccessFeature.State(status: .checkFailed, reason: .networkError)
        XCTAssertTrue(failed.showsRetry)

        let active = BetaAccessFeature.State(status: .active)
        XCTAssertFalse(active.showsRetry)

        let notActive = BetaAccessFeature.State(status: .notActive, reason: .missingInput)
        XCTAssertFalse(notActive.showsRetry)
    }

    /// ONB-002:show_access_unlock_status — 검증 중에는 제출이 잠기고 응답 후 다시 풀리는지 확인한다.
    ///
    /// - 검증 내용: `checkTapped` 직후 `canSubmit`이 false가 되어야 한다.
    /// - 사전 조건: email/token이 채워진 상태와 성공 응답.
    /// - 기대 결과: 검증 중에는 제출 불가, 응답 후 `status == .active`.
    func testVerifyingStateDuringCheck() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
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

    /// ONB-002:show_access_unlock_status — invalid_token 오류가 미활성 사유로 보이는지 확인한다.
    ///
    /// - 검증 내용: `gatewayError(code: "invalid_token")`는 `.notActive`로 내려가야 한다.
    /// - 사전 조건: 유효한 입력이지만 게이트웨이가 invalid_token을 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .invalidToken`, `isComplete == false`.
    func testNotActiveStatusShowsReason() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "invalid_token")
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

    /// ONB-002:show_access_unlock_status — 입력이 모두 채워지면 missingInput 사유가 해제되는지 확인한다.
    ///
    /// - 검증 내용: email/token이 모두 입력되면 `reason`이 `.none`이어야 한다.
    /// - 사전 조건: 초기에는 비어 있고 두 입력을 순차적으로 채움.
    /// - 기대 결과: `reason == .none`.
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

    // 검증 결과(성공/실패) 적용과 상태 전환을 검증합니다.
    // ok/not-ok 응답, 네트워크·디코딩·디바이스·요청 오류, 완료 플래그 설정, 기존 자격 증명 보존 등 결과 처리 테스트를 포함합니다.

    /// ONB-002:apply_access_unlock_result — 성공 응답이 상태 완료로 이어지는지 확인한다.
    ///
    /// - 검증 내용: 유효한 email/token으로 검증 성공 시 `.active`로 전환되어야 한다.
    /// - 사전 조건: 검증 클라이언트가 `ok: true`를 반환.
    /// - 기대 결과: `status == .active`, `reason == .none`, `isComplete == true`.
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

    /// ONB-002:apply_access_unlock_result — 응답 처리 후 active 상태와 완료 플래그가 함께 세워지는지 확인한다.
    ///
    /// - 검증 내용: 성공 응답은 `isVerifying`를 내리고 완료 상태를 세팅해야 한다.
    /// - 사전 조건: 성공 응답(`ok: true`).
    /// - 기대 결과: `status == .active`, `reason == .none`, `isComplete == true`, `isVerifying == false`.
    func testVerificationResponseOkSetsActiveAndComplete() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
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

    /// ONB-002:apply_access_unlock_result — 거짓 응답이 실패 상태로 처리되는지 확인한다.
    ///
    /// - 검증 내용: `ok: false`는 성공 완료가 아니라 실패 처리여야 한다.
    /// - 사전 조건: 검증 클라이언트가 `ok: false`를 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .internalError`, `isComplete == false`.
    func testVerificationResponseNotOkSetsCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.notOk
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

    /// ONB-002:apply_access_unlock_result — 네트워크 오류가 실패 사유로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: 네트워크 예외는 재시도 가능한 실패로 내려가야 한다.
    /// - 사전 조건: 검증 클라이언트가 `networkError`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .networkError`, `isComplete == false`.
    func testVerificationFailureNetworkError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.throwing(.networkError)
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

    /// ONB-002:apply_access_unlock_result — 디코딩 오류가 내부 오류로 수렴하는지 확인한다.
    ///
    /// - 검증 내용: 응답 파싱 실패는 내부 실패로 처리되어야 한다.
    /// - 사전 조건: 검증 클라이언트가 `decodingError`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .internalError`, `isComplete == false`.
    func testVerificationFailureDecodingError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.throwing(.decodingError)
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

    /// ONB-002:apply_access_unlock_result — 디바이스 식별자 부족이 전용 사유로 반영되는지 확인한다.
    ///
    /// - 검증 내용: 기기 식별이 불가능하면 별도 상태 사유가 보여야 한다.
    /// - 사전 조건: 검증 클라이언트가 `deviceIdUnavailable`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .deviceIdUnavailable`, `isComplete == false`.
    func testVerificationFailureDeviceIdUnavailable() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.throwing(.deviceIdUnavailable)
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

    /// ONB-002:apply_access_unlock_result — 잘못된 요청이 요청 오류로 분류되는지 확인한다.
    ///
    /// - 검증 내용: 형식이 잘못된 요청은 활성화가 아니라 실패 상태여야 한다.
    /// - 사전 조건: 검증 클라이언트가 `invalidRequest`를 던짐.
    /// - 기대 결과: `status == .checkFailed`, `reason == .invalidRequest`, `isComplete == false`.
    func testVerificationFailureInvalidRequest() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.throwing(.invalidRequest)
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

    /// ONB-002:apply_access_unlock_result — 검증 결과 적용이 notActive에서 active로 전환되는지 확인한다.
    ///
    /// - 검증 내용: 이전 상태와 무관하게 성공 응답은 active로 바뀌어야 한다.
    /// - 사전 조건: `status == .notActive`, `reason == .missingInput`에서 성공 응답.
    /// - 기대 결과: `status == .active`, `isComplete == true`.
    func testApplyVerificationResultTransitionsToActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
            status: .notActive,
            reason: .missingInput,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
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

    /// ONB-002:apply_access_unlock_result — 기존 자격 증명이 검증 과정에서 보존되는지 확인한다.
    ///
    /// - 검증 내용: 검증 전후로 email/token 값이 바뀌면 안 된다.
    /// - 사전 조건: 이미 채워진 email/token으로 검증 실행.
    /// - 기대 결과: 입력값 보존, `status == .active`, `isComplete == true`.
    func testApplyVerificationResultWithExistingCredentials() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
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

    // 재시도·복구 흐름과 게이트웨이 에러 코드 매핑을 검증합니다.
    // retryTapped 재검증, 게이트웨이 에러 코드별 상태/사유 매핑, 반복 재시도, 복구 후 재시도 유지 등 복구 경로 테스트를 포함합니다.

    /// ONB-002:start_access_unlock_recovery — 재시도 버튼이 검증을 다시 시작하는지 확인한다.
    ///
    /// - 검증 내용: 실패 상태에서 `retryTapped`는 새 검증 effect를 발생시켜야 한다.
    /// - 사전 조건: `.checkFailed`와 `.networkError` 상태.
    /// - 기대 결과: 재시도 후 `status == .active`, `reason == .none`, `isComplete == true`.
    func testRetryTappedTriggersReverification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
            status: .checkFailed,
            reason: .networkError,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.success
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

    /// ONB-002:start_access_unlock_recovery — 잘못된 게이트웨이 URL이 전용 실패 사유로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: `invalid_gateway_url`은 구성 오류로 `.invalidGatewayUrl`이어야 한다.
    /// - 사전 조건: email/token이 입력된 상태에서 gatewayError(code: "invalid_gateway_url") 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .invalidGatewayUrl`, `isComplete == false`.
    func testInvalidGatewayURLMapsToInvalidGatewayReason() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "invalid_gateway_url")
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

    /// ONB-002:start_access_unlock_recovery — 토큰 누락 게이트웨이 오류가 실패 상태로 내려가는지 확인한다.
    ///
    /// - 검증 내용: missing_token은 활성화가 아니라 검증 실패여야 한다.
    /// - 사전 조건: 토큰이 존재하더라도 게이트웨이가 missing_token을 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .missingToken`, `isComplete == false`.
    func testGatewayErrorMissingTokenMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "missing_token")
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

    /// ONB-002:start_access_unlock_recovery — invalid_token이 미활성 상태로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: 토큰이 무효하면 완료가 아니라 미활성 사유로 분류해야 한다.
    /// - 사전 조건: 게이트웨이가 `invalid_token` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .invalidToken`, `isComplete == false`.
    func testGatewayErrorInvalidTokenMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "invalid_token")
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

    /// ONB-002:start_access_unlock_recovery — invalid_request가 미활성 사유로 처리되는지 확인한다.
    ///
    /// - 검증 내용: 요청 형식이 잘못되면 활성화가 아니라 입력/요청 실패로 보여야 한다.
    /// - 사전 조건: 게이트웨이가 `invalid_request` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .invalidRequest`, `isComplete == false`.
    func testGatewayErrorInvalidRequestMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "invalid_request")
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

    /// ONB-002:start_access_unlock_recovery — 이메일 불일치가 미활성 사유로 보이는지 확인한다.
    ///
    /// - 검증 내용: 계정 이메일이 맞지 않으면 활성화하지 않아야 한다.
    /// - 사전 조건: 게이트웨이가 `email_mismatch` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .emailMismatch`, `isComplete == false`.
    func testGatewayErrorEmailMismatchMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "email_mismatch")
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

    /// ONB-002:start_access_unlock_recovery — 디바이스 불일치가 미활성 사유로 보이는지 확인한다.
    ///
    /// - 검증 내용: 다른 기기에서의 토큰은 활성화가 아니라 거부로 처리되어야 한다.
    /// - 사전 조건: 게이트웨이가 `device_mismatch` 반환.
    /// - 기대 결과: `status == .notActive`, `reason == .deviceMismatch`, `isComplete == false`.
    func testGatewayErrorDeviceMismatchMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "device_mismatch")
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

    /// ONB-002:start_access_unlock_recovery — auth_backend_error가 실패 상태로 매핑되는지 확인한다.
    ///
    /// - 검증 내용: 백엔드 인증 오류는 복구 가능한 실패로 보여야 한다.
    /// - 사전 조건: 게이트웨이가 `auth_backend_error` 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .authBackendError`, `isComplete == false`.
    func testGatewayErrorAuthBackendErrorMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "auth_backend_error")
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

    /// ONB-002:start_access_unlock_recovery — 알 수 없는 게이트웨이 코드를 네트워크 오류로 폴백하는지 확인한다.
    ///
    /// - 검증 내용: 매핑되지 않은 코드는 안전하게 일반 네트워크 실패로 처리해야 한다.
    /// - 사전 조건: 게이트웨이가 임의의 unknown code 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .networkError`, `isComplete == false`.
    func testGatewayErrorUnknownCodeMapsToNetworkError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "some_unknown_code")
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

    /// ONB-002:start_access_unlock_recovery — 게이트웨이 실패 뒤 재시도가 성공으로 복구되는지 확인한다.
    ///
    /// - 검증 내용: 첫 실패 후 retry가 실제로 두 번째 검증을 호출해야 한다.
    /// - 사전 조건: 첫 호출은 auth_backend_error, 두 번째 호출은 성공.
    /// - 기대 결과: 첫 실패는 `.checkFailed`, 재시도 후 `.active` / `isComplete == true`, 시도 횟수는 2회.
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

    /// ONB-002:start_access_unlock_recovery — 네트워크 실패 뒤 재시도가 복구되는지 확인한다.
    ///
    /// - 검증 내용: 첫 네트워크 실패 후 retry가 다시 검증을 수행해야 한다.
    /// - 사전 조건: 첫 호출은 `networkError`, 두 번째 호출은 성공.
    /// - 기대 결과: 첫 실패는 `.checkFailed`, 재시도 후 `.active` / `isComplete == true`.
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

    /// ONB-002:start_access_unlock_recovery — 여러 번 실패한 뒤에도 재시도가 계속 복구 가능한지 확인한다.
    ///
    /// - 검증 내용: 실패가 반복돼도 마지막 성공 응답까지 retry가 유지되어야 한다.
    /// - 사전 조건: 첫 두 호출은 네트워크 실패, 세 번째 호출은 성공.
    /// - 기대 결과: 최종적으로 `.active`, `isComplete == true`, 시도 횟수는 3회.
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

    /// ONB-002:start_access_unlock_recovery — timeout 코드가 네트워크 실패로 수렴하는지 확인한다.
    ///
    /// - 검증 내용: 타임아웃은 재시도 가능한 일반 실패로 처리되어야 한다.
    /// - 사전 조건: email/token이 입력되고 gatewayError(code: "timeout") 반환.
    /// - 기대 결과: `status == .checkFailed`, `reason == .networkError`, `isComplete == false`.
    func testGatewayTimeoutMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClientFixture.gatewayError(code: "timeout")
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

    /// ONB-002:start_access_unlock_recovery — 실패 후 복구 흐름이 다시 시도 가능하게 유지되는지 확인한다.
    ///
    /// - 검증 내용: 타임아웃 실패 뒤 retry가 다시 성공 응답으로 이어져야 한다.
    /// - 사전 조건: 첫 호출은 timeout, 두 번째 호출은 성공.
    /// - 기대 결과: 첫 실패는 `.checkFailed`, 재시도 후 `.active` / `isComplete == true`.
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

    // MARK: - Restored verified state (snapshot restore, no credentials)

    /// Snapshot restore sets `isComplete == true`, `status == .active` but leaves
    /// email/token empty. `isRestoredVerifiedAccess` must be `true` in this case.
    func testIsRestoredVerifiedAccessTrueWhenVerifiedButCredentialsEmpty() {
        let state = BetaAccessFeature.State(
            email: "",
            token: "",
            status: .active,
            reason: .none,
            isComplete: true,
        )
        XCTAssertTrue(state.isRestoredVerifiedAccess)
    }

    /// In-session verified state (email/token present) must NOT be flagged as restored.
    func testIsRestoredVerifiedAccessFalseWhenCredentialsPresent() {
        let state = BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
        )
        XCTAssertFalse(state.isRestoredVerifiedAccess)
    }

    /// Unverified state with empty fields must NOT be flagged as restored.
    func testIsRestoredVerifiedAccessFalseWhenNotVerified() {
        let state = BetaAccessFeature.State()
        XCTAssertFalse(state.isRestoredVerifiedAccess)
    }

    /// Snapshot-restored state with `onAppear` must not trigger re-verification.
    func testOnAppearSkipsVerificationWhenRestoredVerified() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "",
            token: "",
            status: .active,
            reason: .none,
            isComplete: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                _ = counter.increment()
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.onAppear)

        XCTAssertTrue(store.state.isComplete)
        XCTAssertEqual(store.state.status, .active)
        XCTAssertFalse(store.state.isVerifying)
        XCTAssertTrue(store.state.isRestoredVerifiedAccess)
        XCTAssertEqual(counter.value, 0)

        await store.finish()
    }

    // MARK: - Re-verification on snapshot restore

    /// `needsReverification == true`인 상태에서 `onAppear`가 호출되면
    /// gateway re-verification을 수행하고 성공 시 `active` 상태를 유지한다.
    func testOnAppearReverifiesWhenNeedsReverification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
            status: .active,
            reason: .none,
            isComplete: true,
            needsReverification: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.onAppear) { state in
            state.needsReverification = false
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

    /// `needsReverification == true`인 상태에서 re-verification이 실패하면
    /// `notActive`로 전환된다.
    func testOnAppearReverifiesFailsWhenTokenInvalid() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "expired-token",
            status: .active,
            reason: .none,
            isComplete: true,
            needsReverification: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: false)
            })
        }

        await store.send(.onAppear) { state in
            state.needsReverification = false
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

    /// `needsReverification == true`이지만 email/token이 비어 있으면
    /// gateway 호출 없이 즉시 `missingInput` 상태가 된다.
    func testOnAppearReverifiesWithEmptyCredentialsReturnsMissingInput() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "",
            token: "",
            status: .active,
            reason: .none,
            isComplete: true,
            needsReverification: true,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                _ = counter.increment()
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.onAppear) { state in
            state.needsReverification = false
            state.isVerifying = false
            state.status = .notActive
            state.reason = .missingInput
            state.isComplete = false
        }

        XCTAssertEqual(counter.value, 0)

        await store.finish()
    }
}
