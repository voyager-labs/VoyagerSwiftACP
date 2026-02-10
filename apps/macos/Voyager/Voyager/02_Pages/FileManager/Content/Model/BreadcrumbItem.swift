import AppKit

struct BreadcrumbItem: Equatable {
    let name: String
    let fullPath: String
    let icon: NSImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.fullPath == rhs.fullPath
    }

    init(path: String, name: String, icon: NSImage) {
        fullPath = path
        self.name = name
        self.icon = icon
    }
}
