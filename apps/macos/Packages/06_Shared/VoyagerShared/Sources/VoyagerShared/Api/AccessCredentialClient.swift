import ComposableArchitecture
import Foundation
import Security

// MARK: - Error

public enum AccessCredentialError: Error, Equatable, Sendable {
    case saveFailed(service: String)
    case loadFailed(service: String)
    case deleteFailed(service: String)
    case notFound
}

// MARK: - Client

public struct AccessCredentialClient: Sendable {
    public var saveAccessToken: @Sendable (String) throws -> Void
    public var loadAccessToken: @Sendable () throws -> String?
    public var deleteAccessToken: @Sendable () throws -> Void
    public var saveRefreshToken: @Sendable (String) throws -> Void
    public var loadRefreshToken: @Sendable () throws -> String?
    public var deleteRefreshToken: @Sendable () throws -> Void

    nonisolated public init(
        saveAccessToken: @escaping @Sendable (String) throws -> Void,
        loadAccessToken: @escaping @Sendable () throws -> String?,
        deleteAccessToken: @escaping @Sendable () throws -> Void,
        saveRefreshToken: @escaping @Sendable (String) throws -> Void,
        loadRefreshToken: @escaping @Sendable () throws -> String?,
        deleteRefreshToken: @escaping @Sendable () throws -> Void,
    ) {
        self.saveAccessToken = saveAccessToken
        self.loadAccessToken = loadAccessToken
        self.deleteAccessToken = deleteAccessToken
        self.saveRefreshToken = saveRefreshToken
        self.loadRefreshToken = loadRefreshToken
        self.deleteRefreshToken = deleteRefreshToken
    }
}

// MARK: - Keychain Helpers

extension AccessCredentialClient {
    private static let accessTokenService = "com.voyager.access.accessToken"
    private static let refreshTokenService = "com.voyager.access.refreshToken"
    private static let account = "voyager"

    private static func keychainSave(service: String, data: String) throws {
        guard let data = data.data(using: .utf8) else {
            throw AccessCredentialError.saveFailed(service: service)
        }

        // 삭제 후 추가 (upsert)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccessCredentialError.saveFailed(service: service)
        }
    }

    private static func keychainLoad(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccessCredentialError.loadFailed(service: service)
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccessCredentialError.deleteFailed(service: service)
        }
    }
}

// MARK: - DependencyKey

extension AccessCredentialClient: DependencyKey {
    nonisolated public static var liveValue: AccessCredentialClient {
        AccessCredentialClient(
            saveAccessToken: { token in
                try keychainSave(service: accessTokenService, data: token)
            },
            loadAccessToken: {
                try keychainLoad(service: accessTokenService)
            },
            deleteAccessToken: {
                try keychainDelete(service: accessTokenService)
            },
            saveRefreshToken: { token in
                try keychainSave(service: refreshTokenService, data: token)
            },
            loadRefreshToken: {
                try keychainLoad(service: refreshTokenService)
            },
            deleteRefreshToken: {
                try keychainDelete(service: refreshTokenService)
            },
        )
    }

    nonisolated public static var testValue: AccessCredentialClient {
        nonisolated(unsafe) var storage: [String: String] = [:]
        let lock = NSLock()
        return AccessCredentialClient(
            saveAccessToken: { token in
                lock.lock()
                defer { lock.unlock() }
                storage["accessToken"] = token
            },
            loadAccessToken: {
                lock.lock()
                defer { lock.unlock() }
                return storage["accessToken"]
            },
            deleteAccessToken: {
                lock.lock()
                defer { lock.unlock() }
                storage.removeValue(forKey: "accessToken")
            },
            saveRefreshToken: { token in
                lock.lock()
                defer { lock.unlock() }
                storage["refreshToken"] = token
            },
            loadRefreshToken: {
                lock.lock()
                defer { lock.unlock() }
                return storage["refreshToken"]
            },
            deleteRefreshToken: {
                lock.lock()
                defer { lock.unlock() }
                storage.removeValue(forKey: "refreshToken")
            },
        )
    }

    nonisolated public static var previewValue: AccessCredentialClient {
        testValue
    }
}

// MARK: - DependencyValues

public extension DependencyValues {
    nonisolated var accessCredentialClient: AccessCredentialClient {
        get { self[AccessCredentialClient.self] }
        set { self[AccessCredentialClient.self] = newValue }
    }
}
