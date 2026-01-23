import Darwin
import Foundation
import GRDB
import Logging
import SwiftDotenv

/// Helper 앱의 GRDB 데이터베이스 관리자
/// DatabasePool을 사용하여 단일 writer + 다중 reader 모드로 동작
actor DatabaseManager {
    static let shared = DatabaseManager()

    private var pool: DatabasePool?
    private let logger: Logger
    private let databaseURLProvider: @Sendable () throws -> URL

    init(
        databaseURLProvider: @Sendable @escaping () throws -> URL = DatabaseManager.defaultDatabaseURL,
        logger: Logger = Logger(label: "VoyagerHelper.Database")
    ) {
        self.databaseURLProvider = databaseURLProvider
        self.logger = logger
    }

    /// 데이터베이스 초기화 및 마이그레이션 수행
    /// - Throws: 데이터베이스 초기화 실패 시 에러
    func initialize() async throws {
        guard pool == nil else { return }

        let dbURL = try databaseURLProvider()
        try ensureDirectoryExists(for: dbURL)

        do {
            try await withMigrationLock(for: dbURL) {
                let configuration = makeConfiguration()
                pool = try DatabasePool(path: dbURL.path, configuration: configuration)
                try await migrate(databaseURL: dbURL)
            }
        } catch {
            pool = nil
            throw error
        }
    }

    /// 데이터베이스 읽기 작업 실행
    func read<T>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        guard let pool else {
            throw DatabaseError.notInitialized
        }
        return try await pool.read(block)
    }

    /// 데이터베이스 쓰기 작업 실행
    func write<T>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        guard let pool else {
            throw DatabaseError.notInitialized
        }
        return try await pool.write(block)
    }

    /// 트랜잭션 없이 데이터베이스 쓰기 작업 실행
    func writeWithoutTransaction<T>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        guard let pool else {
            throw DatabaseError.notInitialized
        }
        return try await pool.writeWithoutTransaction(block)
    }

    /// 데이터베이스 연결 해제
    func shutdown() {
        pool = nil
    }

    /// 데이터베이스 파일 URL 반환
    private static func defaultDatabaseURL() throws -> URL {
        if let envURL = resolveDatabaseURLFromEnv() {
            return envURL
        }
        throw DatabaseError.missingDatabaseConfiguration
    }

    private static func resolveDatabaseURLFromEnv() -> URL? {
        guard let location = envValue(for: "PUBLIC_SQLITE_FILE_LOCATION"),
              let name = envValue(for: "PUBLIC_SQLITE_FILE_NAME")
        else {
            return nil
        }

        let expandedLocation = (location as NSString).expandingTildeInPath
        var baseURL = URL(fileURLWithPath: expandedLocation, isDirectory: true)
        if !expandedLocation.hasPrefix("/") {
            let cwd = FileManager.default.currentDirectoryPath
            baseURL = URL(fileURLWithPath: cwd, isDirectory: true)
                .appendingPathComponent(expandedLocation, isDirectory: true)
        }
        return baseURL.appendingPathComponent(name)
    }

    private static func envValue(for key: String) -> String? {
        if let value = Dotenv[key]?.stringValue, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        return nil
    }

    private func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        let logger = self.logger
        configuration.prepareDatabase { db in
            // PRAGMA 설정
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 5000") // 5초

            // JSON1 지원 확인
            if let result = try? Int64.fetchOne(db, sql: "SELECT json_extract('{\"a\":1}', '$.a')"),
               result == 1
            {
                // JSON1 지원 확인됨
            } else {
                logger.warning("JSON1 support check failed - may need alternative strategy")
            }
        }
        return configuration
    }

    private func ensureDirectoryExists(for databaseURL: URL) throws {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
    }

    private func migrationLockURL(for databaseURL: URL) -> URL {
        databaseURL.appendingPathExtension("migration.lock")
    }

    private func withMigrationLock<T>(
        for databaseURL: URL,
        _ block: () async throws -> T
    ) async throws -> T {
        let lockURL = migrationLockURL(for: databaseURL)
        let lockDescriptor = try acquireMigrationLock(at: lockURL)
        defer { releaseMigrationLock(lockDescriptor, at: lockURL) }
        return try await block()
    }

    private func acquireMigrationLock(at lockURL: URL) throws -> Int32 {
        let descriptor = open(lockURL.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor != -1 else {
            throw DatabaseError.migrationLockExists(lockURL.path)
        }

        let payload = "pid=\(getpid()) timestamp=\(iso8601Timestamp())\n"
        let data = Data(payload.utf8)
        _ = data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return Darwin.write(descriptor, baseAddress, buffer.count)
        }
        return descriptor
    }

    private func releaseMigrationLock(_ descriptor: Int32, at lockURL: URL) {
        _ = close(descriptor)
        try? FileManager.default.removeItem(at: lockURL)
    }

    private func backupDatabaseFile(databaseURL: URL, pool: DatabasePool) async throws -> URL {
        let timestamp = backupTimestamp()
        let backupURL = databaseURL.appendingPathExtension("bak.\(timestamp)")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try await pool.write { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [backupURL.path])
        }
        return backupURL
    }

    private func iso8601Timestamp() -> String {
        timestampString(format: "%Y-%m-%dT%H:%M:%SZ")
    }

    private func backupTimestamp() -> String {
        timestampString(format: "%Y%m%d%H%M%S")
    }

    private func timestampString(format: String) -> String {
        var now = time_t(Date().timeIntervalSince1970)
        var tmValue = tm()
        gmtime_r(&now, &tmValue)

        var buffer = [CChar](repeating: 0, count: 32)
        format.withCString { formatCString in
            _ = strftime(&buffer, buffer.count, formatCString, &tmValue)
        }
        if buffer[0] == 0 {
            return String(Int(Date().timeIntervalSince1970))
        }
        return String(cString: buffer)
    }

    /// 마이그레이션 실행
    private func migrate(databaseURL: URL) async throws {
        guard let pool else {
            throw DatabaseError.notInitialized
        }

        var migrator = DatabaseMigrator()
        let logger = self.logger

        try DatabaseMigrations.registerAll(into: &migrator)

        try await pool.read { db in
            try DatabaseMigrations.validateMigrationHistory(db)
        }

        let legacyEntries = try await pool.read { db in
            let hasMigrations = try db.tableExists("grdb_migrations")
            guard !hasMigrations else { return false }
            return try db.tableExists("entries")
        }
        if legacyEntries {
            logger.info("Legacy entries DB detected without migrations; applying baseline migrations")
            let backupURL = try await backupDatabaseFile(databaseURL: databaseURL, pool: pool)
            logger.info("Legacy entries DB backup created at: \(backupURL.path)")
        }

        try migrator.migrate(pool)
    }

    enum DatabaseError: Error, Equatable {
        case notInitialized
        case missingDatabaseConfiguration
        case migrationLockExists(String)
        case migrationFailed(String)
    }
}
