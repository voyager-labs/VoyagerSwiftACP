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
        let select = whereClause.select { $0.path }
        let prepared = select.query.prepare { _ in "?" }
        let arguments = StatementArguments(prepared.bindings.map(\.databaseValue))

        let items = try await manager.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: prepared.sql,
                arguments: arguments,
            )
            return rows.compactMap { row -> JSONValue? in
                let path: String = row["path"]
                guard path.isEmpty == false else {
                    return nil
                }
                return JSONValue.string(path)
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
