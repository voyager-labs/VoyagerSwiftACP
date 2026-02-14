import ComposableArchitecture
import Foundation
import SwiftUI

@MainActor
struct ContentPaneBreadcrumbBarView: View {
    let store: StoreOf<FileManagerContentFeature>
    let onNavigate: (String) -> Void

    private var statusText: String {
        let total = store.entries.displayItems.count
        let selected = store.entries.selectedIds.count

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

            HStack(spacing: 0) {
                let breadcrumbItems = BreadcrumbBuilder.breadcrumbItems(
                    navigationState: store.navigation.navigationState,
                    selectedPath: selectedPath,
                    computerName: computerName,
                    homePath: homePath,
                    trashPath: trashPath,
                    displayName: { path in FileManager.default.displayName(atPath: path) },
                )
                let selectedBreadcrumbItem = BreadcrumbBuilder.selectedBreadcrumbItem(
                    selectedPath: selectedPath,
                    selectedName: selectedName,
                    currentPath: store.navigation.currentPath,
                )

                if !breadcrumbItems.isEmpty || selectedBreadcrumbItem != nil {
                    PathBreadcrumbView(
                        breadcrumbItems: breadcrumbItems,
                        selectedItem: selectedBreadcrumbItem,
                        availableWidth: leftWidth,
                        onNavigate: { path in onNavigate(path) },
                        onOpenInNewWindow: { path in
                            store.send(.openPathInNewWindow(path))
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

    private var computerName: String {
        FileManager.default.displayName(atPath: "/")
    }

    private var homePath: String {
        NSHomeDirectory()
    }

    private var trashPath: String? {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
    }

    private var selectedEntry: Entry? {
        guard store.entries.selectedIds.count == 1,
              let selectedId = store.entries.selectedIds.first
        else {
            return nil
        }
        return store.entries.displayItems[id: selectedId]
    }

    private var selectedPath: String? {
        selectedEntry?.fullPath
    }

    private var selectedName: String? {
        selectedEntry?.name
    }
}
