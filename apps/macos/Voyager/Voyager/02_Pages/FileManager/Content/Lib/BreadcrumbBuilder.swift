import Foundation

import VoyagerEntitiesEntry

enum BreadcrumbBuilder {
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

    static func selectedBreadcrumbItem(
        selectedEntry: EntryModel?,
        currentPath: String,
        iconSystemName: (EntryModel) -> String,
    ) -> BreadcrumbItem? {
        guard let selectedEntry
        else { return nil }

        let selectedBreadcrumb = BreadcrumbItem(
            path: selectedEntry.fullPath,
            name: selectedEntry.name,
            iconSystemName: iconSystemName(selectedEntry),
        )

        if selectedBreadcrumb.fullPath == currentPath {
            return nil
        }

        return selectedBreadcrumb
    }

    static func breadcrumbPaths(
        navigationState: ContentPageNavigationRoute,
        roots: FileManagerBreadcrumbRoots,
    ) -> [String] {
        guard case let .folder(path) = navigationState else {
            return []
        }

        if let rootPath = roots.specialRootPath(for: path) {
            return buildBreadcrumbPaths(from: rootPath, to: path)
        }
        return buildBreadcrumbPathsForStandardPath(path)
    }
}
