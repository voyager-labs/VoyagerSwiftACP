import Foundation

/// UI 라벨을 백엔드에서 기대하는 key/operator 코드로 매핑하는 유틸.
/// 프론트에서 선택한 라벨을 그대로 넘기지 말고 이 매핑을 통해 정규화해 사용한다.
enum ConditionMapping {
    enum Category: String {
        case fileInfo = "Custom Metadata" // 파일 이름/타입/크기 등 사용자 친화 메타
        case system = "System Metadata" // 시스템 속성/숨김 여부
        case video = "Video"
        case audio = "Audio"
        case dateTime = "Date/Time"
        case other = "Other"
    }

    struct PropertyInfo {
        let key: String
        let label: String
        let category: Category
    }

    /// 프로퍼티 라벨 -> propertyKey (search_api_spec + file_entries 컬럼 기반)
    private static let propertyLabelToKey: [String: String] = [
        // 기본/파일
        "File Name": "name",
        "File Type": "extension",
        "File Size": "size",
        "File Kind": "fileKind",
        "Content Type": "contentType",
        "Content Type Tree": "contentTypeTree",
        "Parent Folder": "parentDirName",
        "Relative Path": "relativePathFromHome",

        // 날짜
        "Date Created": "createdAt",
        "Date Modified": "modifiedAt",
        "Date Added": "addedAt",
        "Last Used": "lastUsedAt",
        "Content Created": "contentCreatedAt",
        "Content Modified": "contentModifiedAt",
    ]

    /// propertyKey -> 카테고리
    private static let propertyKeyToCategory: [String: Category] = [
        // Custom Metadata (파일 기본/사용자 친화)
        "name": .fileInfo,
        "extension": .fileInfo,
        "size": .fileInfo,
        "fileKind": .fileInfo,
        "contentType": .fileInfo,
        "contentTypeTree": .fileInfo,
        "parentDirName": .fileInfo,
        "relativePathFromHome": .fileInfo,

        // System Metadata
        "isInvisible": .system,

        // Date/Time
        "createdAt": .dateTime,
        "modifiedAt": .dateTime,
        "addedAt": .dateTime,
        "lastUsedAt": .dateTime,
        "contentCreatedAt": .dateTime,
        "contentModifiedAt": .dateTime,

        // Video (추가 확장 시 사용)
        "durationSeconds": .video,
        "videoBitRate": .video,
        "totalBitRate": .video,
        "pixelWidth": .video,
        "pixelHeight": .video,

        // Audio (추가 확장 시 사용)
        "audioBitRate": .audio,
        "audioChannelCount": .audio,
    ]

    /// 오퍼레이터 라벨 -> operator 코드
    private static let operatorLabelToCode: [String: String] = [
        "Is": "eq",
        "Is not": "neq",
        "Greater than": "gt",
        "Greater or equal": "gte",
        "Less than": "lt",
        "Less or equal": "lte",
        "Is between": "between",
        "Contains": "contains",
        "In list": "in",
        "Is empty": "empty",
        "Is not empty": "not_empty",
    ]

    /// 라벨을 키로 변환. 없는 경우 nil.
    static func propertyKey(for label: String) -> String? {
        propertyLabelToKey[label]
    }

    /// 백엔드 키를 라벨로 변환. 매핑에 없으면 캐멀/스네이크를 Title Case로 변환한 기본 라벨을 돌려준다.
    static func defaultLabel(forKey key: String) -> String {
        if let found = propertyLabelToKey.first(where: { $0.value == key })?.key {
            return found
        }
        // fallback: camelCase/snake_case -> Title Case
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.capitalized
    }

    static func operatorCode(for label: String) -> String? {
        operatorLabelToCode[label]
    }

    /// 매핑에 정의된 모든 프로퍼티 정보를 반환한다.
    static var allProperties: [PropertyInfo] {
        propertyKeyToCategory.map { key, category in
            let label = propertyLabelToKey.first(where: { $0.value == key })?.key
                ?? defaultLabel(forKey: key)
            return PropertyInfo(key: key, label: label, category: category)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
