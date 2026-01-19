import Foundation
import GRDB
import Logging

/// Helper 앱의 GRDB 데이터베이스 관리자
/// DatabasePool을 사용하여 단일 writer + 다중 reader 모드로 동작
actor DatabaseManager {
    static let shared = DatabaseManager()

    private var pool: DatabasePool?
    private let logger: Logger
    private let databaseURLProvider: () throws -> URL

    init(
        databaseURLProvider: @escaping () throws -> URL = DatabaseManager.defaultDatabaseURL,
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
        configuration.prepareDatabase { [self] db in
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

    /// 데이터베이스 풀 반환
    /// - Returns: 초기화된 DatabasePool
    /// - Throws: 데이터베이스가 초기화되지 않은 경우 에러
    func getPool() throws -> DatabasePool {
        guard let pool else {
            throw DatabaseError.notInitialized
        }
        return pool
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

        registerEntriesTableMigration(into: &migrator)
        registerEntriesIndexesMigration(into: &migrator)

        try migrator.migrate(pool)
    }

    private func registerEntriesTableMigration(into migrator: inout DatabaseMigrator) {
        // V1: entries 테이블 생성
        migrator.registerMigration("v1_create_entries") { db in
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
    }

    private func registerEntriesIndexesMigration(into migrator: inout DatabaseMigrator) {
        // V2: 검색/정렬 인덱스 추가
        migrator.registerMigration("v2_add_entries_indexes") { db in
            try db.create(index: "idx_entries_path", on: "entries", columns: ["path"])
            try db.create(index: "idx_entries_dir_path", on: "entries", columns: ["dir_path"])
            try db.create(index: "idx_entries_name_full", on: "entries", columns: ["name_full"])
            try db.create(index: "idx_entries_name_stem", on: "entries", columns: ["name_stem"])
            try db.create(index: "idx_entries_extension", on: "entries", columns: ["extension"])
            try db.create(
                index: "idx_entries_parent_dir_name",
                on: "entries",
                columns: ["parent_dir_name"]
            )
            try db.create(
                index: "idx_entries_uniform_type_identifier",
                on: "entries",
                columns: ["uniform_type_identifier"]
            )
            try db.create(index: "idx_entries_file_kind", on: "entries", columns: ["file_kind"])
            try db.create(index: "idx_entries_is_invisible", on: "entries", columns: ["is_invisible"])
            try db.create(
                index: "idx_entries_modification_date",
                on: "entries",
                columns: ["modification_date"]
            )
            try db.create(
                index: "idx_entries_creation_date",
                on: "entries",
                columns: ["creation_date"]
            )
            try db.create(index: "idx_entries_added_date", on: "entries", columns: ["added_date"])
        }
    }

    enum DatabaseError: Error, Equatable {
        case notInitialized
        case applicationSupportNotFound
        case migrationFailed(String)
    }
}
