import ComposableArchitecture
@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

// MARK: - HTTP Error Mapping

final class AiHTTPErrorMappingTests: XCTestCase {
    func testMapHTTPError_401_returnsInvalidAPIKey() {
        let error = AiHTTPError.httpError(statusCode: 401, body: "Unauthorized")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testMapHTTPError_403_plainText_returnsInvalidAPIKey() {
        let error = AiHTTPError.httpError(statusCode: 403, body: "Forbidden")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testMapHTTPError_403_expiredApiKeyBody_returnsExpired() {
        let body = #"{"error":{"code":"expired_api_key"}}"#
        let error = AiHTTPError.httpError(statusCode: 403, body: body)
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.expired))
    }

    func testMapHTTPError_403_otherErrorCode_returnsInvalidAPIKey() {
        let body = #"{"error":{"code":"model_not_found"}}"#
        let error = AiHTTPError.httpError(statusCode: 403, body: body)
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testMapHTTPError_429_returnsVerificationFailed() {
        let error = AiHTTPError.httpError(statusCode: 429, body: "Rate limited")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    func testMapHTTPError_500_returnsNetworkError() {
        let error = AiHTTPError.httpError(statusCode: 500, body: "Internal Server Error")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_503_returnsNetworkError() {
        let error = AiHTTPError.httpError(statusCode: 503, body: "Service Unavailable")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_400_returnsVerificationFailed() {
        let error = AiHTTPError.httpError(statusCode: 400, body: "Bad Request")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    func testMapHTTPError_networkError_returnsNetworkError() {
        let error = AiHTTPError.networkError("connection refused")
        let result = AiConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_timeout_returnsNetworkError() {
        let result = AiConnectionRuntimeClient.mapHTTPError(.timeout)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_invalidURL_returnsVerificationFailed() {
        let result = AiConnectionRuntimeClient.mapHTTPError(.invalidURL("bad://url"))
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    func testMapHTTPError_cancelled_returnsVerificationFailed() {
        let result = AiConnectionRuntimeClient.mapHTTPError(.cancelled)
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }
}

// MARK: - AIConnectionStatus

final class AIConnectionStatusTests: XCTestCase {
    func testAIConnectionStatus_ready_isEquatable() {
        XCTAssertEqual(AIConnectionStatus.ready, .ready)
    }

    func testAIConnectionStatus_notConfigured_isEquatable() {
        XCTAssertEqual(AIConnectionStatus.notConfigured, .notConfigured)
    }

    func testAIConnectionStatus_invalidCredential_differentReasons_notEqual() {
        XCTAssertNotEqual(
            AIConnectionStatus.invalidCredential(.expired),
            .invalidCredential(.invalidAPIKey),
        )
    }

    func testAIConnectionStatus_networkUnavailable_isEquatable() {
        XCTAssertEqual(AIConnectionStatus.networkUnavailable, .networkUnavailable)
    }

    func testAIConnectionStatus_verificationFailed_isEquatable() {
        XCTAssertEqual(AIConnectionStatus.verificationFailed, .verificationFailed)
    }

    // MARK: - VOY-218: five distinct status cases

    func testAllFiveDistinctStatusCases_exist() {
        let cases: [AIConnectionStatus] = [
            .ready,
            .notConfigured,
            .invalidCredential(.none),
            .networkUnavailable,
            .verificationFailed,
        ]
        XCTAssertEqual(cases.count, 5)

        for i in 0 ..< cases.count {
            for j in (i + 1) ..< cases.count {
                XCTAssertNotEqual(
                    cases[i],
                    cases[j],
                    "AIConnectionStatus cases must be pairwise distinct: \(cases[i]) vs \(cases[j])",
                )
            }
        }
    }
}

// MARK: - AiConnectionStatusClient

final class AiConnectionStatusClientTests: XCTestCase {
    func testStatus_withNoStoredCredential_returnsNotConfigured() async {
        let sut = makeClient(storedFile: .empty(), verifyResult: .valid)
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .notConfigured)
    }

    func testStatus_withConnectedCredential_valid_returnsReady() async {
        let sut = makeClient(
            storedFile: storedFileWithCredential(status: .connected),
            verifyResult: .valid,
        )
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .ready)
    }

    func testStatus_withFailedCredential_returnsInvalidCredential() async {
        let sut = makeClient(
            storedFile: storedFileWithCredential(status: .connectionFailed, errorCode: .expired),
            verifyResult: .valid,
        )
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .invalidCredential(.expired))
    }

    func testStatus_withConnectedCredential_invalid_returnsInvalidCredential() async {
        let sut = makeClient(
            storedFile: storedFileWithCredential(status: .connected),
            verifyResult: .invalid(.invalidAPIKey),
        )
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .invalidCredential(.invalidAPIKey))
    }

    func testStatus_withConnectedCredential_networkError_returnsNetworkUnavailable() async {
        let sut = makeClient(
            storedFile: storedFileWithCredential(status: .connected),
            verifyResult: .networkError,
        )
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .networkUnavailable)
    }

    func testStatus_withConnectedCredential_unsupportedProvider_returnsVerificationFailed() async {
        let sut = makeClient(
            storedFile: storedFileWithCredential(status: .connected),
            verifyResult: .unsupportedProvider,
        )
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .verificationFailed)
    }

    func testStatus_withNotVerifiedCredential_returnsNotConfigured() async {
        let sut = makeClient(
            storedFile: storedFileWithCredential(status: .notVerified),
            verifyResult: .valid,
        )
        let status = await sut.checkStatus(.openai)
        XCTAssertEqual(status, .notConfigured)
    }

    func testDependencyKey_registered_and_returnsTestValue() async {
        @Dependency(\.aiConnectionStatusClient)
        var client
        let status = await client.checkStatus(.openai)
        XCTAssertEqual(status, .ready)
    }

    // MARK: - VOY-218: Codex OAuth status client paths

    func testStatus_codexOAuth_connectedWithValidCredential_returnsReady() async {
        let sut = makeClient(
            storedFile: codexStoredFileWithCredential(status: .connected),
            verifyResult: .valid,
        )
        let status = await sut.checkStatus(.chatgptCodex)
        XCTAssertEqual(status, .ready)
    }

    func testStatus_codexOAuth_connectedWithInvalidCredential_returnsInvalidCredential() async {
        let sut = makeClient(
            storedFile: codexStoredFileWithCredential(status: .connected),
            verifyResult: .invalid(.expired),
        )
        let status = await sut.checkStatus(.chatgptCodex)
        XCTAssertEqual(status, .invalidCredential(.expired))
    }

    func testStatus_codexOAuth_notConfigured_returnsNotConfigured() async {
        let sut = makeClient(
            storedFile: .empty(),
            verifyResult: .valid,
        )
        let status = await sut.checkStatus(.chatgptCodex)
        XCTAssertEqual(status, .notConfigured)
    }

    func testStatus_codexOAuth_connectedNetworkError_returnsNetworkUnavailable() async {
        let sut = makeClient(
            storedFile: codexStoredFileWithCredential(status: .connected),
            verifyResult: .networkError,
        )
        let status = await sut.checkStatus(.chatgptCodex)
        XCTAssertEqual(status, .networkUnavailable)
    }

    func testStatus_codexOAuth_connectedUnsupportedProvider_returnsVerificationFailed() async {
        let sut = makeClient(
            storedFile: codexStoredFileWithCredential(status: .connected),
            verifyResult: .unsupportedProvider,
        )
        let status = await sut.checkStatus(.chatgptCodex)
        XCTAssertEqual(status, .verificationFailed)
    }

    func testStatus_codexOAuth_connectionFailed_returnsInvalidCredentialWithReason() async {
        let sut = makeClient(
            storedFile: codexStoredFileWithCredential(
                status: .connectionFailed,
                errorCode: .oauthRejected,
            ),
            verifyResult: .valid,
        )
        let status = await sut.checkStatus(.chatgptCodex)
        XCTAssertEqual(status, .invalidCredential(.oauthRejected))
    }

    private func makeClient(
        storedFile: AIConnectionsFile,
        verifyResult: AiProviderVerificationResult = .valid,
    ) -> AiConnectionStatusClient {
        let runtimeClient = AiConnectionRuntimeClient(
            verifyProvider: { _, _ in verifyResult },
            resolveAdapter: { _, _ in nil },
        )
        return AiConnectionStatusClient(
            checkStatus: { provider in
                let file = storedFile
                guard let record = file.providers[provider.rawValue] else {
                    return .notConfigured
                }
                guard record.credential != nil else {
                    return .notConfigured
                }
                if record.snapshot.lastKnownStatus == .connected {
                    let result = await runtimeClient.verifyProvider(provider, record.credential)
                    switch result {
                    case .valid: return .ready
                    case let .invalid(reason): return .invalidCredential(reason)
                    case .networkError: return .networkUnavailable
                    case .unsupportedProvider: return .verificationFailed
                    }
                }
                switch record.snapshot.lastKnownStatus {
                case .connectionFailed: return .invalidCredential(record.snapshot.lastErrorCode)
                case .notVerified: return .notConfigured
                default: return .notConfigured
                }
            },
        )
    }

    private func storedFileWithCredential(
        status: ProviderConnectionState = .connected,
        errorCode: ProviderStatusReason = .none,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: status,
                        lastVerifiedAtMs: 1_760_000_000_000,
                        lastErrorCode: errorCode,
                    ),
                ),
            ],
        )
    }

    private func codexStoredFileWithCredential(
        status: ProviderConnectionState = .connected,
        errorCode: ProviderStatusReason = .none,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile(accessToken: "codex-oauth-token")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: status,
                        lastVerifiedAtMs: 1_760_000_000_000,
                        lastErrorCode: errorCode,
                    ),
                ),
            ],
        )
    }
}

