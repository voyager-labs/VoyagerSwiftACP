/// Go 생성 카탈로그(property_condition_catalog_gen.go)의 42개 relation과 shared
/// fixture inventory를 미러링하는 Swift 측 정본 relation table이다. decoder는 이
/// table로 capability가 definition value contract와 정확히 일치하는지 검증한다.
/// drift는 public contract flow 테스트가 fixture relation과 대조해 검출한다.
enum PropertyConditionRelation {
    static let nativeTypes: [PropertyConditionNativeType] = [
        .string,
        .number,
        .date,
        .boolean,
        .stringList,
        .categorical,
    ]

    private static let operatorIDsByNativeType: [PropertyConditionNativeType: [String]] = [
        .string: ["all", "any", "cn", "empty", "eq", "ew", "exists", "nc", "neq", "rx", "sw"],
        .number: ["btw", "eq", "exists", "gt", "gte", "lt", "lte", "nbtw", "neq"],
        .date: ["btw", "eq", "exists", "gt", "gte", "lt", "lte", "nbtw", "neq", "today"],
        .boolean: ["eq", "exists"],
        .stringList: ["all", "any", "empty", "exists", "miss", "none"],
        .categorical: ["any", "empty", "exists", "none"],
    ]

    /// native type의 전체 정렬 operator 집합을 반환한다. table과 operator enum이
    /// 어긋나면 빈 집합을 반환해 caller가 capability를 fail-closed로 거절한다.
    static func operators(for nativeType: PropertyConditionNativeType) -> [PropertyConditionOperator] {
        guard let ids = operatorIDsByNativeType[nativeType] else { return [] }
        var operators: [PropertyConditionOperator] = []
        for id in ids {
            guard let operation = try? PropertyConditionOperator(rawValue: id) else { return [] }
            operators.append(operation)
        }
        return operators.sorted()
    }

    /// 불변 value contract(Workspace value_type과 cardinality)를 condition-side
    /// native type으로 유도한다. 평가 불가능한 계약은 nil을 반환하고 caller는
    /// supported capability를 거절한다(Go domain derivation과 동일한 매핑).
    static func nativeType(
        for valueType: PropertyValueType,
        cardinality: PropertyCardinality,
    ) -> PropertyConditionNativeType? {
        if cardinality == .many {
            switch valueType {
            case .text: return .stringList
            case .select: return .categorical
            default: return nil
            }
        }
        switch valueType {
        case .text: return .string
        case .number: return .number
        case .date: return .date
        case .boolean: return .boolean
        case .select: return .categorical
        case .datetime: return nil
        }
    }
}
