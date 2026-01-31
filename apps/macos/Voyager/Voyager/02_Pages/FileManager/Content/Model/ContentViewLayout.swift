enum ContentViewLayout: String, Equatable, Codable {
    case list
    case grid

    static func from(_ rawValue: String?) -> ContentViewLayout? {
        rawValue.flatMap(Self.init(rawValue:))
    }
}
