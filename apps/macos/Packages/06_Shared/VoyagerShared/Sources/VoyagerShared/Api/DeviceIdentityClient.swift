import ComposableArchitecture
import Foundation
import IOKit

// MARK: - Client

public struct DeviceIdentityClient: Sendable {
    public var deviceId: @Sendable () throws -> String

    nonisolated public init(deviceId: @escaping @Sendable () throws -> String) {
        self.deviceId = deviceId
    }
}

// MARK: - IOKit Helper

extension DeviceIdentityClient {
    private static func platformUUID() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard
            let uuid = IORegistryEntryCreateCFProperty(
                service,
                kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault,
                0,
            )?.takeRetainedValue() as? String
        else { return nil }
        return uuid
    }
}

// MARK: - DependencyKey

extension DeviceIdentityClient: DependencyKey {
    nonisolated public static var liveValue: DeviceIdentityClient {
        DeviceIdentityClient(
            deviceId: {
                guard let uuid = platformUUID() else {
                    throw DeviceIdentityError.platformUUIDUnavailable
                }
                return uuid
            },
        )
    }

    nonisolated public static var testValue: DeviceIdentityClient {
        DeviceIdentityClient(
            deviceId: { "test-device-id" },
        )
    }

    nonisolated public static var previewValue: DeviceIdentityClient {
        testValue
    }
}

// MARK: - Error

public enum DeviceIdentityError: Error, Equatable, Sendable {
    case platformUUIDUnavailable
}

// MARK: - DependencyValues

public extension DependencyValues {
    nonisolated var deviceIdentityClient: DeviceIdentityClient {
        get { self[DeviceIdentityClient.self] }
        set { self[DeviceIdentityClient.self] = newValue }
    }
}
