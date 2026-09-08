import Foundation
import os.log

public extension Logger {
    /// Lock-protected subsystem configuration. Legacy synchronous API is kept;
    /// the single mutable value lives behind one lock (its documented invariant).
    private static let subsystemBox = SubsystemBox()

    private final class SubsystemBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = "com.acp"

        var current: String {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: String) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    /// Configure the logging subsystem (call once at initialization)
    static func configureACPLogging(subsystem: String) {
        subsystemBox.set(subsystem)
    }

    /// Create a logger for a specific category
    static func forCategory(_ category: String) -> Logger {
        Logger(subsystem: subsystemBox.current, category: category)
    }

    /// Convenience logger for ACP
    static let acp = Logger.forCategory("ACP")
}
