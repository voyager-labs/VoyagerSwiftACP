import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

struct ToolbarNavigationButtons: View {
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void
    let backHistoryItems: [ToolbarHistoryItem]
    let forwardHistoryItems: [ToolbarHistoryItem]
    let canGoBack: Bool
    let canGoForward: Bool
    let canGoToEnclosingDirectory: Bool
    let backPrimaryAction: () -> Void
    let backIsEnabled: Bool
    let enclosingDirectorySystemName: String
    let enclosingDirectoryHelp: String
    let enclosingDirectoryAction: () -> Void

    init(
        onNavigationAction: @escaping (ContentPageNavigationAction.View) -> Void,
        backHistoryItems: [ToolbarHistoryItem],
        forwardHistoryItems: [ToolbarHistoryItem],
        canGoBack: Bool,
        canGoForward: Bool,
        canGoToEnclosingDirectory: Bool,
        backPrimaryAction: (() -> Void)? = nil,
        backIsEnabled: Bool? = nil,
        enclosingDirectorySystemName: String = "chevron.up",
        enclosingDirectoryHelp: String = "Go to Enclosing Folder",
        enclosingDirectoryAction: (() -> Void)? = nil,
    ) {
        self.onNavigationAction = onNavigationAction
        self.backHistoryItems = backHistoryItems
        self.forwardHistoryItems = forwardHistoryItems
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.canGoToEnclosingDirectory = canGoToEnclosingDirectory
        self.backPrimaryAction = backPrimaryAction ?? { onNavigationAction(.goBack) }
        self.backIsEnabled = backIsEnabled ?? canGoBack
        self.enclosingDirectorySystemName = enclosingDirectorySystemName
        self.enclosingDirectoryHelp = enclosingDirectoryHelp
        self.enclosingDirectoryAction = enclosingDirectoryAction ?? { onNavigationAction(.goToEnclosingDirectory) }
    }

    var body: some View {
        HStack(spacing: 0) {
            backButton()
            forwardButton()
            enclosingDirectoryButton()
        }
    }

    private func backButton() -> some View {
        ToolbarMenuButton(
            systemName: "chevron.left",
            isEnabled: backIsEnabled,
            font: IconButtonStyle.toolbar.font,
            menuID: backHistoryItems.count,
            primaryAction: backPrimaryAction,
            menuContent: {
                if backHistoryItems.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(backHistoryItems.enumerated().reversed()), id: \.offset) { index, item in
                        Button(
                            action: {
                                onNavigationAction(.goToHistoryIndex(index, isBackHistory: true))
                            },
                            label: { historyMenuLabel(for: item) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func forwardButton() -> some View {
        ToolbarMenuButton(
            systemName: "chevron.right",
            isEnabled: canGoForward,
            font: IconButtonStyle.toolbar.font,
            menuID: forwardHistoryItems.count,
            primaryAction: { onNavigationAction(.goForward) },
            menuContent: {
                if forwardHistoryItems.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(forwardHistoryItems.enumerated().reversed()), id: \.offset) { index, item in
                        Button(
                            action: {
                                onNavigationAction(.goToHistoryIndex(index, isBackHistory: false))
                            },
                            label: { historyMenuLabel(for: item) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func enclosingDirectoryButton() -> some View {
        Button(
            action: enclosingDirectoryAction,
            label: {
                ToolbarHoverButtonLabel(
                    systemName: enclosingDirectorySystemName,
                    isEnabled: canGoToEnclosingDirectory,
                    font: IconButtonStyle.toolbar.font,
                )
            },
        )
        .fixedSize()
        .disabled(!canGoToEnclosingDirectory)
        .buttonStyle(.borderless)
        .help(enclosingDirectoryHelp)
        .accessibilityLabel(enclosingDirectoryHelp)
    }

    private func historyMenuLabel(for item: ToolbarHistoryItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.iconSystemName)
                .accessibilityHidden(true)
                .frame(width: 10, height: 10)
            Text(item.title)
        }
    }
}
