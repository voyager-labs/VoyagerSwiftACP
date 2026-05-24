import Foundation

final class MutationRecorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [T] = []

    func record(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        recordedValues.append(value)
    }

    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}

final class InMemoryStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var bools: [String: Bool] = [:]
    private var strings: [String: String] = [:]
    private var objects: [String: Any] = [:]

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
