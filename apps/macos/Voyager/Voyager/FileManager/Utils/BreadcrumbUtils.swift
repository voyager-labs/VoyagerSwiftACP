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
            if path == SidebarUtils.computerName {
                name = path
                icon = NSImage(named: "NSComputer") ?? NSWorkspace.shared.icon(forFile: "/")
            } else {
                name = FileManager.default.displayName(atPath: path)
                if let trashPath = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path,
                   path == trashPath
                {
                    icon = NSImage(named: NSImage.trashFullName) ?? NSWorkspace.shared.icon(forFile: path)
                } else {
                    icon = NSWorkspace.shared.icon(forFile: path)
                }
            }
        }

        init(fsItem: FSItem) {
            fullPath = fsItem.fullPath
            name = fsItem.name
            icon = FSItemIconUtils.icon(for: fsItem)
        }
    }

    static func findSpecialRootPath(for path: String, isTrashFolder: Bool) -> String? {
        if isTrashFolder,
           let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
        {
            return trashURL.path
        }
        if path.hasPrefix(SidebarUtils.iCloudDrivePath) {
            return SidebarUtils.iCloudDrivePath
        }
        if path.hasPrefix(SidebarUtils.cloudStoragePath + "/") {
            let relativePath = path.replacingOccurrences(of: SidebarUtils.cloudStoragePath + "/", with: "")
            if let firstSlashIndex = relativePath.firstIndex(of: "/") {
                return (SidebarUtils.cloudStoragePath as NSString)
                    .appendingPathComponent(String(relativePath[..<firstSlashIndex]))
            }
            return path
        }
        return nil
    }

    static func buildBreadcrumbs(from root: String, to target: String) -> [Item] {
        var result = [Item(path: root)]
        if target != root {
            let relativePath = target.replacingOccurrences(of: root + "/", with: "")
            var accumulated = root
            for component in relativePath.split(separator: "/") {
                accumulated += "/" + component
                result.append(Item(path: accumulated))
            }
        }
        return result
    }

    static func buildBreadcrumbsForStandardPath(_ path: String) -> [Item] {
        var result: [Item] = []
        if path.hasPrefix("/") {
            result.append(Item(path: "/"))
        }
        var accumulated = "/"
        for component in path.split(separator: "/") {
            accumulated += component
            result.append(Item(path: accumulated))
            accumulated += "/"
        }
        return result
    }
}
