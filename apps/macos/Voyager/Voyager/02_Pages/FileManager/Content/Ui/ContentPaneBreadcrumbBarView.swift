import ComposableArchitecture
import Foundation
import SwiftUI

import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared

@MainActor
struct ContentPaneBreadcrumbBarView: View {
    let store: StoreOf<FileManagerContentFeature>
    let chromeProps: FileManagerContentChromeProps
    let onNavigate: (String) -> Void

    private func displayName(for path: String) -> String {
        if path == "/" {
            return chromeProps.computerName.isEmpty ? "Computer" : chromeProps.computerName
        }

        if let cached = chromeProps.pathDisplayNames[path], !cached.isEmpty {
            return cached
        }

        let fallback = URL(fileURLWithPath: path).lastPathComponent
        return fallback.isEmpty ? path : fallback
    }

    private func iconSystemName(forDirectoryPath path: String) -> String {
        if path == "/" {
            return "internaldrive"
        }
        if path == chromeProps.breadcrumbRoots.homePath {
            return "house"
        }
        if path.hasPrefix("/Volumes/") {
            return "externaldrive"
        }
        if let mapped = chromeProps.specialDirectoryIconNames[path] {
            return mapped
        }
        return "folder"
    }

    private func iconSystemName(for entry: EntryModel) -> String {
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return "rectangle.stack"
        }
        return entry.isFolder ? "folder" : "doc"
    }

    private var statusText: String {
        let total = store.entryViewLayout.displayItems.count
        let selected = store.entryViewLayout.selectedIds.count

        if selected == 0 {
            return "\(total) items"
        } else {
            return "\(selected) of \(total) selected"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = max(proxy.size.width - 32, 0)
            let leftWidth = max(totalWidth * 0.5, 0)
            let breadcrumbItems = resolvedBreadcrumbItems()

            HStack(spacing: 0) {
                let selectedBreadcrumbItem = BreadcrumbBuilder.selectedBreadcrumbItem(
                    selectedEntry: selectedEntry,
                    currentPath: store.navigation.currentPath,
                    iconSystemName: { entry in iconSystemName(for: entry) },
                )

                if !breadcrumbItems.isEmpty || selectedBreadcrumbItem != nil {
                    PathBreadcrumbView(
                        breadcrumbItems: breadcrumbItems,
                        selectedItem: selectedBreadcrumbItem,
                        availableWidth: leftWidth,
                        onNavigate: { path in onNavigate(path) },
                        onOpenInNewWindow: { path in
                            store.send(.delegate(.openPathInNewWindow(path)))
                        },
                    )
                    .frame(width: leftWidth, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: leftWidth)
                }

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 20)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .frame(height: 24)
    }

    private func resolvedBreadcrumbItems() -> [BreadcrumbItem] {
        switch store.navigation.navigationState {
        case .recents, .tags, .collection:
            return []
        case .computer:
            guard store.navigation.currentPath != "/" else {
                return []
            }
            return [
                BreadcrumbItem(
                    path: "/",
                    name: chromeProps.computerName,
                    iconSystemName: iconSystemName(forDirectoryPath: "/"),
                ),
            ]
        case .folder:
            let paths = BreadcrumbBuilder.breadcrumbPaths(
                navigationState: store.navigation.navigationState,
                roots: chromeProps.breadcrumbRoots,
            )
            return paths.map { path in
                BreadcrumbItem(
                    path: path,
                    name: displayName(for: path),
                    iconSystemName: iconSystemName(forDirectoryPath: path),
                )
            }
        }
    }

    private var selectedEntry: EntryModel? {
        guard store.entryViewLayout.selectedIds.count == 1,
              let selectedId = store.entryViewLayout.selectedIds.first
        else {
            return nil
        }
        return store.entryViewLayout.displayItems[id: selectedId]
    }
}
