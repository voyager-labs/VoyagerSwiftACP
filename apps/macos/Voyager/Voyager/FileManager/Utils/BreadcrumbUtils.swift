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

        init(path: String, name: String, icon: NSImage) {
            fullPath = path
            self.name = name
            self.icon = icon
        }

        init(entry: Entry) {
            fullPath = entry.fullPath
            name = entry.name
            icon = EntryIconUtils.icon(for: entry)
        }
    }

    static func findSpecialRootPath(
        for path: String,
        isTrashFolder: Bool,
        trashPath: String?,
        iCloudDrivePath: String,
        cloudStoragePath: String,
    ) -> String? {
        if isTrashFolder, let trashPath {
            return trashPath
        }
        if path.hasPrefix(iCloudDrivePath) {
            return iCloudDrivePath
        }
        if path.hasPrefix(cloudStoragePath + "/") {
            let relativePath = path.replacingOccurrences(of: cloudStoragePath + "/", with: "")
            if let firstSlashIndex = relativePath.firstIndex(of: "/") {
                return (cloudStoragePath as NSString)
                    .appendingPathComponent(String(relativePath[..<firstSlashIndex]))
            }
            return path
        }
        return nil
    }

    static func buildBreadcrumbPaths(from root: String, to target: String) -> [String] {
        var result = [root]
        if target != root {
            let relativePath = target.replacingOccurrences(of: root + "/", with: "")
            var accumulated = root
            for component in relativePath.split(separator: "/") {
                accumulated += "/" + component
                result.append(accumulated)
            }
        }
        return result
    }

    static func buildBreadcrumbPathsForStandardPath(_ path: String) -> [String] {
        var result: [String] = []
        if path.hasPrefix("/") {
            result.append("/")
        }
        var accumulated = "/"
        for component in path.split(separator: "/") {
            accumulated += String(component)
            result.append(accumulated)
            accumulated += "/"
        }
        return result
    }
}
