import Foundation

let kSqlKindDefaultOperators: [String: String] = [
    "comparison": "=",
    "range": "BETWEEN",
    "like_prefix": "LIKE",
    "like_suffix": "LIKE",
    "like_pattern": "LIKE",
]

let kSqlKindValueShapes: [String: Set<ValueShape>] = [
    "comparison": [.single],
    "like_prefix": [.single],
    "like_suffix": [.single],
    "like_pattern": [.single],
    "range": [.range],
    "exists": [.none],
    "empty": [.none],
    "string_list_any": [.list],
    "string_list_all": [.list],
    "string_list_not_any": [.list],
    "string_list_not_all": [.list],
]
