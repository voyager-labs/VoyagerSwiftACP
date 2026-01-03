import Foundation

enum PropertyType {
    case string
    case number
    case datetime
    case boolean
    case array
}

enum ValueUIKind {
    case none // 값 없이 사용 (empty/not_empty)
    case singleText // 단일 텍스트
    case singleNumber // 단일 숫자
    case singleDate // 단일 날짜/시간
    case rangeNumber // 숫자 범위 (min,max)
    case rangeDate // 날짜 범위 (from,to)
    case listText // 문자열 목록
    case listNumber // 숫자 목록
    case toggle // 불린 토글
}

struct OperatorUIOption {
    let code: String // 백엔드 operator 코드
    let label: String // UI 표시 라벨
    let valueUI: ValueUIKind
}

enum ConditionOperatorMapping {
    private static let propertyKeyToType: [String: PropertyType] = [
        // 숫자
        "size": .number,

        // 날짜/시간
        "createdAt": .datetime,
        "modifiedAt": .datetime,
        "addedAt": .datetime,
        "lastUsedAt": .datetime,
        "contentCreatedAt": .datetime,
        "contentModifiedAt": .datetime,

        // 불린
        "isInvisible": .boolean,

        // 문자열 기본
        "name": .string,
        "extension": .string,
        "fileKind": .string,
        "contentType": .string,
        "contentTypeTree": .string,
        "parentDirName": .string,
        "relativePathFromHome": .string,
    ]

    /// 타입별 허용 오퍼레이터 세트
    private static func operators(for type: PropertyType) -> [OperatorUIOption] {
        switch type {
        case .string:
            [
                .init(code: "eq", label: "Is", valueUI: .singleText),
                .init(code: "neq", label: "Is not", valueUI: .singleText),
                .init(code: "contains", label: "Contains", valueUI: .singleText),
                .init(code: "in", label: "In list", valueUI: .listText),
                .init(code: "empty", label: "Is empty", valueUI: .none),
                .init(code: "not_empty", label: "Is not empty", valueUI: .none),
            ]
        case .number:
            [
                .init(code: "eq", label: "Is", valueUI: .singleNumber),
                .init(code: "neq", label: "Is not", valueUI: .singleNumber),
                .init(code: "gt", label: "Greater than", valueUI: .singleNumber),
                .init(code: "gte", label: "Greater or equal", valueUI: .singleNumber),
                .init(code: "lt", label: "Less than", valueUI: .singleNumber),
                .init(code: "lte", label: "Less or equal", valueUI: .singleNumber),
                .init(code: "between", label: "Is between", valueUI: .rangeNumber),
            ]
        case .datetime:
            [
                .init(code: "eq", label: "Is", valueUI: .singleDate),
                .init(code: "neq", label: "Is not", valueUI: .singleDate),
                .init(code: "gt", label: "After", valueUI: .singleDate),
                .init(code: "gte", label: "On or after", valueUI: .singleDate),
                .init(code: "lt", label: "Before", valueUI: .singleDate),
                .init(code: "lte", label: "On or before", valueUI: .singleDate),
                .init(code: "between", label: "Is between", valueUI: .rangeDate),
            ]
        case .boolean:
            [
                .init(code: "eq", label: "Is", valueUI: .toggle),
                .init(code: "neq", label: "Is not", valueUI: .toggle),
            ]
        case .array:
            [
                .init(code: "contains", label: "Contains", valueUI: .listText),
                .init(code: "in", label: "In list", valueUI: .listText),
                .init(code: "empty", label: "Is empty", valueUI: .none),
                .init(code: "not_empty", label: "Is not empty", valueUI: .none),
            ]
        }
    }

    /// propertyKey로 타입을 찾고 허용 오퍼레이터 목록을 반환
    static func operatorOptions(for propertyKey: String) -> [OperatorUIOption] {
        let type = propertyKeyToType[propertyKey] ?? .string
        return operators(for: type)
    }

    /// propertyKey에 대응하는 타입을 노출 (외부에서 모델 생성 시 사용).
    static func propertyType(for propertyKey: String) -> PropertyType? {
        propertyKeyToType[propertyKey]
    }

    /// operator 코드와 타입 조합으로 값 UI 힌트를 반환
    static func valueUI(for operatorCode: String, propertyKey: String) -> ValueUIKind {
        let type = propertyKeyToType[propertyKey] ?? .string
        return operators(for: type).first { $0.code == operatorCode }?.valueUI ?? .singleText
    }
}
