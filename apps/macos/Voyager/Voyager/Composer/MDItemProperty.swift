import Foundation

/// 백엔드 `/api/mditem/properties` 응답을 매핑하는 모델.
struct MDItemProperty: Decodable, Equatable, Identifiable {
    let key: String
    let label: String
    let category: String
    let type: String
    let isDefault: Bool
    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case category
        case type
        case isDefault = "is_default"
    }
}
