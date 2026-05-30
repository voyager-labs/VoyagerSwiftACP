import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

/*
 SET-007-manage_ai_connections coverage preservation

 | Existing file | Existing scenario | SET-007 section | Preservation |
 | --- | --- | --- | --- |
 | AiSettingsFeatureTests | provider catalog rows, method labels, default/last-used absence | SET-007-show_ai_provider_list | testProviderRowsExposeSupportedProvidersMethodsAndActions |
 | AiConnectionUnavailableTests | unavailable rows are inert and disabled | SET-007-show_ai_provider_list / connect_ai_provider | testUnavailableProviderIsVisibleDisabledAndInert |
 | AiConnectionOAuthTests | ChatGPT Codex browser login success, retry, duplicate guard | SET-007-connect_ai_provider | OAuth scenarios in owner suite |
 | AiSettingsFeatureTests | OpenAI/Anthropic API key submit success/failure | SET-007-connect_ai_provider | API key scenarios in owner suite |
 | AiConnectionDisconnectTests | confirmation, cancel, success, failure, duplicate guard | SET-007-disconnect_ai_provider | disconnect scenarios in owner suite |
 | AiConnectionRestoreTests / AiConnectionCatalogFailureTests | restore, failed bootstrap, retry | SET-007-restore_ai_provider_connection_status | restore scenarios in owner suite |

 The legacy flat tests remain in place for now. This owner suite provides the
 product-spec traceability layer before any duplicate cleanup is attempted.
 */

@MainActor
final class SET007ManageAIConnectionsTests: XCTestCase {
    // MARK: - SET-007-show_ai_provider_list

    /// SET-007-show_ai_provider_list: 지원 provider row는 연결 방식과 primary action을 노출하고 기본/최근 사용 UI를 만들지 않는다.
    /// Settings AI 탭의 provider 목록이 현재 빌드의 지원 provider와 계약상 허용된 연결 방식만 표시하는지 검증한다.
    /// - 검증 내용: ChatGPT Codex/OAuth, OpenAI/API Key, Anthropic/API Key, fresh action, connected/retry action
    /// - 사전 조건: Settings AI provider catalog를 기본 상태로 구성한다.
    /// - 기대 결과: 3개 provider row가 정해진 순서와 method label/action으로 노출되고 default/last-used 상태는 없다.
    func testProviderRowsExposeSupportedProvidersMethodsAndActions() {
        let rows = AiSettingsState.catalogRows()

        XCTAssertEqual(rows.map(\.provider), [.chatgptCodex, .openai, .anthropic])
        XCTAssertEqual(rows.map(\.displayName), ["ChatGPT Codex", "OpenAI", "Anthropic"])
        XCTAssertEqual(rows.map(\.authMethodLabel), ["OAuth", "API Key", "API Key"])
        XCTAssertTrue(rows.allSatisfy { $0.connectionState == .notVerified })
        XCTAssertTrue(rows.allSatisfy { $0.primaryAction == .connect })
        XCTAssertEqual(AiConnectionRowState(provider: .openai, connectionState: .connected).primaryAction, .disconnect)
        XCTAssertEqual(
            AiConnectionRowState(provider: .anthropic, connectionState: .connectionFailed).primaryAction,
            .retry,
        )
    }