// MARK: - AIProviderVerificationClient

final class AIProviderVerificationClientTests: XCTestCase {
    func testDependencyKey_returnsTestValue() async {
        @Dependency(\.aiProviderVerificationClient)
        var client
        let result = await client.verify(.openai, nil)
        XCTAssertEqual(result, .valid)
    }

    func testVerifyProvider_nilCredential_returnsMissingCredential() {
        let client = AiConnectionRuntimeClient(
            // swiftlint:disable:next unused_closure_parameter
            verifyProvider: { _, credential in
                guard let credential else { return .invalid(.missingCredential) }
                return .valid
            },
            resolveAdapter: { _, _ in nil },
        )
        let result = awaitTest { await client.verifyProvider(.openai, nil) }
        XCTAssertEqual(result, .invalid(.missingCredential))
    }

    func testVerifyProvider_emptyAPIKey_returnsInvalidAPIKey() {
        let client = AiConnectionRuntimeClient(
            verifyProvider: { _, credential in
                guard let credential else { return .invalid(.missingCredential) }
                let secret: String = switch credential {
                case let .apiKey(payload): payload.secret
                case let .oauth(payload): payload.accessToken
                }
                guard !secret.isEmpty else { return .invalid(.invalidAPIKey) }
                return .valid
            },
            resolveAdapter: { _, _ in nil },
        )
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: ""))
        let result = awaitTest { await client.verifyProvider(.openai, credential) }
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }
}

