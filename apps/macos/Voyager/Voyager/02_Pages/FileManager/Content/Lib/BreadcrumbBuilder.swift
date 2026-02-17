import Foundation

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
        navigationState: ContentPageNavigationRoute,
        selectedPath: String?,
        computerName: String,
        homePath: String,
        trashPath: String?,
        displayName: (String) -> String,
    ) -> [BreadcrumbItem] {
        switch navigationState {
        case .recents, .tags, .collection:
            return []
        case .computer:
            if selectedPath == "/" {
                return []
            }
            return [
                BreadcrumbItem(
                    path: "/",
                    name: computerName,
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
                    displayName: displayName,
                )
            }
        }
    }

    static func selectedBreadcrumbItem(
        selectedPath: String?,
        selectedName: String?,
        currentPath: String,
    ) -> BreadcrumbItem? {
        guard let selectedPath,
              let selectedName
        else { return nil }

        let selectedBreadcrumb = BreadcrumbItem(path: selectedPath, name: selectedName)

        if selectedBreadcrumb.fullPath == currentPath {
            return nil
        }

        return selectedBreadcrumb
    }

    private static func makeBreadcrumbItem(
        path: String,
        displayName: (String) -> String,
    ) -> BreadcrumbItem {
        BreadcrumbItem(path: path, name: displayName(path))
    }
}
