@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

/// Recovered from old AIConnectionRuntimeClientTests (9d3be186).
/// Adapted for the simplified AiAdapterDescriptor (no providerID/capabilities fields).
final class AiRuntimeAdapterTests: XCTestCase {
    // MARK: - Adapter Resolution

    func testResolveAdapter_openai_withAPIKeyCredential_returnsDescriptor() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))
        let descriptor = client.resolveAdapter(.openai, credential)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.provider, .openai)
        XCTAssertEqual(descriptor?.adapterName, "OpenAIAdapter")
    }

    func testResolveAdapter_openai_withNilCredential_returnsNil() {
        let client = makeStubClient()
        XCTAssertNil(client.resolveAdapter(.openai, nil))
    }

    func testResolveAdapter_chatgptCodex_withOAuthCredential_returnsDescriptor() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.oauth(
            OAuthCredentialFile(accessToken: "tok")
        )
        let descriptor = client.resolveAdapter(.chatgptCodex, credential)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.provider, .chatgptCodex)
        XCTAssertEqual(descriptor?.adapterName, "OpenAIAdapter")
    }

    func testResolveAdapter_anthropic_withAPIKeyCredential_returnsDescriptor() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-ant-test"))
        let descriptor = client.resolveAdapter(.anthropic, credential)

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.provider, .anthropic)
        XCTAssertEqual(descriptor?.adapterName, "AnthropicAdapter")
    }

    func testResolveAdapter_anthropic_withNilCredential_returnsNil() {
        let client = makeStubClient()
        XCTAssertNil(client.resolveAdapter(.anthropic, nil))
    }

    // MARK: - Verify Provider with stubs

    func testVerifyProvider_openai_validCredential_callsVerifyAndReturnsValid() {
        nonisolated(unsafe) var didCallVerify = false
        let client = AiConnectionRuntimeClient(
            verifyProvider: { _, credential in
                guard let credential, case let .apiKey(payload) = credential, !payload.secret.isEmpty else {
                    return .invalid(.missingCredential)
                }
                didCallVerify = true
                return .valid
            },
            resolveAdapter: { _, _ in nil }
        )

        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-valid"))
        let result = awaitTest { await client.verifyProvider(.openai, credential) }
        XCTAssertTrue(didCallVerify)
        XCTAssertEqual(result, .valid)
    }

    func testVerifyProvider_anthropic_validCredential_returnsValid() {
        let client = AiConnectionRuntimeClient(
            verifyProvider: { _, _ in .valid },
            resolveAdapter: { _, _ in nil }
        )

        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-ant-valid"))
        let result = awaitTest { await client.verifyProvider(.anthropic, credential) }
        XCTAssertEqual(result, .valid)
    }

    func testLiveVerifyProvider_chatgptCodex_doesNotCallPlatformAPI() {
        NetworkTrapURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkTrapURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AiConnectionRuntimeClient.live(session: session)
        let credential = StoredCredentialPayload.oauth(
            OAuthCredentialFile(accessToken: "codex-access-token")
        )

        let result = awaitTest { await client.verifyProvider(.chatgptCodex, credential) }

        XCTAssertEqual(result, .valid)
        XCTAssertEqual(NetworkTrapURLProtocol.requestCount, 0)
    }

    // MARK: - VOY-218: chatgptCodex verification does NOT call Platform API

    /// VOY-218 intentional decision: a non-empty OAuth credential for chatgptCodex
    /// returns `.valid` without ANY network call. The live client short-circuits
    /// before reaching the smoke-request path.
    func testLiveVerifyProvider_chatgptCodex_nonEmptyOAuthCredential_isValidWithoutNetwork() {
        NetworkTrapURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkTrapURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AiConnectionRuntimeClient.live(session: session)
        let credential = StoredCredentialPayload.oauth(
            OAuthCredentialFile(accessToken: "codex-oauth-access-token-voY218")
        )

        let result = awaitTest { await client.verifyProvider(.chatgptCodex, credential) }

        // Core VOY-218 contract: non-empty OAuth credential = valid, zero network calls
        XCTAssertEqual(result, .valid, "chatgptCodex with non-empty OAuth must return .valid")
        XCTAssertEqual(
            NetworkTrapURLProtocol.requestCount, 0,
            "chatgptCodex verification must NOT issue any HTTP request"
        )
    }

    /// VOY-218: chatgptCodex with empty OAuth credential returns .invalid — still no network call.
    func testLiveVerifyProvider_chatgptCodex_emptyOAuthCredential_isInvalidWithoutNetwork() {
        NetworkTrapURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkTrapURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AiConnectionRuntimeClient.live(session: session)
        let credential = StoredCredentialPayload.oauth(
            OAuthCredentialFile(accessToken: "")
        )

        let result = awaitTest { await client.verifyProvider(.chatgptCodex, credential) }

        XCTAssertNotEqual(result, .valid, "Empty OAuth credential must not be treated as valid")
        XCTAssertEqual(
            NetworkTrapURLProtocol.requestCount, 0,
            "chatgptCodex verification must NOT issue any HTTP request even for empty credential"
        )
    }

    // MARK: - AiAdapterDescriptor

    func testAdapterDescriptor_equality() {
        let a = AiAdapterDescriptor(provider: .openai, adapterName: "OpenAIAdapter")
        let b = AiAdapterDescriptor(provider: .openai, adapterName: "OpenAIAdapter")
        XCTAssertEqual(a, b)
    }

    func testAdapterDescriptor_inequality() {
        let openai = AiAdapterDescriptor(provider: .openai, adapterName: "OpenAIAdapter")
        let anthropic = AiAdapterDescriptor(provider: .anthropic, adapterName: "AnthropicAdapter")
        XCTAssertNotEqual(openai, anthropic)
    }

    // MARK: - No Vendor DTO Leakage

    func testVerifyProvider_returnsOnlyVoyagerOwnedTypes() {
        let client = makeStubClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))

        for provider in AiProvider.allCases {
            let result = awaitTest { await client.verifyProvider(provider, credential) }
            switch result {
            case .valid, .invalid, .unsupportedProvider, .networkError:
                break
            }
        }
    }

    func testAIAdapterDescriptor_doesNotExposeVendorConfigTypes() {
        let descriptor = AiAdapterDescriptor(provider: .openai, adapterName: "OpenAIAdapter")
        XCTAssertTrue(type(of: descriptor.provider) == AiProvider.self)
        XCTAssertTrue(type(of: descriptor.adapterName) == String.self)
    }

    // MARK: - Helpers

    private func makeStubClient() -> AiConnectionRuntimeClient {
        AiConnectionRuntimeClient(
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
                    return AiAdapterDescriptor(provider: .openai, adapterName: "OpenAIAdapter")
                case .chatgptCodex:
                    return AiAdapterDescriptor(provider: .chatgptCodex, adapterName: "OpenAIAdapter")
                case .anthropic:
                    return AiAdapterDescriptor(provider: .anthropic, adapterName: "AnthropicAdapter")
                }
            }
        )
    }
}

private final class NetworkTrapURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated(unsafe) static var count = 0

    static var requestCount: Int { count }

    static func reset() {
        count = 0
    }

    override class func canInit(with _: URLRequest) -> Bool {
        count += 1
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let error = URLError(.unsupportedURL)
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}

private func awaitTest<T: Sendable>(
    timeout: TimeInterval = 2.0,
    _ operation: @escaping @Sendable () async -> T
) -> T {
    let expectation = XCTestExpectation()
    nonisolated(unsafe) var result: T?
    Task { @Sendable in
        result = await operation()
        expectation.fulfill()
    }
    _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    return result!
}
