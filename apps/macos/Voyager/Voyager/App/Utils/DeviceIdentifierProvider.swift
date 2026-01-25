import Foundation
import IOKit

enum DeviceIdentifierProvider {
    static func current() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let uuid = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0,
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return uuid
    }
}
