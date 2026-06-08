import Foundation
@testable import VoyagerEntitiesAppPreferences
import VoyagerShared
import XCTest

final class CollectionSearchAISettingsClientTests: XCTestCase {
    func testLoadReturnsDefaultWhenMissing() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)

        XCTAssertEqual(client.load(), .default)
    }

    func testSaveAndLoadRoundTrip() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        let settings = CollectionSearchAISettings(
            provider: .specific("openai"),
            model: .specific(provider: "openai", model: "gpt-4o-mini"),
            thinking: .effort("low"),
        )

        client.save(settings)

        XCTAssertEqual(client.load(), settings)
    }

    func testLoadReturnsDefaultWhenDataIsCorrupt() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        userDefaultsClient.setObject(Data([0x00, 0x01, 0x02]), SettingsKeys.collectionSearchAISettings)

        XCTAssertEqual(client.load(), .default)
        XCTAssertNotNil(userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data)
    }

    func testResetRemovesStoredValue() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        client.save(
            CollectionSearchAISettings(
                provider: .specific("anthropic"),
                model: .specific(provider: "anthropic", model: "claude-3-5-sonnet"),
                thinking: .providerDefault,
            ),
        )

        XCTAssertNotNil(userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data)

        client.reset()

        XCTAssertNil(userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data)
        XCTAssertEqual(client.load(), .default)
    }
}
