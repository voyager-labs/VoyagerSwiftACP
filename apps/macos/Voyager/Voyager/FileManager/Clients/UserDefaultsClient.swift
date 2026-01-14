import ComposableArchitecture
import Foundation

struct UserDefaultsClient: Sendable {
    var bool: @Sendable (String) -> Bool
    var setBool: @Sendable (Bool, String) -> Void
    var string: @Sendable (String) -> String?
    var setString: @Sendable (String, String) -> Void
    var double: @Sendable (String) -> Double
    var setDouble: @Sendable (Double, String) -> Void
    var object: @Sendable (String) -> Any?
    var setObject: @Sendable (Any?, String) -> Void

    nonisolated init(
        bool: @escaping @Sendable (String) -> Bool,
        setBool: @escaping @Sendable (Bool, String) -> Void,
        string: @escaping @Sendable (String) -> String?,
        setString: @escaping @Sendable (String, String) -> Void,
        double: @escaping @Sendable (String) -> Double,
        setDouble: @escaping @Sendable (Double, String) -> Void,
        object: @escaping @Sendable (String) -> Any?,
        setObject: @escaping @Sendable (Any?, String) -> Void,
    ) {
        self.bool = bool
        self.setBool = setBool
        self.string = string
        self.setString = setString
        self.double = double
        self.setDouble = setDouble
        self.object = object
        self.setObject = setObject
    }
}

extension UserDefaultsClient: DependencyKey {
    nonisolated static var liveValue: UserDefaultsClient {
        nonisolated(unsafe) let userDefaults = UserDefaults.standard
        return UserDefaultsClient(
            bool: { key in
                userDefaults.bool(forKey: key)
            },
            setBool: { value, key in
                userDefaults.set(value, forKey: key)
            },
            string: { key in
                userDefaults.string(forKey: key)
            },
            setString: { value, key in
                userDefaults.set(value, forKey: key)
            },
            double: { key in
                userDefaults.double(forKey: key)
            },
            setDouble: { value, key in
                userDefaults.set(value, forKey: key)
            },
            object: { key in
                userDefaults.object(forKey: key)
            },
            setObject: { value, key in
                userDefaults.set(value, forKey: key)
            },
        )
    }

    nonisolated static var testValue: UserDefaultsClient {
        nonisolated(unsafe) var storage: [String: Any] = [:]
        nonisolated(unsafe) let lock = NSLock()
        return UserDefaultsClient(
            bool: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key] as? Bool ?? false
            },
            setBool: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
            string: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key] as? String
            },
            setString: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
            double: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key] as? Double ?? 0.0
            },
            setDouble: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
            object: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key]
            },
            setObject: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
        )
    }

    nonisolated static var previewValue: UserDefaultsClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}
