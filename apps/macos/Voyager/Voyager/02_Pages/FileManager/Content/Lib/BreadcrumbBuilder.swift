import AppKit
import Foundation
import UniformTypeIdentifiers

enum BreadcrumbBuilder {
    /// breadcrumb root가 특별 취급되는 경로(Trash/iCloud Drive/CloudStorage 등)를 해석하는 리졸버.
    /// 참고: 이 로직은 breadcrumb 도메인에 종속적이지 않아서, 커지면 별도 유틸/서비스로 분리하는 편이 낫다.
    private struct SpecialRootResolver {
        let trashPath: String?
        let iCloudDrivePath: String
        let cloudStoragePath: String

        init(homePath: String, trashPath: String?) {
            self.trashPath = trashPath
            iCloudDrivePath = (homePath as NSString)
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            cloudStoragePath = (homePath as NSString)
                .appendingPathComponent("Library/CloudStorage")
        }

        func specialRootPath(for path: String) -> String? {
            if let trashPath,
               path == trashPath || path.hasPrefix(trashPath + "/")
            {
                return trashPath
            }

            if path.hasPrefix(iCloudDrivePath) {
                return iCloudDrivePath
            }

            let cloudStoragePrefix = cloudStoragePath + "/"
            if path.hasPrefix(cloudStoragePrefix) {
                let relativePath = path.replacingOccurrences(of: cloudStoragePrefix, with: "")
                if let firstSlashIndex = relativePath.firstIndex(of: "/") {
                    return (cloudStoragePath as NSString)
                        .appendingPathComponent(String(relativePath[..<firstSlashIndex]))
                }
                return path
            }

            return nil
        }
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

    static func breadcrumbItems(
        for state: FileManagerContentFeature.State,
        computerName: String,
        homePath: String,
        trashPath: String?,
        entryClient: EntryClient,
        workspaceClient: WorkspaceClient,
    ) -> [BreadcrumbItem] {
        switch state.navigationState {
        case .recents, .tags, .collection:
            return []
        case .computer:
            if state.entries.selectedIds.count == 1,
               let selectedItem = state.entries.displayItems.first(where: { $0.id == state.entries.selectedIds.first }),
               selectedItem.fullPath == "/"
            {
                return []
            }
            return [
                BreadcrumbItem(
                    path: computerName,
                    name: computerName,
                    icon: NSImage(named: "NSComputer") ?? workspaceClient.iconForFile("/"),
                ),
            ]
        case let .folder(path):
            let resolver = SpecialRootResolver(homePath: homePath, trashPath: trashPath)
            let paths: [String] = if let rootPath = resolver.specialRootPath(for: path) {
                buildBreadcrumbPaths(from: rootPath, to: path)
            } else {
                buildBreadcrumbPathsForStandardPath(path)
            }

            return paths.map { breadcrumbPath in
                makeBreadcrumbItem(
                    path: breadcrumbPath,
                    computerName: computerName,
                    trashPath: trashPath,
                    entryClient: entryClient,
                    workspaceClient: workspaceClient,
                )
            }
        }
    }

    static func selectedBreadcrumbItem(
        for state: FileManagerContentFeature.State,
        workspaceClient: WorkspaceClient,
    ) -> BreadcrumbItem? {
        guard state.entries.selectedIds.count == 1,
              let selectedItem = state.entries.displayItems.first(where: { $0.id == state.entries.selectedIds.first })
        else { return nil }

        let selectedBreadcrumb = makeBreadcrumbItem(
            entry: selectedItem,
            workspaceClient: workspaceClient,
        )

        if selectedBreadcrumb.fullPath == state.currentPath {
            return nil
        }

        return selectedBreadcrumb
    }

    private static func makeBreadcrumbItem(
        path: String,
        computerName: String,
        trashPath: String?,
        entryClient: EntryClient,
        workspaceClient: WorkspaceClient,
    ) -> BreadcrumbItem {
        if path == computerName {
            return BreadcrumbItem(
                path: computerName,
                name: computerName,
                icon: NSImage(named: "NSComputer") ?? workspaceClient.iconForFile("/"),
            )
        }

        let name = entryClient.displayName(path)
        let icon: NSImage = if let trashPath,
                               path == trashPath
        {
            NSImage(named: NSImage.trashFullName) ?? workspaceClient.iconForFile(path)
        } else {
            workspaceClient.iconForFile(path)
        }

        return BreadcrumbItem(path: path, name: name, icon: icon)
    }

    private static func makeBreadcrumbItem(
        entry: Entry,
        workspaceClient: WorkspaceClient,
    ) -> BreadcrumbItem {
        let fullPath = entry.fullPath
        let name = entry.name

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
            return BreadcrumbItem(path: fullPath, name: name, icon: cached)
        }

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
        return BreadcrumbItem(path: fullPath, name: name, icon: fetchedIcon)
    }
}
