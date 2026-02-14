import StructuredQueries

extension QueryFragment {
    static var alwaysTrue: QueryFragment { "1=1" }
    static var alwaysFalse: QueryFragment { "1=0" }

    static func group(_ fragment: QueryFragment) -> QueryFragment {
        "(\(fragment))"
    }

    static func not(_ fragment: QueryFragment) -> QueryFragment {
        "NOT (\(fragment))"
    }

    static func compare(_ lhs: QueryFragment, op: String, rhs: QueryFragment) -> QueryFragment {
        "\(lhs) \(raw: op) \(rhs)"
    }

    static func eq(_ lhs: QueryFragment, _ rhs: QueryFragment) -> QueryFragment {
        compare(lhs, op: "=", rhs: rhs)
    }

    static func eq(_ lhs: QueryFragment, _ rhs: QueryBinding) -> QueryFragment {
        compare(lhs, op: "=", rhs: bind(rhs))
    }

    static func like(_ lhs: QueryFragment, _ rhs: QueryBinding) -> QueryFragment {
        compare(lhs, op: "LIKE", rhs: bind(rhs))
    }

    static func notLike(_ lhs: QueryFragment, _ rhs: QueryBinding) -> QueryFragment {
        compare(lhs, op: "NOT LIKE", rhs: bind(rhs))
    }

    static func between(
        _ lhs: QueryFragment,
        op: String,
        start: QueryFragment,
        end: QueryFragment,
    ) -> QueryFragment {
        "\(lhs) \(raw: op) \(start) AND \(end)"
    }

    static func isNull(_ lhs: QueryFragment) -> QueryFragment {
        "\(lhs) IS NULL"
    }

    static func isNotNull(_ lhs: QueryFragment) -> QueryFragment {
        "\(lhs) IS NOT NULL"
    }

    static func inList(_ lhs: QueryFragment, _ values: QueryFragment) -> QueryFragment {
        "\(lhs) IN (\(values))"
    }

    static func notInList(_ lhs: QueryFragment, _ values: QueryFragment) -> QueryFragment {
        "\(lhs) NOT IN (\(values))"
    }

    static func jsonExtract(_ field: QueryFragment, _ path: QueryBinding) -> QueryFragment {
        "json_extract(\(field), \(path))"
    }

    static func jsonType(_ field: QueryFragment, _ path: QueryBinding) -> QueryFragment {
        "json_type(\(field), \(path))"
    }

    static func jsonArrayLength(_ field: QueryFragment, _ path: QueryBinding) -> QueryFragment {
        "json_array_length(\(field), \(path))"
    }

    static func jsonEach(_ field: QueryFragment, _ path: QueryBinding) -> QueryFragment {
        "json_each(\(field), \(path))"
    }

    static func cast(_ expr: QueryFragment, as type: String) -> QueryFragment {
        "CAST(\(expr) AS \(raw: type))"
    }

    static func date(_ expr: QueryFragment) -> QueryFragment {
        "DATE(\(expr))"
    }

    static func exists(_ subquery: QueryFragment) -> QueryFragment {
        "EXISTS (\(subquery))"
    }

    static func jsonEachExists(
        field: QueryFragment,
        path: QueryBinding,
        values: QueryFragment,
    ) -> QueryFragment {
        "EXISTS (SELECT 1 FROM \(jsonEach(field, path)) WHERE value IN (\(values)))"
    }

    static func jsonEachCountDistinctEquals(
        field: QueryFragment,
        path: QueryBinding,
        values: QueryFragment,
        count: QueryFragment,
    ) -> QueryFragment {
        "(SELECT COUNT(DISTINCT value) FROM \(jsonEach(field, path)) WHERE value IN (\(values))) = \(count)"
    }

    static func bind(_ binding: QueryBinding) -> QueryFragment {
        QueryFragment("\(binding)")
    }

    static func joinWithComma(_ fragments: [QueryFragment]) -> QueryFragment {
        fragments.joined(separator: ", ")
    }
}

extension [QueryFragment] {
    func joinedWithAnd() -> QueryFragment {
        joined(separator: " AND ")
    }

    func joinedWithOr() -> QueryFragment {
        joined(separator: " OR ")
    }
}
