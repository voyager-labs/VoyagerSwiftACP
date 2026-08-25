import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared
import XCTest

final class StartPageResolverTests: XCTestCase {
    func testHomeDoesNotProbe() {
        let probeCount = Counter()
        let client = StartPageAvailabilityClient { _ in
            probeCount.value += 1
            return .missing
        }

        let result = withDependencies {
            $0.startPageAvailabilityClient = client
        } operation: {
            StartPageResolver.resolve(.home)
        }

        XCTAssertEqual(result.effectiveStartPage, .home)
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(probeCount.value, 0)
    }

    func testAvailableDirectoryResolvesToDirectory() {
        let path = "/tmp/voy-744-available"
        let result = withDependencies {
            $0.startPageAvailabilityClient = StartPageAvailabilityClient { _ in .availableDirectory }
        } operation: {
            StartPageResolver.resolve(.directory(path))
        }

        XCTAssertEqual(result.effectiveStartPage, .directory(path))
        XCTAssertNil(result.fallbackReason)
    }

    func testDirectoryFailuresFallbackToHomeWithoutPersistence() {
        let failures: [StartPageDirectoryAvailability] = [
            .missing,
            .nonDirectory,
            .permissionDenied,
            .cloudPlaceholder,
        ]

        for failure in failures {
            let path = "/tmp/voy-744-canary-\(failure)"
            let storage = RecordingUserDefaults()
            storage.values[SettingsKeys.defaultStartPageType] = "directory"
            storage.values[SettingsKeys.defaultTabPath] = path
            let result = withDependencies {
                $0.startPageAvailabilityClient = StartPageAvailabilityClient { _ in failure }
                $0.userDefaultsClient = storage.client
            } operation: {
                StartPageResolver.resolve(.directory(path))
            }

            XCTAssertEqual(result.effectiveStartPage, .home)
            XCTAssertEqual(result.fallbackReason, .init(availability: failure))
            XCTAssertEqual(storage.writeCount, 0)
            XCTAssertEqual(storage.values[SettingsKeys.defaultStartPageType], "directory")
            XCTAssertEqual(storage.values[SettingsKeys.defaultTabPath], path)
            XCTAssertFalse(String(describing: result).contains(path))
        }
    }

    func testLiveProbeResolvesTemporaryDirectory() throws {
        let sandbox = try FileManagerFixtureSandbox()
        defer { sandbox.cleanup() }

        let result = withDependencies {
            $0.startPageAvailabilityClient = .liveValue
        } operation: {
            StartPageResolver.resolve(.directory(sandbox.directory.path))
        }

        XCTAssertEqual(result.effectiveStartPage, .directory(sandbox.directory.path))
        XCTAssertNil(result.fallbackReason)
    }
}

private final class RecordingUserDefaults: @unchecked Sendable {
    var values: [String: String] = [:]
    var writeCount = 0

    var client: UserDefaultsClient {
        UserDefaultsClient(
            bool: { _ in false },
            setBool: { _, _ in self.writeCount += 1 },
            string: { key in self.values[key] },
            setString: { value, key in
                self.writeCount += 1
                self.values[key] = value
            },
            double: { _ in 0 },
            setDouble: { _, _ in self.writeCount += 1 },
            object: { _ in nil },
            setObject: { _, _ in self.writeCount += 1 },
        )
    }
}

private final class Counter: @unchecked Sendable {
    var value = 0
}

private struct FileManagerFixtureSandbox {
    let root: URL
    let directory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerAppPreferencesFixture-\(UUID().uuidString)", isDirectory: true)
        directory = root.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
