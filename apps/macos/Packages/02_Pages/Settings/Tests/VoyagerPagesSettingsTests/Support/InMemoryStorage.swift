import Foundation

final class InMemoryStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var bools: [String: Bool] = [:]
    private var strings: [String: String] = [:]
    private var objects: [String: Any] = [:]
    private(set) var stringWriteCount = 0

    func setBool(_ value: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        bools[key] = value
    }

    func getBool(_ key: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return bools[key]
    }

    func setString(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        strings[key] = value
        stringWriteCount += 1
    }

    func getString(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return strings[key]
    }

    func setDouble(_ value: Double, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        objects[key] = value
    }

    func getDouble(_ key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return objects[key] as? Double
    }

    func setObject(_ value: Any?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        objects[key] = value
    }

    func getObject(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return objects[key]
    }
}
