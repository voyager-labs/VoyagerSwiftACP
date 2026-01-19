import Foundation

/// 백엔드 시스템 프로퍼티 레지스트리 응답을 매핑하는 모델.
struct SystemProperty: Decodable, Equatable, Identifiable {
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