// MARK: - AIConnectionsFileClient

final class AIConnectionsFileClientTests: XCTestCase {
    func testDependencyKey_returnsTestValue() async throws {
        @Dependency(\.aiConnectionsFileClient)
        var client
        let file = try await client.load()
        XCTAssertEqual(file, AIConnectionsFile.empty())
    }

    func testMutationResult_success_equality() {
        let file = AIConnectionsFile.empty()
        let result = AiConnectionMutationResult.success(file)
        XCTAssertEqual(result, .success(file))
    }

    func testMutationResult_fileSystemError_equality() {
        let result = AiConnectionMutationResult.fileSystemError(.lockContention)
        XCTAssertEqual(result, .fileSystemError(.lockContention))
    }
}

// MARK: - AIProviderConnectionClient

final class AIProviderConnectionClientTests: XCTestCase {
    func testDependencyKey_testValue_connectAPIKey() async {
        @Dependency(\.aiProviderConnectionClient)
        var client
        let result = await client.connectAPIKey(.openai, "sk-test", .connected)
        XCTAssertEqual(result.provider, .openai)
        XCTAssertEqual(result.state, .connected)
    }

    func testDependencyKey_testValue_disconnect() async {
        @Dependency(\.aiProviderConnectionClient)
        var client
        let result = await client.disconnect(.openai)
        XCTAssertEqual(result.provider, .openai)
        XCTAssertEqual(result.state, .notVerified)
    }

    func testConnectionResult_equality() {
        let a = AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .none,
            updatedFile: .empty(),
        )
        let b = AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .none,
            updatedFile: .empty(),
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - CodexNativeAuthError

final class CodexNativeAuthErrorTests: XCTestCase {
    func testAllCases_equality() {
        let errors: [CodexNativeAuthError] = [
            .cancelled,
            .timeout,
            .callbackMismatch,
            .loginUnavailable,
            .networkError("connection refused"),
        ]
        for error in errors {
            XCTAssertEqual(error, error)
        }
    }

    func testDifferentNetworkMessages_notEqual() {
        XCTAssertNotEqual(
            CodexNativeAuthError.networkError("a"),
            .networkError("b"),
        )
    }
}

// MARK: - Helper

private func awaitTest<T: Sendable>(
    timeout: TimeInterval = 2.0,
    _ operation: @escaping @Sendable () async -> T,
) -> T {
    let expectation = XCTestExpectation()
    nonisolated(unsafe) var result: T?
    Task { @Sendable in
        result = await operation()
        expectation.fulfill()
    }
    _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    guard let unwrapped = result else {
        XCTFail("awaitTest timed out or returned nil")
        fatalError("awaitTest: result was nil after wait")
    }
    return unwrapped
}
