import AppKit
import Foundation
import UniformTypeIdentifiers

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

        init(entry: Entry, workspaceClient: WorkspaceClient) {
            fullPath = entry.fullPath
            name = entry.name

            // 아이콘 캐싱 키 생성
            let cacheKey: String = if entry.fullPath == "/" {
                "root:/"
            } else if entry.fileExtension.lowercased() == "voycoll" {
                "asset:\(EntryIconUtils.voycollIconName)"
            } else if entry.isDirectory {
                "dir:\(entry.fullPath)"
            } else {
                UTType(filenameExtension: entry.fileExtension)
                    .map { "type:\($0.identifier)" }
                    ?? "generic:file"
            }

            // 캐시 확인
            if let cached = EntryIconUtils.getCachedIcon(for: cacheKey) {
                icon = cached
            } else {
                // 아이콘 가져오기
                let fetchedIcon: NSImage = if entry.fullPath == "/" {
                    workspaceClient.iconForFile("/")
                } else if entry.fileExtension.lowercased() == "voycoll" {
                    if let voycollIcon = NSImage(named: EntryIconUtils.voycollIconName) {
                        voycollIcon
                    } else {
                        workspaceClient.iconForType(.data)
                    }
                } else if entry.isDirectory {
                    workspaceClient.iconForFile(entry.fullPath)
                } else {
                    if let utType = UTType(filenameExtension: entry.fileExtension) {
                        workspaceClient.iconForType(utType)
                    } else {
                        workspaceClient.iconForType(.data)
                    }
                }

                // 캐시 저장
                EntryIconUtils.setCachedIcon(fetchedIcon, for: cacheKey)
                icon = fetchedIcon
            }
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
