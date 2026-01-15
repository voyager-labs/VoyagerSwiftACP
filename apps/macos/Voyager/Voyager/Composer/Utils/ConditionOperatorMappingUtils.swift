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

enum ConditionOperatorMappingUtils {
    private static let propertyKeyToType: [String: PropertyType] = [
        // 숫자
        "size": .number,
        "pixelHeight": .number,
        "pixelWidth": .number,
        "duration": .number,
        "videoBitRate": .number,
        "audioBitRate": .number,
        "audioSampleRate": .number,
        "audioChannelCount": .number,
        "numberOfPages": .number,
        "latitude": .number,
        "longitude": .number,

        // 날짜/시간
        "createdAt": .datetime,
        "modifiedAt": .datetime,
        "addedAt": .datetime,
        "lastUsedAt": .datetime,
        "contentCreatedAt": .datetime,
        "contentModifiedAt": .datetime,

        // 불린
        "isInvisible": .boolean,
        "hasAlphaChannel": .boolean,

        // 문자열
        "name": .string,
        "extension": .string,
        "kind": .string,
        "contentType": .string,
        "colorSpace": .string,
        "title": .string,
        "creator": .string,
    ]

    private static let propertyKeyToSupported: [String: [String]] = [
        "size": ["eq", "gt", "gte", "lt", "lte", "between"],
        "contentType": ["eq", "contains", "in"],
        "kind": ["eq", "contains"],
        "name": ["eq", "contains"],
        "extension": ["eq", "in"],
        "isInvisible": ["eq"],
        "createdAt": ["eq", "gt", "gte", "lt", "lte", "between"],
        "modifiedAt": ["eq", "gt", "gte", "lt", "lte", "between"],
        "addedAt": ["eq", "gt", "gte", "lt", "lte", "between"],
        "lastUsedAt": ["eq", "gt", "gte", "lt", "lte", "between"],
        "contentCreatedAt": ["eq", "gt", "gte", "lt", "lte", "between"],
        "contentModifiedAt": ["eq", "gt", "gte", "lt", "lte", "between"],
        "pixelHeight": ["eq", "gt", "gte", "lt", "lte", "between"],
        "pixelWidth": ["eq", "gt", "gte", "lt", "lte", "between"],
        "colorSpace": ["eq", "in"],
        "hasAlphaChannel": ["eq"],
        "duration": ["eq", "gt", "gte", "lt", "lte", "between"],
        "videoBitRate": ["eq", "gt", "gte", "lt", "lte"],
        "audioBitRate": ["eq", "gt", "gte", "lt", "lte"],
        "audioSampleRate": ["eq", "gt", "gte", "lt", "lte"],
        "audioChannelCount": ["eq", "in"],
        "title": ["eq", "contains"],
        "numberOfPages": ["eq", "gt", "gte", "lt", "lte", "between"],
        "creator": ["eq", "contains"],
        "latitude": ["eq", "gt", "gte", "lt", "lte", "between"],
        "longitude": ["eq", "gt", "gte", "lt", "lte", "between"],
    ]

    /// 타입별 오퍼레이터 템플릿
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
                .init(code: "gt", label: "Is greater than", valueUI: .singleNumber),
                .init(code: "gte", label: "Is greater or equal", valueUI: .singleNumber),
                .init(code: "lt", label: "Is less than", valueUI: .singleNumber),
                .init(code: "lte", label: "Is less or equal", valueUI: .singleNumber),
                .init(code: "between", label: "Is between", valueUI: .rangeNumber),
            ]
        case .datetime:
            [
                .init(code: "eq", label: "Is", valueUI: .singleDate),
                .init(code: "neq", label: "Is not", valueUI: .singleDate),
                .init(code: "gt", label: "Is after", valueUI: .singleDate),
                .init(code: "gte", label: "Is on or after", valueUI: .singleDate),
                .init(code: "lt", label: "Is before", valueUI: .singleDate),
                .init(code: "lte", label: "Is on or before", valueUI: .singleDate),
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
        let supported = propertyKeyToSupported[propertyKey]
        let options = operators(for: type)
        if let supported {
            return options.filter { supported.contains($0.code) }
        }
        return options
    }

    /// propertyKey에 대응하는 타입을 노출 (외부에서 모델 생성 시 사용).
    static func propertyType(for propertyKey: String) -> PropertyType? {
        propertyKeyToType[propertyKey]
    }

    /// propertyKey에 대응하는 타입 문자열을 반환 (UI 모델용).
    static func propertyTypeString(for propertyKey: String) -> String {
        guard let type = propertyKeyToType[propertyKey] else {
            return "string"
        }

        switch type {
        case .string:
            return "string"
        case .number:
            return "number"
        case .datetime:
            return "datetime"
        case .boolean:
            return "boolean"
        case .array:
            return "array"
        }
    }

    /// operator 코드와 타입 조합으로 값 UI 힌트를 반환
    static func valueUI(for operatorCode: String, propertyKey: String) -> ValueUIKind {
        let type = propertyKeyToType[propertyKey] ?? .string
        return operators(for: type).first { $0.code == operatorCode }?.valueUI ?? .singleText
    }
}
