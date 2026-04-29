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
