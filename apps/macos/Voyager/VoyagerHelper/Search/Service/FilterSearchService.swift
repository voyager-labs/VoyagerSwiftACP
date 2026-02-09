import Foundation
@preconcurrency import GRDB
import Logging
import StructuredQueries

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
        let scopePredicate = scopeBuilder.buildScopePredicate(scopes: filters.scopes)
        let conditionPredicate = try conditionBuilder.buildWhere(conditions: filters.conditions)
        let whereClause = FilterSearchEntryTable.where { _ in
            let predicates: [QueryFragment] = [scopePredicate, conditionPredicate]
            return predicates
        }
        let select = whereClause.select {
            (
                $0.id,
                $0.path,
                $0.nameFull,
                $0.size,
                $0.fileExtension,
                $0.fileKind,
                $0.modificationDate,
            )
        }
        let prepared = select.query.prepare { _ in "?" }
        let arguments = StatementArguments(prepared.bindings.map(\.databaseValue))

        let items = try await manager.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: prepared.sql,
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
            error: nil,
        )
    }

    private nonisolated static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension QueryBinding {
    var databaseValue: DatabaseValueConvertible? {
        switch self {
        case let .blob(blob):
            Data(blob)
        case let .bool(value):
            value
        case let .double(value):
            value
        case let .date(value):
            value
        case let .int(value):
            value
        case .null:
            nil
        case let .text(value):
            value
        case let .uint(value):
            Int64(value)
        case let .uuid(value):
            value.uuidString.lowercased()
        case let .invalid(error):
            error.underlyingError.localizedDescription
        }
    }
}
