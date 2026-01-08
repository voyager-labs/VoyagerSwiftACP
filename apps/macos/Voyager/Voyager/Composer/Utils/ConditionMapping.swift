import Foundation

/// UI 라벨을 백엔드에서 기대하는 key/operator 코드로 매핑하는 유틸.
/// 프론트에서 선택한 라벨을 그대로 넘기지 말고 이 매핑을 통해 정규화해 사용한다.
enum ConditionMapping {
    enum Category: String {
        case system = "System Metadata"
        case content = "Content"
        case image = "Image"
        case video = "Video"
        case audio = "Audio"
        case document = "Document"
        case download = "Download"
        case location = "Location"
    }

    struct PropertyInfo {
        let key: String
        let label: String
        let category: Category
    }

    /// 프로퍼티 라벨 -> propertyKey (search_api_spec + file_entries 컬럼 기반)
    private static let propertyLabelToKey: [String: String] = [
        // System Metadata (filesystem)
        "File size": "size",
        "File type": "contentType",
        "File kind": "kind",
        "File name": "name",
        "Extension": "extension",
        "Invisible": "isInvisible",
        "Date created": "createdAt",
        "Date modified": "modifiedAt",
        "Date added": "addedAt",
        "Last used": "lastUsedAt",

        // Content
        "Content created": "contentCreatedAt",
        "Content modified": "contentModifiedAt",

        // Image
        "Pixel height": "pixelHeight",
        "Pixel width": "pixelWidth",
        "Color space": "colorSpace",
        "Has alpha channel": "hasAlphaChannel",

        // Video/Audio
        "Duration (sec)": "duration",
        "Video bitrate": "videoBitRate",
        "Audio bitrate": "audioBitRate",
        "Audio sample rate": "audioSampleRate",
        "Audio channels": "audioChannelCount",

        // Document
        "Title": "title",
        "Page count": "numberOfPages",
        "Creator": "creator",

        // Location
        "Latitude": "latitude",
        "Longitude": "longitude",
    ]

    /// propertyKey -> 카테고리
    private static let propertyKeyToCategory: [String: Category] = [
        // System Metadata
        "size": .system,
        "contentType": .system,
        "kind": .system,
        "name": .system,
        "extension": .system,
        "isInvisible": .system,
        "createdAt": .system,
        "modifiedAt": .system,
        "addedAt": .system,
        "lastUsedAt": .system,

        // Content
        "contentCreatedAt": .content,
        "contentModifiedAt": .content,

        // Image
        "pixelHeight": .image,
        "pixelWidth": .image,
        "colorSpace": .image,
        "hasAlphaChannel": .image,

        // Video
        "duration": .video,
        "videoBitRate": .video,

        // Audio
        "audioBitRate": .audio,
        "audioSampleRate": .audio,
        "audioChannelCount": .audio,

        // Document
        "title": .document,
        "numberOfPages": .document,
        "creator": .document,

        // Location
        "latitude": .location,
        "longitude": .location,
    ]

    /// 오퍼레이터 라벨 -> operator 코드
    private static let operatorLabelToCode: [String: String] = [
        "Is": "eq",
        "Is not": "neq",
        "Is greater than": "gt",
        "Is greater or equal": "gte",
        "Is less than": "lt",
        "Is less or equal": "lte",
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
