import Foundation
import GRDB

nonisolated enum IndexingStateSchema {
    static let tableName = "indexing_state"

    static let requiredColumns = [
        "id",
        "key",
        "value",
        "updated_at",
    ]

    static func createTable(_ db: Database) throws {
        try db.create(table: tableName) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("key", .text).notNull()
            table.column("value", .text).notNull()
            table.column("updated_at", .datetime).notNull()
            table.uniqueKey(["key"])
        }
    }
}
