import Foundation
import GRDB
import Logging

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

        // DatabasePool 생성 (단일 writer + 다중 reader)
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

        pool = try DatabasePool(path: dbURL.path, configuration: configuration)

        // 마이그레이션 실행
        try await migrate()
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

    /// 데이터베이스 연결 해제
    func shutdown() {
        pool = nil
    }

    /// 데이터베이스 파일 URL 반환
    /// Application Support/Voyager 디렉토리에 저장
    private static func defaultDatabaseURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else {
            throw DatabaseError.applicationSupportNotFound
        }

        let voyagerDir = appSupport.appendingPathComponent("Voyager")
        return voyagerDir.appendingPathComponent("Entries.db")
    }

    private func ensureDirectoryExists(for databaseURL: URL) throws {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
    }

    /// 마이그레이션 실행
    private func migrate() async throws {
        guard let pool else {
            throw DatabaseError.notInitialized
        }

        var migrator = DatabaseMigrator()
        let logger = self.logger

        registerEntriesTableMigration(into: &migrator)
        registerEntriesIndexesMigration(into: &migrator)

        let legacyEntries = try await pool.read { db in
            let hasMigrations = try db.tableExists("grdb_migrations")
            guard !hasMigrations else { return false }
            return try db.tableExists("entries")
        }
        if legacyEntries {
            logger.info("Legacy entries DB detected without migrations; applying baseline migrations")
        }

        try migrator.migrate(pool)
    }

    private func registerEntriesTableMigration(into migrator: inout DatabaseMigrator) {
        // V1: entries 테이블 생성
        migrator.registerMigration("v1_create_entries") { db in
            if try db.tableExists("entries") {
                try Self.validateExistingEntriesTable(db)
                return
            }

            try Self.createEntriesTable(db)
        }
    }

    private func registerEntriesIndexesMigration(into migrator: inout DatabaseMigrator) {
        // V2: 검색/정렬 인덱스 추가
        migrator.registerMigration("v2_add_entries_indexes") { db in
            guard try db.tableExists("entries") else {
                throw DatabaseError.migrationFailed("entries table missing before index migration")
            }

            try Self.createMissingEntriesIndexes(db)
        }
    }

    private static let entriesRequiredColumns = [
        "id",
        "volume_identifier",
        "file_resource_identifier",
        "path",
        "dir_path",
        "name_full",
        "name_stem",
        "extension",
        "parent_dir_name",
        "depth_from_home",
        "relative_path_from_home",
        "size",
        "uniform_type_identifier",
        "file_kind",
        "is_invisible",
        "creation_date",
        "modification_date",
        "content_creation_date",
        "content_modification_date",
        "added_date",
        "last_used_date",
        "original_metadata",
    ]

    private struct IndexSpec {
        let name: String
        let columns: [String]
    }

    private static let entriesIndexSpecs = [
        IndexSpec(name: "idx_entries_path", columns: ["path"]),
        IndexSpec(name: "idx_entries_dir_path", columns: ["dir_path"]),
        IndexSpec(name: "idx_entries_name_full", columns: ["name_full"]),
        IndexSpec(name: "idx_entries_name_stem", columns: ["name_stem"]),
        IndexSpec(name: "idx_entries_extension", columns: ["extension"]),
        IndexSpec(name: "idx_entries_parent_dir_name", columns: ["parent_dir_name"]),
        IndexSpec(
            name: "idx_entries_uniform_type_identifier",
            columns: ["uniform_type_identifier"]
        ),
        IndexSpec(name: "idx_entries_file_kind", columns: ["file_kind"]),
        IndexSpec(name: "idx_entries_is_invisible", columns: ["is_invisible"]),
        IndexSpec(name: "idx_entries_modification_date", columns: ["modification_date"]),
        IndexSpec(name: "idx_entries_creation_date", columns: ["creation_date"]),
        IndexSpec(name: "idx_entries_added_date", columns: ["added_date"]),
    ]

    private static func validateExistingEntriesTable(_ db: Database) throws {
        let existingColumns = Set(try db.columns(in: "entries").map(\.name))
        let missing = entriesRequiredColumns.filter { !existingColumns.contains($0) }
        if !missing.isEmpty {
            throw DatabaseError.migrationFailed(
                "Legacy entries table missing columns: \(missing.joined(separator: \", \"))"
            )
        }
    }

    private static func createEntriesTable(_ db: Database) throws {
        try db.create(table: "entries") { table in
            // Primary Key
            table.autoIncrementedPrimaryKey("id")

            // 논리 키 (유니크 제약)
            table.column("volume_identifier", .text).notNull()
            table.column("file_resource_identifier", .text).notNull()
            table.uniqueKey(["volume_identifier", "file_resource_identifier"])

            // 경로 정보
            table.column("path", .text).notNull()
            table.column("dir_path", .text).notNull()
            table.column("name_full", .text).notNull()
            table.column("name_stem", .text).notNull()
            table.column("extension", .text).notNull()
            table.column("parent_dir_name", .text).notNull()
            table.column("depth_from_home", .integer).notNull()
            table.column("relative_path_from_home", .text)

            // 파일 속성
            table.column("size", .integer)
            table.column("uniform_type_identifier", .text)
            table.column("file_kind", .text)
            table.column("is_invisible", .boolean).notNull().defaults(to: false)

            // 시간 필드 (Spotlight 메타데이터)
            table.column("creation_date", .datetime)
            table.column("modification_date", .datetime)
            table.column("content_creation_date", .datetime)
            table.column("content_modification_date", .datetime)
            table.column("added_date", .datetime)
            table.column("last_used_date", .datetime)

            // JSON 컬럼
            table.column("original_metadata", .text) // JSON TEXT
        }
    }

    private static func createMissingEntriesIndexes(_ db: Database) throws {
        let existingIndexes = Set(try db.indexes(on: "entries").map(\.name))
        for spec in entriesIndexSpecs where !existingIndexes.contains(spec.name) {
            try db.create(index: spec.name, on: "entries", columns: spec.columns)
        }
    }

    enum DatabaseError: Error, Equatable {
        case notInitialized
        case applicationSupportNotFound
        case migrationFailed(String)
    }
}
