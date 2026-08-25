import VoyagerEntitiesAppPreferences
import VoyagerShared
import XCTest

final class SettingsDefaultsTests: XCTestCase {
    func testDefaultTabPathReturnsStoredLegacyValueByteForByte() {
        let legacyPath = "/tmp/voy-744/legacy folder/日本語"
        let client = UserDefaultsClient.testValue
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultTabPath(userDefaultsClient: client), legacyPath)
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    func testMissingDiscriminatorAndLegacyPathPersistHome() {
        let client = UserDefaultsClient.testValue

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "home")
    }

    func testMissingDiscriminatorMigratesNonemptyLegacyPathToDirectory() {
        let legacyPath = "/tmp/voy-744/legacy"
        let client = UserDefaultsClient.testValue
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .directory(legacyPath))
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "directory")
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    func testExplicitHomeIgnoresRetainedLegacyDirectoryPayload() {
        let legacyPath = "/tmp/voy-744/retained"
        let client = UserDefaultsClient.testValue
        client.setString("home", SettingsKeys.defaultStartPageType)
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    func testExplicitDirectoryUsesRetainedLegacyPathWithoutRewritingIt() {
        let legacyPath = "/tmp/voy-744/explicit"
        let client = UserDefaultsClient.testValue
        client.setString("directory", SettingsKeys.defaultStartPageType)
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .directory(legacyPath))
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    func testUnknownDiscriminatorFallsBackToHomeAndRetainsLegacyPath() {
        let legacyPath = "/tmp/voy-744/unknown"
        let client = UserDefaultsClient.testValue
        client.setString("future", SettingsKeys.defaultStartPageType)
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "home")
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
    }

    func testEmptyDiscriminatorAndLegacyPayloadFallBackToHome() {
        let client = UserDefaultsClient.testValue
        client.setString("", SettingsKeys.defaultStartPageType)
        client.setString("", SettingsKeys.defaultTabPath)

        XCTAssertEqual(SettingsDefaults.defaultStartPage(userDefaultsClient: client), .home)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "home")
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), "")
    }

    func testMigratedSnapshotIsStableAcrossReloads() {
        let legacyPath = "/tmp/voy-744/stable"
        let client = UserDefaultsClient.testValue
        client.setString(legacyPath, SettingsKeys.defaultTabPath)

        let first = SettingsDefaults.defaultStartPage(userDefaultsClient: client)
        let second = SettingsDefaults.defaultStartPage(userDefaultsClient: client)

        XCTAssertEqual(first, .directory(legacyPath))
        XCTAssertEqual(second, first)
        XCTAssertEqual(client.string(SettingsKeys.defaultTabPath), legacyPath)
        XCTAssertEqual(client.string(SettingsKeys.defaultStartPageType), "directory")
    }
}
