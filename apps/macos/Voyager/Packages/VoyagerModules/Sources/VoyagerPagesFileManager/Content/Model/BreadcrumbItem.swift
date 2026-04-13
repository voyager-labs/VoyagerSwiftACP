public struct BreadcrumbItem: Equatable {
    public let iconSystemName: String
    public let name: String
    public let fullPath: String

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.iconSystemName == rhs.iconSystemName && lhs.name == rhs.name && lhs.fullPath == rhs.fullPath
    }

    public init(path: String, name: String, iconSystemName: String) {
        self.iconSystemName = iconSystemName
        fullPath = path
        self.name = name
    }
}
