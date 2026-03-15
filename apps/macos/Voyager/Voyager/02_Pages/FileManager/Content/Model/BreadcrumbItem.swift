struct BreadcrumbItem: Equatable {
    let iconSystemName: String
    let name: String
    let fullPath: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.iconSystemName == rhs.iconSystemName && lhs.name == rhs.name && lhs.fullPath == rhs.fullPath
    }

    init(path: String, name: String, iconSystemName: String) {
        self.iconSystemName = iconSystemName
        fullPath = path
        self.name = name
    }
}
