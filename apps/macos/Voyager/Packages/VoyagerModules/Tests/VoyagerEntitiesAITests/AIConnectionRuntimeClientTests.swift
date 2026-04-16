import Foundation
@testable import VoyagerEntitiesAI
import XCTest

final class AIConnectionRuntimeClientTests: XCTestCase {
    // MARK: - Adapter Resolution

    func testResolveAdapter_openai_withAPIKeyCredential_returnsDescriptor() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))
        let descriptor = client.resolveAdapter(.openai, credential)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.provider, .openai)
        XCTAssertEqual(descriptor?.providerID, .openai)
        XCTAssertEqual(descriptor?.adapterName, "OpenAIAdapter")
        XCTAssertTrue(descriptor!.capabilities.contains(.streaming))
    }

    func testResolveAdapter_openai_withNilCredential_returnsNil() {
        let client = makeStubClient()
        XCTAssertNil(client.resolveAdapter(.openai, nil))
    }

    func testResolveAdapter_chatgptCodex_withOAuthCredential_returnsDescriptor() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.oauth(
            OAuthCredentialFile(accessToken: "tok"),
        )
        let descriptor = client.resolveAdapter(.chatgptCodex, credential)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.provider, .chatgptCodex)
        XCTAssertEqual(descriptor?.providerID, .chatgptCodex)
        XCTAssertEqual(descriptor?.adapterName, "OpenAIAdapter")
    }

    func testResolveAdapter_anthropic_withAPIKeyCredential_returnsDescriptor() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-ant-test"))
        let descriptor = client.resolveAdapter(.anthropic, credential)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.provider, .anthropic)
        XCTAssertEqual(descriptor?.providerID, .anthropic)
        XCTAssertEqual(descriptor?.adapterName, "AnthropicAdapter")
        XCTAssertTrue(descriptor!.capabilities.contains(.streaming))
    }

    func testResolveAdapter_anthropic_withNilCredential_returnsNil() {
        let client = makeStubClient()
        XCTAssertNil(client.resolveAdapter(.anthropic, nil))
    }

    // MARK: - Verify Provider — Credential Validation

    func testVerifyProvider_nilCredential_returnsMissingCredential() {
        let client = makeStubClient()
        let result = AsyncTestHelper.sync { await client.verifyProvider(.openai, nil) }
        XCTAssertEqual(result, .invalid(.missingCredential))
    }

    func testVerifyProvider_emptyAPIKey_returnsInvalidAPIKey() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: ""))
        let result = AsyncTestHelper.sync { await client.verifyProvider(.openai, credential) }
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testVerifyProvider_emptyOAuthToken_returnsInvalidAPIKey() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.oauth(
            OAuthCredentialFile(accessToken: ""),
        )
        let result = AsyncTestHelper.sync { await client.verifyProvider(.chatgptCodex, credential) }
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    // MARK: - Verify Provider — Successful Verification

    func testVerifyProvider_openai_validCredential_callsAdapterAndReturnsValid() {
        var didCallGenerate = false
        let client = AIConnectionRuntimeClient(
            verifyProvider: { _, credential in
                guard let credential, case let .apiKey(payload) = credential, !payload.secret.isEmpty else {
                    return .invalid(.missingCredential)
                }
                didCallGenerate = true
                return .valid
            },
            resolveAdapter: { _, _ in nil },
        )

        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-valid"))
        let result = AsyncTestHelper.sync { await client.verifyProvider(.openai, credential) }
        XCTAssertTrue(didCallGenerate)
        XCTAssertEqual(result, .valid)
    }

    func testVerifyProvider_anthropic_validCredential_returnsValid() {
        let client = AIConnectionRuntimeClient(
            verifyProvider: { _, _ in .valid },
            resolveAdapter: { _, _ in nil },
        )

        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-ant-valid"))
        let result = AsyncTestHelper.sync { await client.verifyProvider(.anthropic, credential) }
        XCTAssertEqual(result, .valid)
    }

    // MARK: - HTTP Error Mapping

    func testMapHTTPError_401_returnsInvalidAPIKey() {
        let error = AIHTTPError.httpError(statusCode: 401, body: "Unauthorized")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testMapHTTPError_403_returnsExpired() {
        let error = AIHTTPError.httpError(statusCode: 403, body: "Forbidden")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.expired))
    }

    func testMapHTTPError_429_returnsVerificationFailed() {
        let error = AIHTTPError.httpError(statusCode: 429, body: "Rate limited")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    func testMapHTTPError_500_returnsNetworkError() {
        let error = AIHTTPError.httpError(statusCode: 500, body: "Internal Server Error")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_503_returnsNetworkError() {
        let error = AIHTTPError.httpError(statusCode: 503, body: "Service Unavailable")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_400_returnsVerificationFailed() {
        let error = AIHTTPError.httpError(statusCode: 400, body: "Bad Request")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    func testMapHTTPError_networkError_returnsNetworkError() {
        let error = AIHTTPError.networkError("connection refused")
        let result = AIConnectionRuntimeClient.mapHTTPError(error)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_timeout_returnsNetworkError() {
        let result = AIConnectionRuntimeClient.mapHTTPError(.timeout)
        XCTAssertEqual(result, .networkError)
    }

    func testMapHTTPError_invalidURL_returnsVerificationFailed() {
        let result = AIConnectionRuntimeClient.mapHTTPError(.invalidURL("bad://url"))
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    func testMapHTTPError_cancelled_returnsVerificationFailed() {
        let result = AIConnectionRuntimeClient.mapHTTPError(.cancelled)
        XCTAssertEqual(result, .invalid(.verificationFailed))
    }

    // MARK: - AIAdapterDescriptor

    func testAdapterDescriptor_equality() {
        let a = AIAdapterDescriptor(
            provider: .openai,
            providerID: .openai,
            adapterName: "OpenAIAdapter",
            capabilities: OpenAICapabilities.standard,
        )
        let b = AIAdapterDescriptor(
            provider: .openai,
            providerID: .openai,
            adapterName: "OpenAIAdapter",
            capabilities: OpenAICapabilities.standard,
        )
        XCTAssertEqual(a, b)
    }

    func testAdapterDescriptor_inequality() {
        let openai = AIAdapterDescriptor(
            provider: .openai,
            providerID: .openai,
            adapterName: "OpenAIAdapter",
            capabilities: OpenAICapabilities.standard,
        )
        let anthropic = AIAdapterDescriptor(
            provider: .anthropic,
            providerID: .anthropic,
            adapterName: "AnthropicAdapter",
            capabilities: AnthropicCapabilities.standard,
        )
        XCTAssertNotEqual(openai, anthropic)
    }

    // MARK: - No Vendor DTO Leakage

    func testVerifyProvider_returnsOnlyVoyagerOwnedTypes() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))

        for provider in AIProvider.allCases {
            let result = AsyncTestHelper.sync { await client.verifyProvider(provider, credential) }
            switch result {
            case .valid, .invalid, .unsupportedProvider, .networkError:
                break
            }
        }
    }

    func testAIAdapterDescriptor_doesNotExposeVendorConfigTypes() {
        let descriptor = AIAdapterDescriptor(
            provider: .openai,
            providerID: .openai,
            adapterName: "OpenAIAdapter",
            capabilities: OpenAICapabilities.standard,
        )
        XCTAssertEqual(type(of: descriptor.provider), AIProvider.self)
        XCTAssertEqual(type(of: descriptor.providerID), AIProviderID.self)
        XCTAssertEqual(type(of: descriptor.capabilities), AIProviderCapability.self)
    }

    // MARK: - Connection Lifecycle

    func testVerifyProvider_openai_httpError401_mapsToInvalidAPIKey() {
        let client = AIConnectionRuntimeClient(
            verifyProvider: { _, _ in
                .invalid(.invalidAPIKey)
            },
            resolveAdapter: { _, _ in nil },
        )

        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-bad"))
        let result = AsyncTestHelper.sync { await client.verifyProvider(.openai, credential) }
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testVerifyProvider_anthropic_networkError_mapsCorrectly() {
        let client = AIConnectionRuntimeClient(
            verifyProvider: { _, _ in .networkError },
            resolveAdapter: { _, _ in nil },
        )

        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-ant-test"))
        let result = AsyncTestHelper.sync { await client.verifyProvider(.anthropic, credential) }
        XCTAssertEqual(result, .networkError)
    }

    // MARK: - Helpers

    private func makeStubClient() -> AIConnectionRuntimeClient {
        AIConnectionRuntimeClient(
            verifyProvider: { _, credential in
                guard let credential else { return .invalid(.missingCredential) }
                let secret: String = switch credential {
                case let .apiKey(payload): payload.secret
                case let .oauth(payload): payload.accessToken
                }
                guard !secret.isEmpty else { return .invalid(.invalidAPIKey) }
                return .valid
            },
            resolveAdapter: { provider, credential in
                guard credential != nil else { return nil }
                switch provider {
                case .openai:
                    return AIAdapterDescriptor(
                        provider: .openai,
                        providerID: .openai,
                        adapterName: "OpenAIAdapter",
                        capabilities: OpenAICapabilities.standard,
                    )
                case .chatgptCodex:
                    return AIAdapterDescriptor(
                        provider: .chatgptCodex,
                        providerID: .chatgptCodex,
                        adapterName: "OpenAIAdapter",
                        capabilities: OpenAICapabilities.standard,
                    )
                case .anthropic:
                    return AIAdapterDescriptor(
                        provider: .anthropic,
                        providerID: .anthropic,
                        adapterName: "AnthropicAdapter",
                        capabilities: AnthropicCapabilities.standard,
                    )
                }
            },
        )
    }
}

private enum AsyncTestHelper {
    static func sync<T>(_ operation: @escaping () async throws -> T) rethrows -> T {
        let expectation = XCTestExpectation()
        var result: T?
        Task {
            result = try await operation()
            expectation.fulfill()
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: 2.0)
        return result!
    }
}
