struct BreadcrumbItem: Equatable {
    let name: String
    let fullPath: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.fullPath == rhs.fullPath
    }

    init(path: String, name: String) {
        fullPath = path
        self.name = name
    }
}
