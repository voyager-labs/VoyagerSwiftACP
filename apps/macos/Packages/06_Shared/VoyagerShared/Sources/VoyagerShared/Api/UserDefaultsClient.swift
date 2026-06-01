import ComposableArchitecture
import Foundation

public struct UserDefaultsClient: Sendable {
    public var bool: @Sendable (String) -> Bool
    public var setBool: @Sendable (Bool, String) -> Void
    public var string: @Sendable (String) -> String?
    public var setString: @Sendable (String, String) -> Void
    public var double: @Sendable (String) -> Double
    public var setDouble: @Sendable (Double, String) -> Void
    public var object: @Sendable (String) -> Any?
    public var setObject: @Sendable (Any?, String) -> Void

    nonisolated public init(
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
    nonisolated public static var liveValue: UserDefaultsClient {
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

    nonisolated public static var testValue: UserDefaultsClient {
        nonisolated(unsafe) var storage: [String: Any] = [:]
        let lock = NSLock()
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

    nonisolated public static var previewValue: UserDefaultsClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}
