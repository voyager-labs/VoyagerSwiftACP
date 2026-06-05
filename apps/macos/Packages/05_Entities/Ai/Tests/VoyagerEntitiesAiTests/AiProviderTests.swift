@testable import VoyagerEntitiesAi
import XCTest

final class AiProviderTests: XCTestCase {
    // MARK: - Provider catalog

    func testProviderSet_hasExactlyThreeProviders() {
        XCTAssertEqual(AiProvider.allCases.count, 3)
        XCTAssertTrue(AiProvider.allCases.contains(.chatgptCodex))
        XCTAssertTrue(AiProvider.allCases.contains(.openai))
        XCTAssertTrue(AiProvider.allCases.contains(.anthropic))
    }

    func testProviderRawValues_areStable() {
        XCTAssertEqual(AiProvider.chatgptCodex.rawValue, "chatgptCodex")
        XCTAssertEqual(AiProvider.openai.rawValue, "openai")
        XCTAssertEqual(AiProvider.anthropic.rawValue, "anthropic")
    }

    // MARK: - Auth method per provider

    func testChatGPTCodex_usesOAuth() {
        let descriptor = ProviderDescriptor.descriptor(for: .chatgptCodex)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.authMethod, .oauth)
    }

    func testOpenAI_usesAPIKey() {
        let descriptor = ProviderDescriptor.descriptor(for: .openai)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.authMethod, .apiKey)
    }

    func testAnthropic_usesAPIKey() {
        let descriptor = ProviderDescriptor.descriptor(for: .anthropic)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.authMethod, .apiKey)
    }

    // MARK: - V1 catalog

    func testV1Catalog_hasExactlyThreeEntries() {
        XCTAssertEqual(ProviderDescriptor.v1Catalog.count, 3)
    }

    func testV1Catalog_isSorted() {
        let sortOrders = ProviderDescriptor.v1Catalog.map(\.sortOrder)
        XCTAssertEqual(sortOrders, [0, 1, 2])
    }

    func testV1Catalog_matchesAllProviders() {
        let catalogProviders = Set(ProviderDescriptor.v1Catalog.map(\.provider))
        XCTAssertEqual(catalogProviders, ProviderDescriptor.supportedProviders)
        XCTAssertEqual(catalogProviders, Set(AiProvider.allCases))
    }

    func testDescriptorFor_knownProvider_returnsDescriptor() {
        for provider in AiProvider.allCases {
            XCTAssertNotNil(ProviderDescriptor.descriptor(for: provider))
        }
    }

    // MARK: - Codable

    func testAIProvider_roundTrips() throws {
        for provider in AiProvider.allCases {
            let encoded = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(AiProvider.self, from: encoded)
            XCTAssertEqual(decoded, provider)
        }
    }

    func testProviderAuthMethod_roundTrips() throws {
        for method in [ProviderAuthMethod.oauth, .apiKey, .codexCLI] {
            let encoded = try JSONEncoder().encode(method)
            let decoded = try JSONDecoder().decode(ProviderAuthMethod.self, from: encoded)
            XCTAssertEqual(decoded, method)
        }
    }

    func testProviderConnectPath_roundTrips() throws {
        for path in [ProviderConnectPath.browserLogin, .deviceAuth, .legacyImport] {
            let encoded = try JSONEncoder().encode(path)
            let decoded = try JSONDecoder().decode(ProviderConnectPath.self, from: encoded)
            XCTAssertEqual(decoded, path)
        }
    }
}
