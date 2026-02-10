import ComposableArchitecture
import SwiftUI

@MainActor
struct ContentPaneBreadcrumbBarView: View {
    let store: StoreOf<FileManagerContentFeature>
    let onNavigate: (String) -> Void

    @Dependency(\.entryClient)
    private var entryClient
    @Dependency(\.workspaceClient)
    private var workspaceClient
    @Dependency(\.fileManagerNavigationClient)
    private var navigationClient

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
                    for: store.state,
                    computerName: navigationClient.computerName(),
                    homePath: entryClient.homeDirectory(),
                    trashPath: entryClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path,
                    entryClient: entryClient,
                    workspaceClient: workspaceClient,
                )
                let selectedBreadcrumbItem = BreadcrumbBuilder.selectedBreadcrumbItem(
                    for: store.state,
                    workspaceClient: workspaceClient,
                )

                if !breadcrumbItems.isEmpty || selectedBreadcrumbItem != nil {
                    PathBreadcrumbView(
                        breadcrumbItems: breadcrumbItems,
                        selectedItem: selectedBreadcrumbItem,
                        availableWidth: leftWidth,
                        onNavigate: { path in onNavigate(path) },
                        onOpenInNewWindow: { path in
                            Task {
                                await MainActor.run {
                                    _ = FileManagerWindowSessionCoordinator.shared.createNewWindow(path: path)
                                }
                            }
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
}
