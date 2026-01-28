import Foundation
@preconcurrency import GRDB
import Logging

struct FilterSearchService: Sendable {
    private let manager: DatabaseManager
    private let logger: Logger
    private let scopeBuilder: FilterSearchScopeBuilder
    private let conditionBuilder: FilterSearchConditionBuilder

    init(
        manager: DatabaseManager,
        logger: Logger = Logger(label: "VoyagerHelper.FilterSearchService"),
        bundle: Bundle = .main,
    ) throws {
        self.manager = manager
        self.logger = logger
        scopeBuilder = FilterSearchScopeBuilder()
        conditionBuilder = try FilterSearchConditionBuilder(bundle: bundle)
    }

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        let (scopeClause, scopeArgs) = scopeBuilder.buildScopeClause(scopes: filters.scopes)
        let (conditionClause, conditionArgs) = try conditionBuilder.buildWhere(conditions: filters.conditions)
        let whereClause = "\(scopeClause) AND \(conditionClause)"
        let arguments = StatementArguments(mergeArguments(scopeArgs, conditionArgs))

        let items = try await manager.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    id,
                    path,
                    name_full,
                    size,
                    extension,
                    file_kind,
                    modification_date
                FROM entries
                WHERE \(whereClause)
                """,
                arguments: arguments,
            )
            return rows.map { row in
                let modificationDate = row["modification_date"] as? Date
                return JSONValue.object([
                    "id": .number(Double(row["id"] as? Int64 ?? 0)),
                    "path": .string(row["path"] as? String ?? ""),
                    "name": .string(row["name_full"] as? String ?? ""),
                    "size": .number(Double(row["size"] as? Int64 ?? 0)),
                    "extension": .string(row["extension"] as? String ?? ""),
                    "fileKind": .string(row["file_kind"] as? String ?? ""),
                    "modificationDate": modificationDate.map { .string(Self.formatDate($0)) } ?? .null,
                ])
            }
        }

        return SearchResponsePayload(
            itemCount: items.count,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                conditions: filters.conditions,
            ),
            items: items,
        )
    }

    private func mergeArguments(
        _ first: [String: DatabaseValueConvertible?],
        _ second: [String: DatabaseValueConvertible?],
    ) -> [String: DatabaseValueConvertible?] {
        var merged = first
        for (key, value) in second {
            merged[key] = value
        }
        return merged
    }

    private nonisolated static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