    /// SET-007-show_ai_provider_list: unavailable provider는 목록에 남지만 action은 disabled다.
    /// 지원되지 않는 provider row가 사라지지 않고 사용자에게 비활성 상태로 표현되는지 검증한다.
    /// - 검증 내용: unavailable 상태의 primary action과 연결 시도 무시
    /// - 사전 조건: OpenAI row를 unavailable 상태로 구성한다.
    /// - 기대 결과: row 상태가 unavailable/idle로 유지되고 primary action은 disabled다.
    func testUnavailableProviderIsVisibleDisabledAndInert() async {
        let store = rowStore(
            state: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        )

        await store.send(.connectButtonTapped)
        await store.send(.retryButtonTapped)
        await store.send(.submitAPIKey("sk-test"))
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.primaryAction, .disabled)
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: ChatGPT Codex는 OAuth browser login으로만 연결된다.
    /// OAuth provider connect action이 API key 경로 없이 browser login flow와 verification/persistence를 거치는지 검증한다.
    /// - 검증 내용: connect button, browser login in-progress, OAuth verification, connected completion
    /// - 사전 조건: ChatGPT Codex row가 not_verified 상태이고 OAuth fixture가 성공한다.
    /// - 기대 결과: row가 connect_in_progress를 거쳐 connected가 되고 flowState는 idle로 복귀한다.
    func testChatGPTCodexOAuthConnectSuccessMovesRowToConnected() async {
        let credential = OAuthCredentialFile.testFixture()
        let store = rowStore(
            state: AiConnectionRowState(provider: .chatgptCodex),
        ) {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(.completed(credential))
                    continuation.finish()
                }
            }
            $0.aiProviderVerificationClient.verify = { provider, credential in
                XCTAssertEqual(provider, .chatgptCodex)
                XCTAssertNotNil(credential)
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                .connectSuccess(provider: provider, state: connectionState)
            }
        }

        await store.send(.connectButtonTapped)
        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }
        await store.receive(\._connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }
        await store.receive(\.browserLoginCompleted)
        await store.finish()
    }

    /// SET-007-connect_ai_provider: OpenAI API key 연결 성공은 verification 이후 connected로 전환된다.
    /// API key provider가 OAuth flow를 시작하지 않고 key verification과 connect client만 사용하는지 검증한다.
    /// - 검증 내용: trimmed key 저장, verification response, API key connect response, connected row state
    /// - 사전 조건: OpenAI row가 not_verified 상태이고 API key verification이 valid를 반환한다.
    /// - 기대 결과: row가 connected가 되고 입력 key는 성공 후 비워진다.
    func testOpenAIAPIKeyConnectSuccessMovesRowToConnected() async {
        let store = apiKeyRowStore(provider: .openai, verificationResult: .valid)

        await store.send(.submitAPIKey("  sk-valid  ")) { state in
            state.enteredKey = "sk-valid"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }
        await store.receive(\._verificationResponse) { state in
            state.isVerifying = false
        }
        await store.receive(\._connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
            state.enteredKey = ""
        }
        await store.finish()
    }

    /// SET-007-connect_ai_provider: Anthropic API key 검증 실패는 recoverable connection_failed 상태가 된다.
    /// 잘못된 API key가 connected로 저장되지 않고 retry 가능한 실패 상태로 표시되는지 검증한다.
    /// - 검증 내용: invalid API key verification, connection_failed state, invalidAPIKey reason, retry action
    /// - 사전 조건: Anthropic row가 not_verified 상태이고 verification이 invalidAPIKey를 반환한다.
    /// - 기대 결과: row는 connection_failed/invalidAPIKey가 되고 primary action은 retry다.
    func testAnthropicAPIKeyInvalidCredentialShowsConnectionFailed() async {
        let store = apiKeyRowStore(provider: .anthropic, verificationResult: .invalid(.invalidAPIKey))

        await store.send(.submitAPIKey("bad-key")) { state in
            state.enteredKey = "bad-key"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }
        await store.receive(\._verificationResponse) { state in
            state.isVerifying = false
            state.connectionState = .connectionFailed
            state.statusReason = .invalidAPIKey
            state.flowState = .idle
        }
        await store.finish()

        XCTAssertEqual(store.state.primaryAction, .retry)
    }

    /// SET-007-connect_ai_provider: connect_in_progress 중복 connect action은 새 flow를 만들지 않는다.
    /// 이미 연결 flow가 진행 중일 때 re-entry가 provider client를 중복 호출하지 않는지 검증한다.
    /// - 검증 내용: duplicate connect button ignored, flowState unchanged
    /// - 사전 조건: ChatGPT Codex row가 connect_in_progress/browserLoginInProgress 상태다.
    /// - 기대 결과: state가 변경되지 않고 추가 effect가 없다.
    func testDuplicateConnectWhileInProgressIsIgnored() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .chatgptCodex,
                connectionState: .connectInProgress,
                flowState: .browserLoginInProgress,
            ),
        )

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connectInProgress)
        XCTAssertEqual(store.state.flowState, .browserLoginInProgress)
    }

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: connected provider의 disconnect는 확인 dialog를 먼저 연다.
    /// 사용자가 실수로 credential을 제거하지 않도록 confirmation gate가 선행되는지 검증한다.
    /// - 검증 내용: disconnect button, confirmation flag, connected state preservation
    /// - 사전 조건: OpenAI row가 connected 상태다.
    /// - 기대 결과: confirmation이 표시되고 row는 아직 connected 상태다.
    func testDisconnectButtonShowsConfirmationBeforeMutation() async {
        let store = rowStore(state: AiConnectionRowState(provider: .openai, connectionState: .connected))

        await store.send(.disconnectButtonTapped) { state in
            state.isShowingDisconnectConfirmation = true
        }
        await store.finish()
    }

    /// SET-007-disconnect_ai_provider: confirmation cancel은 connected 상태를 유지한다.
    /// disconnect 확인 dialog에서 취소한 경우 저장 상태와 row state가 바뀌지 않는지 검증한다.
    /// - 검증 내용: disconnect cancel, confirmation dismissal, connected preservation
    /// - 사전 조건: OpenAI row가 connected이고 confirmation이 표시되어 있다.
    /// - 기대 결과: confirmation만 닫히고 connected 상태가 유지된다.
    func testDisconnectCancelKeepsProviderConnected() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true,
            ),
        )

        await store.send(.disconnectCancel) { state in
            state.isShowingDisconnectConfirmation = false
        }
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
    }

    /// SET-007-disconnect_ai_provider: confirmation success는 credential을 제거하고 not_verified로 돌아간다.
    /// provider disconnect 성공 응답이 row와 입력 key를 연결 전 상태로 되돌리는지 검증한다.
    /// - 검증 내용: disconnecting transition, disconnect response, enteredKey clearing, connect action
    /// - 사전 조건: OpenAI row가 connected이고 confirmation이 표시되어 있다.
    /// - 기대 결과: row가 not_verified/idle로 바뀌고 primary action은 connect다.
    func testDisconnectConfirmationSuccessRemovesCredentialAndReturnsNotVerified() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                enteredKey: "sk-preserved",
                isShowingDisconnectConfirmation: true,
            ),
        ) {
            $0.aiProviderConnectionClient.disconnect = { provider in .disconnectSuccess(provider: provider) }
        }

        await store.send(.disconnectConfirm) { state in
            state.isShowingDisconnectConfirmation = false
            state.flowState = .disconnecting
            state.connectionState = .disconnecting
        }
        await store.receive(\._disconnectResponse) { state in
            state.flowState = .idle
            state.connectionState = .notVerified
            state.statusReason = .none
            state.enteredKey = ""
        }
        await store.finish()

        XCTAssertEqual(store.state.primaryAction, .connect)
    }

    /// SET-007-disconnect_ai_provider: disconnect 실패는 connected 상태를 보존한다.
    /// credential 제거 실패가 UI를 잘못 not_verified로 낮추지 않는지 검증한다.
    /// - 검증 내용: disconnecting transition, failure response, connected preservation
    /// - 사전 조건: OpenAI row가 connected이고 disconnect client가 connected 결과를 반환한다.
    /// - 기대 결과: row는 connected/idle로 복구된다.
    func testDisconnectFailurePreservesConnectedState() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true,
            ),
        ) {
            $0.aiProviderConnectionClient.disconnect = { provider in
                AiProviderConnectionResult(provider: provider, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.disconnectConfirm) { state in
            state.isShowingDisconnectConfirmation = false
            state.flowState = .disconnecting
            state.connectionState = .disconnecting
        }
        await store.receive(\._disconnectResponse) { state in
            state.flowState = .idle
            state.connectionState = .connected
            state.statusReason = .none
        }
        await store.finish()
    }

    // MARK: - SET-007-restore_ai_provider_connection_status

    /// SET-007-restore_ai_provider_connection_status: 저장 credential은 checking_status를 거쳐 connected로 복원된다.
    /// Settings AI 탭 진입 시 저장된 credential을 즉시 connected로 단정하지 않고 verification 이후 확정하는지 검증한다.
    /// - 검증 내용: onAppear bootstrap, checking_status initial result, verification completed result
    /// - 사전 조건: OpenAI credential이 저장되어 있고 verification은 valid를 반환한다.
    /// - 기대 결과: OpenAI row가 checking_status를 거쳐 connected가 된다.
    func testStoredCredentialRestoresFromCheckingStatusToConnected() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .connected)) {
            $0.aiProviderVerificationClient.verify = { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertNotNil(credential)
                return .valid
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: credential이 없으면 not_verified와 missingCredential reason으로 복원된다.
    /// 저장 row는 있으나 credential payload가 누락된 경우 연결된 것으로 오인하지 않는지 검증한다.
    /// - 검증 내용: missing credential bootstrap result, no verification request, connect action
    /// - 사전 조건: OpenAI provider record는 있지만 credential은 nil이다.
    /// - 기대 결과: row는 not_verified/missingCredential이고 primary action은 connect다.
    func testMissingCredentialRestoresToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        let store = settingsStore(file: file)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .missingCredential
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: failed snapshot은 checking_status 이후 connection_failed로 복원된다.
    /// 만료된 저장 credential이 recoverable retry 상태로 표현되는지 검증한다.
    /// - 검증 내용: connectionFailed snapshot, verification invalid response, retry action
    /// - 사전 조건: OpenAI snapshot이 connectionFailed/expired이고 verification도 expired를 반환한다.
    /// - 기대 결과: row는 connection_failed/expired이고 primary action은 retry다.
    func testFailedSnapshotRestoresToConnectionFailedWithRetry() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .connectionFailed, errorCode: .expired)) {
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.expired) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .retry)
    }

    /// SET-007-restore_ai_provider_connection_status: catalog load failure는 rows를 보존하고 retry로 복구된다.
    /// provider catalog/load 오류가 빈 목록으로 보이지 않고 사용자가 재시도할 수 있는 상태로 남는지 검증한다.
    /// - 검증 내용: bootstrap failed phase, rows preserved, retry bootstrap success
    /// - 사전 조건: 첫 load는 실패하고 두 번째 load는 OpenAI credential file을 반환한다.
    /// - 기대 결과: failed phase 후 retry가 loaded/connected 상태로 회복된다.
    func testCatalogLoadFailureShowsRetryAndCanRecover() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                let count = await loadCounter.increment()
                if count == 1 { throw NSError(domain: "SET007", code: -1) }
                return AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.retryBootstrapTapped) { state in
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.bootstrapPhase = .loaded
        }
        await store.finish()
    }
}

@MainActor
private func rowStore(
    state: AiConnectionRowState,
    dependencies: (inout DependencyValues) -> Void = { _ in },
) -> TestStore<AiConnectionRowState, AiConnectionRowAction> {
    TestStore(initialState: state) {
        AiConnectionRowReducer()
    } withDependencies: {
        dependencies(&$0)
    }
}

@MainActor
private func apiKeyRowStore(
    provider: AiProvider,
    verificationResult: AiProviderVerificationResult,
) -> TestStore<AiConnectionRowState, AiConnectionRowAction> {
    rowStore(state: AiConnectionRowState(provider: provider)) {
        $0.aiProviderVerificationClient.verify = { _, _ in verificationResult }
        $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
            .connectSuccess(provider: provider, state: connectionState)
        }
    }
}

@MainActor
private func settingsStore(
    file: AIConnectionsFile,
    dependencies: (inout DependencyValues) -> Void = { _ in },
) -> TestStore<AiSettingsState, AiSettingsAction> {
    TestStore(initialState: AiSettingsState()) {
        AiSettingsFeature()
    } withDependencies: {
        $0.aiConnectionsFileClient.load = { file }
        dependencies(&$0)
    }
}

private actor LoadCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
