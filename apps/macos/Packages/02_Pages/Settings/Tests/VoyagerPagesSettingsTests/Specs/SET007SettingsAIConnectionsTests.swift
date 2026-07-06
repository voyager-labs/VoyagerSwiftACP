import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class SET007SettingsAIConnectionsTests: XCTestCase {
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

    // MARK: - SET-007-connect_ai_provider

    // MARK: - SET-007-connect_ai_provider

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: confirmation success는 credential 제거 file update를 전달하고 not_verified로 돌아간다.
    /// Settings 소유 범위에서 연결 해제 결과가 row state와 저장 파일의 credential 제거 사실을 함께 갱신하는지 검증한다.
    /// - 검증 내용: disconnecting transition, disconnect response, credential nil updatedFile delegate, connect action
    /// - 사전 조건: OpenAI row가 connected이고 confirmation이 표시되어 있다.
    /// - 기대 결과: row는 not_verified가 되고 delegate payload의 OpenAI credential은 nil이다.
    func testDisconnectConfirmationSuccessRemovesCredentialAndEmitsFileUpdate() async {
        let updatedFile = openAIDisconnectedFile()
        let result = AiProviderConnectionResult(
            provider: .openai,
            state: .notVerified,
            reason: .none,
            updatedFile: updatedFile,
        )
        let store = TestStore(initialState: AiSettingsState(rows: [
            AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                enteredKey: "sk-preserved",
                isShowingDisconnectConfirmation: true,
            ),
        ])) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { _ in result }
        }

        await store.send(.row(.element(id: .openai, action: .disconnectConfirm))) { state in
            state.rows[id: .openai]?.isShowingDisconnectConfirmation = false
            state.rows[id: .openai]?.flowState = .disconnecting
            state.rows[id: .openai]?.connectionState = .disconnecting
        }
        await store.receive(.row(.element(id: .openai, action: .disconnectResponse(result)))) { state in
            state.rows[id: .openai]?.flowState = .idle
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.enteredKey = ""
        }
        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
        await store.finish()

        XCTAssertNil(updatedFile.providers[AiProvider.openai.rawValue]?.credential)
        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
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

    /// SET-007-restore_ai_provider_connection_status: provider record가 없으면 모든 row는 not_verified로 복원된다.
    /// 저장 파일이 비어 있는 fresh 상태를 연결 실패나 missing credential로 오인하지 않는지 검증한다.
    /// - 검증 내용: empty connections file bootstrap, default rows, connect primary action
    /// - 사전 조건: AI connections file에 provider record가 없다.
    /// - 기대 결과: 모든 row가 not_verified/none 상태이고 primary action은 connect다.
    func testNoProviderRecordRestoresAllRowsToNotVerified() async {
        let store = settingsStore(file: .empty())

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }
        await store.finish()

        for row in store.state.rows {
            XCTAssertEqual(row.connectionState, .notVerified)
            XCTAssertEqual(row.statusReason, .none)
            XCTAssertEqual(row.primaryAction, .connect)
        }
    }

    /// SET-007-restore_ai_provider_connection_status: stale connect_in_progress snapshot은 credential이 있어도 not_verified로
    /// 낮춘다.
    /// 이전 세션에서 중단된 연결 시도를 재시작하지 않고 사용자가 명시적으로 다시 연결하도록 만드는지 검증한다.
    /// - 검증 내용: persisted connect_in_progress snapshot, credential present, no missingCredential reason
    /// - 사전 조건: ChatGPT Codex OAuth credential이 있지만 snapshot은 connect_in_progress다.
    /// - 기대 결과: row는 not_verified/none 상태이고 primary action은 connect다.
    func testConnectInProgressSnapshotWithCredentialRestoresToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
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
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: disconnecting snapshot은 disconnected로 복원된다.
    /// 이전 세션에서 연결 해제 중 종료된 provider가 계속 disconnecting으로 고정되지 않는지 검증한다.
    /// - 검증 내용: persisted disconnecting snapshot, loaded restore state, connect primary action
    /// - 사전 조건: Anthropic provider snapshot이 disconnecting이다.
    /// - 기대 결과: row는 disconnected/none 상태이고 primary action은 connect다.
    func testDisconnectingSnapshotRestoresToDisconnected() async {
        let store = settingsStore(file: .singleProvider(.anthropic, state: .disconnecting))

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .disconnected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .anthropic]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: disconnected snapshot은 disconnected 상태와 connect action을 유지한다.
    /// 명시적으로 연결 해제된 provider가 fresh not_verified와 구분되어 복원되는지 검증한다.
    /// - 검증 내용: persisted disconnected snapshot, status reason, primary action
    /// - 사전 조건: OpenAI provider snapshot이 disconnected다.
    /// - 기대 결과: row는 disconnected/none 상태이고 primary action은 connect다.
    func testDisconnectedSnapshotRestoresToDisconnected() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .disconnected))

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .disconnected
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: 여러 provider snapshot은 독립적으로 복원된다.
    /// connected/failed/no-record provider가 한 bootstrap에서 서로의 상태를 오염시키지 않는지 검증한다.
    /// - 검증 내용: mixed provider records, verification fan-out, connected/retry/connect actions
    /// - 사전 조건: ChatGPT Codex는 connected, OpenAI는 expired failure, Anthropic은 record가 없다.
    /// - 기대 결과: Codex는 connected, OpenAI는 connection_failed/expired, Anthropic은 not_verified다.
    func testMixedProviderSnapshotsRestoreIndependently() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-expired")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .expired,
                    ),
                ),
            ],
        )
        let store = settingsStore(file: file) {
            $0.aiProviderVerificationClient.verify = { provider, _ in
                switch provider {
                case .chatgptCodex: .valid
                case .openai: .invalid(.expired)
                case .anthropic: .valid
                }
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.primaryAction, .disconnect)
        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .retry)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .notVerified)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.primaryAction, .connect)
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

    /// SET-007-restore_ai_provider_connection_status: catalog load 실패 뒤 onAppear 재진입은 자동 retry를 실행하지 않는다.
    /// 실패 상태에서 사용자의 명시적 retry 없이 catalog load를 반복하지 않는지 검증한다.
    /// - 검증 내용: initial onAppear failure, second onAppear ignored, load call count
    /// - 사전 조건: AI connections file load가 항상 실패한다.
    /// - 기대 결과: load는 1회만 호출되고 bootstrapPhase는 failed로 유지된다.
    func testCatalogLoadFailureDoesNotRetryAutomaticallyOnAppear() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                _ = await loadCounter.increment()
                throw NSError(domain: "SET007", code: -1)
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.send(.onAppear)
        await store.finish()

        let loadCalls = await loadCounter.currentValue()
        XCTAssertEqual(loadCalls, 1)
        XCTAssertEqual(store.state.bootstrapPhase, .failed)
    }

    /// SET-007-restore_ai_provider_connection_status: unavailable snapshot은 verification 후 disabled 상태로 복원된다.
    /// 저장된 provider가 현재 build에서 지원되지 않을 때 연결 가능한 상태로 오인하지 않는지 검증한다.
    /// - 검증 내용: persisted unavailable snapshot, checking status, unsupported verification, disabled primary action
    /// - 사전 조건: OpenAI provider snapshot이 unavailable/providerUnsupportedInBuild 상태다.
    /// - 기대 결과: OpenAI row는 unavailable/providerUnsupportedInBuild이고 primary action은 disabled다.
    func testUnavailableSnapshotRestoresWithDisabledAction() async {
        let store = settingsStore(file: .singleProvider(
            .openai,
            state: .unavailable,
            errorCode: .providerUnsupportedInBuild,
        )) {
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
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
            state.rows[id: .openai]?.connectionState = .unavailable
            state.rows[id: .openai]?.statusReason = .providerUnsupportedInBuild
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .disabled)
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: connection response는 connectionsFileUpdated delegate를 방출한다.
    /// row reducer 결과가 Settings feature의 저장 파일 갱신 delegate로 이어지는지 검증한다.
    /// - 검증 내용: row connectionResponse, connected state, delegate payload
    /// - 사전 조건: ChatGPT Codex row가 connect_in_progress/browserLoginInProgress 상태다.
    /// - 기대 결과: row는 connected/idle이 되고 updated file delegate가 방출된다.
    func testConnectionResponseEmitsConnectionsFileUpdatedDelegate() async {
        let updatedFile = AIConnectionsFile.singleProvider(.chatgptCodex, state: .connected)
        let store = TestStore(
            initialState: AiSettingsState(rows: [
                AiConnectionRowState(
                    provider: .chatgptCodex,
                    connectionState: .connectInProgress,
                    flowState: .browserLoginInProgress,
                ),
            ]),
        ) {
            AiSettingsFeature()
        }

        await store.send(.row(.element(
            id: .chatgptCodex,
            action: .connectionResponse(AiProviderConnectionResult(
                provider: .chatgptCodex,
                state: .connected,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .chatgptCodex]?.flowState = .idle
        }

        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
    }

    /// SET-007-restore_ai_provider_connection_status: bootstrap verification 성공은 저장 파일과 delegate를 갱신한다.
    /// stale failed snapshot이 valid verification 후 connected snapshot으로 저장되는지 검증한다.
    /// - 검증 내용: bootstrap verification, AI connections file save, delegate emission
    /// - 사전 조건: OpenAI snapshot이 connection_failed/expired이고 verification은 valid다.
    /// - 기대 결과: connected snapshot 파일이 저장되고 동일 payload delegate가 방출된다.
    func testBootstrapVerificationSuccessPersistsAndEmitsConnectionsFileUpdatedDelegate() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connectionFailed,
            errorCode: .expired,
        )
        let expectedFile = AIConnectionsFile(
            updatedAtMs: staleFile.updatedAtMs,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: staleFile.providers[AiProvider.openai.rawValue]?.credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connected,
                        lastVerifiedAtMs: staleFile.updatedAtMs,
                        lastErrorCode: .none,
                    ),
                ),
            ],
        )
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { staleFile }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
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

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: disconnect response는 connectionsFileUpdated delegate를 방출한다.
    /// 연결 해제 결과가 Settings feature 경계에서 저장 파일 갱신 이벤트로 전달되는지 검증한다.
    /// - 검증 내용: row disconnectResponse, not_verified state, delegate payload
    /// - 사전 조건: OpenAI row가 disconnecting 상태다.
    /// - 기대 결과: row는 not_verified/idle이 되고 updated file delegate가 방출된다.
    func testDisconnectResponseEmitsConnectionsFileUpdatedDelegate() async {
        let updatedFile = AIConnectionsFile.singleProvider(.openai, state: .notVerified, credential: nil)
        let store = TestStore(
            initialState: AiSettingsState(rows: [
                AiConnectionRowState(
                    provider: .openai,
                    connectionState: .disconnecting,
                ),
            ]),
        ) {
            AiSettingsFeature()
        }

        await store.send(.row(.element(
            id: .openai,
            action: .disconnectResponse(AiProviderConnectionResult(
                provider: .openai,
                state: .notVerified,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.flowState = .idle
        }

        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
    }

    /// SET-007-restore_ai_provider_connection_status: unsupported provider verification은 unavailable snapshot을 저장한다.
    /// 현재 build에서 지원되지 않는 provider가 connected로 남지 않고 저장 파일과 delegate에 반영되는지 검증한다.
    /// - 검증 내용: unsupported verification, unavailable snapshot save, delegate emission
    /// - 사전 조건: ChatGPT Codex snapshot은 connected이고 verification은 unsupportedProvider다.
    /// - 기대 결과: unavailable/providerUnsupportedInBuild snapshot이 저장되고 delegate가 방출된다.
    func testBootstrapVerificationUnsupportedProviderPersistsAndEmitsConnectionsFileUpdatedDelegate() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .chatgptCodex,
            state: .connected,
            errorCode: .none,
        )
        let expectedFile = AIConnectionsFile(
            updatedAtMs: staleFile.updatedAtMs,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: staleFile.providers[AiProvider.chatgptCodex.rawValue]?.credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .unavailable,
                        lastVerifiedAtMs: nil,
                        lastErrorCode: .providerUnsupportedInBuild,
                    ),
                ),
            ],
        )
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { staleFile }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .unavailable
            state.rows[id: .chatgptCodex]?.statusReason = .providerUnsupportedInBuild
        }

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    /// SET-007-restore_ai_provider_connection_status: 최신 credential이 바뀌면 stale verification 결과를 저장하지 않는다.
    /// bootstrap 중 사용자가 credential을 갱신한 경우 이전 credential 검증 결과가 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: stale file load, latest file reload, save suppression
    /// - 사전 조건: 첫 load는 오래된 OpenAI credential, 두 번째 load는 새 credential을 반환한다.
    /// - 기대 결과: row는 connected로 표시되지만 save는 호출되지 않는다.
    func testBootstrapVerificationSkipsPersistWhenLatestCredentialChanged() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connectionFailed,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-old")),
            errorCode: .expired,
        )
        let latestFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connected,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-new")),
        )
        let loadSpy = ConnectionsFileLoadSpy(files: [staleFile, latestFile])
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { try await loadSpy.load() }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
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

        XCTAssertTrue(saveSpy.savedFiles.isEmpty)
    }

    /// SET-007-restore_ai_provider_connection_status: fresh install은 모든 provider를 not_verified로 표시한다.
    /// 저장 파일이 비어 있는 첫 실행 상태에서 기본 provider row가 연결 가능한 상태로 준비되는지 검증한다.
    /// - 검증 내용: empty connections file, default row count, connect primary action
    /// - 사전 조건: AI connections file이 비어 있다.
    /// - 기대 결과: 세 provider row가 not_verified이고 primary action은 connect다.
    func testOnAppear_freshInstall_showsAllNotVerified() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }

        await store.finish()

        let storeState = store.state
        XCTAssertEqual(storeState.rows.count, 3)
        for row in storeState.rows {
            XCTAssertEqual(row.connectionState, .notVerified)
            XCTAssertEqual(row.primaryAction, .connect)
        }
    }

    /// SET-007-restore_ai_provider_connection_status: invalid API key snapshot은 retry 가능한 실패로 복원된다.
    /// 저장된 invalid credential 상태가 bootstrap verification 후 connection_failed로 유지되는지 검증한다.
    /// - 검증 내용: invalidAPIKey snapshot, verification invalid response, retry action
    /// - 사전 조건: Anthropic snapshot이 connection_failed/invalidAPIKey다.
    /// - 기대 결과: row는 connection_failed/invalidAPIKey이고 primary action은 retry다.
    func testOnAppear_invalidAPIKeySnapshot_restoresFailed() async {
        let failedFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "bad-key")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .invalidAPIKey,
                    ),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { failedFile }
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.invalidAPIKey) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .anthropic]?.connectionState = .connectionFailed
            state.rows[id: .anthropic]?.statusReason = .invalidAPIKey
        }

        await store.finish()

        let anthropicRow = store.state.rows[id: .anthropic]
        XCTAssertEqual(anthropicRow?.connectionState, .connectionFailed)
        XCTAssertEqual(anthropicRow?.statusReason, .invalidAPIKey)
        XCTAssertEqual(anthropicRow?.primaryAction, .retry)
    }

    /// SET-007-restore_ai_provider_connection_status: load error는 bootstrapPhase를 failed로 둔다.
    /// connections file load 실패가 빈 목록 성공으로 오인되지 않는지 검증한다.
    /// - 검증 내용: load throw, bootstrapFailed action, row preservation
    /// - 사전 조건: aiConnectionsFileClient.load가 오류를 던진다.
    /// - 기대 결과: bootstrapPhase는 failed이고 기본 row 3개는 유지된다.
    func testOnAppear_loadError_setsFailedBootstrapPhase() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
        XCTAssertEqual(store.state.rows.count, 3)
    }

    /// SET-007-restore_ai_provider_connection_status: onAppear 재진입은 bootstrap을 중복 실행하지 않는다.
    /// 이미 bootstrap이 완료된 Settings AI 탭에서 재진입이 추가 load effect를 만들지 않는지 검증한다.
    /// - 검증 내용: first onAppear bootstrap, second onAppear ignored
    /// - 사전 조건: AI connections file이 비어 있고 첫 bootstrap이 완료됐다.
    /// - 기대 결과: 두 번째 onAppear는 state/effect를 만들지 않는다.
    func testOnAppear_calledTwice_onlyBootstrapsOnce() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }
        await store.finish()

        await store.send(.onAppear)
        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: disconnected snapshot은 disconnected로 복원된다.
    /// 명시적으로 연결 해제된 provider가 fresh not_verified와 구분되는지 검증한다.
    /// - 검증 내용: persisted disconnected snapshot, primary action
    /// - 사전 조건: OpenAI snapshot이 disconnected다.
    /// - 기대 결과: row는 disconnected이고 primary action은 connect다.
    func testOnAppear_disconnectedSnapshot_restoresDisconnected() async {
        let disconnectedFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnected),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { disconnectedFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .disconnected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.finish()

        let openaiRow = store.state.rows[id: .openai]
        XCTAssertEqual(openaiRow?.connectionState, .disconnected)
        XCTAssertEqual(openaiRow?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: credential 없는 connect_in_progress snapshot은 missingCredential로
    /// 복원된다.
    /// 이전 세션의 중단된 연결 시도가 credential 없이 connected로 이어지지 않는지 검증한다.
    /// - 검증 내용: connectInProgress snapshot, nil credential guard, missingCredential reason
    /// - 사전 조건: ChatGPT Codex snapshot은 connect_in_progress이고 credential은 nil이다.
    /// - 기대 결과: row는 not_verified/missingCredential 상태가 된다.
    func testOnAppear_connectInProgress_resetsToNotVerified() async {
        let inProgressFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { inProgressFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .missingCredential
        }

        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: disconnecting snapshot은 disconnected로 복원된다.
    /// 이전 세션에서 연결 해제 중 종료된 상태가 계속 진행 중으로 남지 않는지 검증한다.
    /// - 검증 내용: persisted disconnecting snapshot, disconnected state
    /// - 사전 조건: Anthropic snapshot이 disconnecting이다.
    /// - 기대 결과: row는 disconnected/none 상태가 된다.
    func testOnAppear_disconnecting_resetsToDisconnected() async {
        let disconnectingFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnecting),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { disconnectingFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .disconnected
            state.rows[id: .anthropic]?.statusReason = .none
        }

        await store.finish()
    }

    // MARK: - SET-007-bootstrap_phase

    /// `.idle` 초기 상태에서 rows는 `catalogRows()`로 즉시 채워진다.
    /// UI가 spinner 없이 placeholder rows를 표시할 수 있음을 보장.
    func testIdleState_hasNonEmptyRows_allNotVerified() {
        let state = AiSettingsState()

        XCTAssertEqual(state.bootstrapPhase, .idle)
        XCTAssertEqual(state.rows.count, 3)
        XCTAssertEqual(state.rows.map(\.provider), [.chatgptCodex, .openai, .anthropic])
        XCTAssertTrue(state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    /// `.loading` 상태를 직접 주입해도 rows는 유지된다.
    /// onAppear 직후, `.bootstrapCompleted` 수신 전 first paint가 rows를 표시할 수 있음을 보장.
    func testLoadingState_withExplicitPhase_preservesRows() {
        let rows = AiSettingsState.catalogRows()
        let state = AiSettingsState(
            didBootstrap: true,
            bootstrapPhase: .loading,
            rows: rows,
        )

        XCTAssertEqual(state.bootstrapPhase, .loading)
        XCTAssertEqual(state.rows.count, 3)
        XCTAssertTrue(state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    /// onAppear 직후 `.loading` phase에서 rows가 유지되는지 TestStore로 단언.
    /// `.bootstrapCompleted`가 도착하기 전 first paint 시점의 상태 검증.
    func testOnAppear_setsLoadingPhase_rowsRemainNonEmpty() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        XCTAssertEqual(store.state.bootstrapPhase, .loading)
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }
        await store.finish()
    }

    /// `bootstrapCompleted`가 notVerified/checkingStatus/connected 혼합 initial results를
    /// 정확히 row에 반영하고 phase를 `.loaded`로 전환하는지 검증.
    /// verification pending은 row의 `connectionState`(`.checkingStatus`)로 표현됨.
    func testBootstrapCompleted_appliesMixedInitialResults_setsLoadedPhase() async {
        let mixedResults = [
            AIProviderBootstrapResult(
                provider: .chatgptCodex,
                connectionState: .connected,
                statusReason: .none,
            ),
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: .checkingStatus,
                statusReason: .none,
            ),
            AIProviderBootstrapResult(
                provider: .anthropic,
                connectionState: .notVerified,
                statusReason: .missingCredential,
            ),
        ]
        let store = TestStore(
            initialState: AiSettingsState(
                didBootstrap: true,
                bootstrapPhase: .loading,
            ),
        ) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.bootstrapCompleted(mixedResults)) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .notVerified
            state.rows[id: .anthropic]?.statusReason = .missingCredential
        }

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .connected)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .checkingStatus)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .notVerified)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.statusReason, .missingCredential)
    }

    /// `bootstrapVerificationCompleted`는 `.loaded` phase를 유지하면서 row만 갱신.
    /// verification 결과가 첫 paint phase를 다시 `.loading`으로 되돌리지 않음을 보장.
    func testBootstrapVerificationCompleted_keepsLoadedPhase_updatesRows() async {
        let verificationResults = [
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: .connected,
                statusReason: .none,
            ),
        ]
        let store = TestStore(
            initialState: AiSettingsState(
                didBootstrap: true,
                bootstrapPhase: .loaded,
                rows: [
                    AiConnectionRowState(
                        provider: .openai,
                        connectionState: .checkingStatus,
                    ),
                    AiConnectionRowState(provider: .anthropic),
                    AiConnectionRowState(provider: .chatgptCodex),
                ],
            ),
        ) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.bootstrapVerificationCompleted(verificationResults)) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connected)
    }

    /// bootstrap file load 실패 시 `.failed` phase로 전환되지만 rows는 보존됨.
    func testBootstrapFailed_setsFailedPhase_preservesRows() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                throw NSError(domain: "test", code: -1)
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    // MARK: - SET-007-bootstrap_end_to_end

    /// End-to-end: onAppear → file load → `.bootstrapCompleted`(initial) →
    /// `.bootstrapVerificationCompleted` → 최종 `.loaded`. 3 provider 각각 다른
    /// verification 결과(connected/expired/connected)가 row에 정확히 반영되는지 검증.
    /// - 검증 내용: full pipeline, rows 3개 보존, 최종 connectionState, phase `.loaded`
    /// - 사전 조건: 3 provider 모두 credential 보유, snapshot이 verification 결과와 동일
    /// - 기대 결과: chatgpt=connected, openai=connectionFailed/expired, anthropic=connected
    func testOnAppear_fullBootstrapPipeline_appliesInitialAndVerificationResults_setsLoadedPhase() async {
        let file = Self.threeProviderFileMatchingOutcomes()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, _ in
                switch provider {
                case .chatgptCodex: .valid
                case .openai: .invalid(.expired)
                case .anthropic: .valid
                }
            }
        }

        XCTAssertEqual(store.state.bootstrapPhase, .idle)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
            state.rows[id: .anthropic]?.connectionState = .connected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .connected)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connectionFailed)
        XCTAssertEqual(store.state.rows[id: .openai]?.statusReason, .expired)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .connected)
    }

    /// Launch-like no-credential 상태: 모든 provider record에 credential이 없을 때
    /// bootstrap은 `.loaded`로 종료되며 rows는 처음부터 끝까지 3개 notVerified 상태로 유지.
    /// verification 단계가 생략되고도 spinner-only 상태로 떨어지지 않음을 보장.
    /// - 검증 내용: no-credential initial, verification 미실행, terminal `.loaded`, rows 보존
    /// - 사전 조건: 3 provider record 모두 credential=nil
    /// - 기대 결과: 모든 row notVerified/missingCredential, primaryAction=.connect, phase=.loaded
    func testNoCredentialLaunchState_keepsThreeRowsNotVerified_throughEntireBootstrap() async {
        let file = Self.threeProviderFileAllMissingCredentials()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, _ in
                XCTFail("Verification should not run when credential is nil: \(provider)")
                return .valid
            }
        }

        XCTAssertEqual(store.state.bootstrapPhase, .idle)
        XCTAssertEqual(store.state.rows.count, 3)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .missingCredential
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .missingCredential
            state.rows[id: .anthropic]?.connectionState = .notVerified
            state.rows[id: .anthropic]?.statusReason = .missingCredential
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })
        XCTAssertTrue(store.state.rows.allSatisfy { $0.statusReason == .missingCredential })
        XCTAssertTrue(store.state.rows.allSatisfy { $0.primaryAction == .connect })
    }

    /// File load 실패 → `.failed` phase + rows 3개 보존 → retry 시도 → bootstrap 재실행 성공.
    /// 실패 상태에서 rows가 사라지지 않고 명시적 retry로 전체 파이프라인이 회복되는지 검증.
    /// - 검증 내용: load throw, `.failed` 전이, rows 보존, retry → `.loading` → `.loaded` 회복
    /// - 사전 조건: 첫 load는 throw, 두 번째 load는 3 provider connected file 반환
    /// - 기대 결과: retry 후 모든 row 최종 connected, phase=`.loaded`
    func testFileLoadFailure_setsFailedPhase_preservesRows_retryRecoversAllThreeProviders() async {
        let loadCounter = LoadCounter()
        let recoveryFile = Self.threeProviderFileMatchingOutcomes(
            openaiStatus: .connected,
            openaiErrorCode: .none,
        )
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                let count = await loadCounter.increment()
                if count == 1 { throw NSError(domain: "e2e", code: -1) }
                return recoveryFile
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        XCTAssertEqual(store.state.rows.count, 3)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.retryBootstrapTapped) { state in
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .connected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .connected })
    }

    /// 단일 provider verification 결과가 networkError(timeout-style)여도 다른 provider
    /// row가 정상적으로 갱신됨을 보장. Task 4 병렬화의 회귀 방지 증거.
    /// - 검증 내용: networkError 결과가 형제 provider 갱신을 차단하지 않음, rows 보존
    /// - 사전 조건: 3 provider credential 보유, openai verification이 networkError 반환
    /// - 기대 결과: chatgpt/anthropic=connected, openai=connectionFailed/networkUnavailable
    func testOneProviderNetworkErrorResult_doesNotBlockOtherProviderRows() async {
        let file = Self.threeProviderFileMatchingOutcomes(
            openaiStatus: .connectionFailed,
            openaiErrorCode: .networkUnavailable,
        )
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, _ in
                switch provider {
                case .chatgptCodex: .valid
                case .openai: .networkError
                case .anthropic: .valid
                }
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .networkUnavailable
            state.rows[id: .anthropic]?.connectionState = .connected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .connected)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connectionFailed)
        XCTAssertEqual(store.state.rows[id: .openai]?.statusReason, .networkUnavailable)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .connected)
    }
}

// MARK: - Bootstrap fixtures

private extension SET007SettingsAIConnectionsTests {
    /// 3 provider가 모두 credential을 가지며 snapshot이 verification 결과와 일치하는 파일.
    /// 기본: chatgpt/anthropic=`.connected`, openai=`.connectionFailed/.expired`.
    /// snapshot이 결과와 동일하므로 persist 단계가 생략되어
    /// `.delegate(.connectionsFileUpdated)` 수신 예측이 불필요하다.
    static func threeProviderFileMatchingOutcomes(
        openaiStatus: ProviderConnectionState = .connectionFailed,
        openaiErrorCode: ProviderStatusReason = .expired,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: openaiStatus,
                        lastErrorCode: openaiErrorCode,
                    ),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }

    /// 3 provider record가 모두 credential=nil인 파일. launch-like no-credential 상태.
    static func threeProviderFileAllMissingCredentials() -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }
}
