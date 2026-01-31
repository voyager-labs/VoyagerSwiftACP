import AppKit
import ComposableArchitecture
import Foundation

// MARK: - 브레드크럼

extension ContentPaneView {
    // swiftlint:disable function_body_length
    func breadcrumbItems(for state: FileManagerFeature.State) -> [BreadcrumbUtils.Item] {
        switch state.navigationState {
        case .recents, .tags:
            return []
        case .computer:
            if state.entries.selectedIds.count == 1,
               let selectedItem = state.entries.displayItems.first(where: { $0.id == state.entries.selectedIds.first }),
               selectedItem.fullPath == "/"
            {
                return []
            }
            let computerName = navigationClient.computerName()
            return [
                BreadcrumbUtils.Item(
                    path: computerName,
                    name: computerName,
                    icon: NSImage(named: "NSComputer") ?? workspaceClient.iconForFile("/"),
                ),
            ]
        case let .folder(path):
            let trashPath = entryClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path
            let homePath = entryClient.homeDirectory()
            let iCloudDrivePath = (homePath as NSString)
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            let cloudStoragePath = (homePath as NSString)
                .appendingPathComponent("Library/CloudStorage")

            let isTrashFolder: Bool = if let trashPath {
                path == trashPath || path.hasPrefix(trashPath + "/")
            } else {
                false
            }

            let paths: [String] = if let rootPath = BreadcrumbUtils.findSpecialRootPath(
                for: path,
                isTrashFolder: isTrashFolder,
                trashPath: trashPath,
                iCloudDrivePath: iCloudDrivePath,
                cloudStoragePath: cloudStoragePath,
            ) {
                BreadcrumbUtils.buildBreadcrumbPaths(from: rootPath, to: path)
            } else {
                BreadcrumbUtils.buildBreadcrumbPathsForStandardPath(path)
            }

            let computerName = navigationClient.computerName()
            return paths.map { breadcrumbPath in
                let name: String
                let icon: NSImage

                if breadcrumbPath == computerName {
                    name = computerName
                    icon = NSImage(named: "NSComputer") ?? workspaceClient.iconForFile("/")
                } else {
                    name = entryClient.displayName(breadcrumbPath)
                    if let trashPath = entryClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path,
                       breadcrumbPath == trashPath
                    {
                        icon = NSImage(named: NSImage.trashFullName) ?? workspaceClient.iconForFile(breadcrumbPath)
                    } else {
                        icon = workspaceClient.iconForFile(breadcrumbPath)
                    }
                }

                return BreadcrumbUtils.Item(path: breadcrumbPath, name: name, icon: icon)
            }
        case .collection:
            return []
        }
    }

    func selectedBreadcrumbItem(for state: FileManagerFeature.State) -> BreadcrumbUtils.Item? {
        guard state.entries.selectedIds.count == 1,
              let selectedItem = state.entries.displayItems.first(where: { $0.id == state.entries.selectedIds.first })
        else { return nil }

        let selectedBreadcrumb = BreadcrumbUtils.Item(entry: selectedItem, workspaceClient: workspaceClient)

        if selectedBreadcrumb.fullPath == state.currentPath {
            return nil
        }

        return selectedBreadcrumb
    }
    // swiftlint:enable function_body_length
}
