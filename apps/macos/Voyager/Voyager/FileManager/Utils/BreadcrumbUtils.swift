import AppKit
import Foundation

enum BreadcrumbUtils {
    struct Item: Equatable {
        let name: String
        let fullPath: String
        let icon: NSImage

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name && lhs.fullPath == rhs.fullPath
        }

        init(path: String) {
            fullPath = path
            name = FileManager.default.displayName(atPath: path)

            if let trashPath = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path,
               path == trashPath
            {
                icon = NSImage(named: NSImage.trashFullName) ?? NSWorkspace.shared.icon(forFile: path)
            } else {
                icon = NSWorkspace.shared.icon(forFile: path)
            }
        }

        init(fsItem: FSItem) {
            fullPath = fsItem.fullPath
            name = fsItem.name
            icon = FSItemIconUtils.icon(for: fsItem)
        }
    }
}
