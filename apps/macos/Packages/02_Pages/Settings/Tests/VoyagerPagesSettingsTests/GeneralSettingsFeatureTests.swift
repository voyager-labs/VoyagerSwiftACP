import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class GeneralSettingsFeatureTests: XCTestCase {
    func testToggleAutomaticUpdatePersists() async {
        let storage = BoolStorage()
        let userDefaultsClient = UserDefaultsClient(
            bool: { key in
                storage.get(key) ?? false
            },
            setBool: { value, key in
                storage.set(value, forKey: key)
            },
            string: { _ in nil },
            setString: { _, _ in },
            double: { _ in 0.0 },
            setDouble: { _, _ in },
            object: { key in
                storage.get(key)
            },
            setObject: { value, key in
                if let boolValue = value as? Bool {
                    storage.set(boolValue, forKey: key)
                }
            }
        )

        let store = TestStore(initialState: GeneralSettingsFeature.State()) {
            GeneralSettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = userDefaultsClient
        }

        await store.send(.toggleAutomaticUpdate(true)) { state in
            state.automaticUpdate = true
            state.automaticUpdateError = nil
        }
        await store.finish()

        XCTAssertEqual(storage.get(SettingsKeys.automaticUpdate), true)
    }
}

private final class BoolStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Bool] = [:]

    func set(_ value: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func get(_ key: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
}

// swiftlint:enable xct_specific_matcher
