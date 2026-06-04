struct BreadcrumbItem: Equatable {
    let iconSystemName: String
    let name: String
    let fullPath: String

    init(path: String, name: String, iconSystemName: String) {
        self.iconSystemName = iconSystemName
        fullPath = path
        self.name = name
    }
}
