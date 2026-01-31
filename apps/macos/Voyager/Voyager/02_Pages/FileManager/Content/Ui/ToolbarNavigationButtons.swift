import AppKit
import ComposableArchitecture
import SwiftUI

struct ToolbarNavigationButtons: View {
    let store: StoreOf<FileManagerFeature>
    let backHistory: [FileManagerFeature.HistoryEntry]
    let forwardHistory: [FileManagerFeature.HistoryEntry]
    let canGoBack: Bool
    let canGoForward: Bool
    let canGoToEnclosingDirectory: Bool

    @Dependency(\.fileManagerNavigationClient)
    private var navigationClient
    @Dependency(\.entryClient)
    private var entryClient
    @Dependency(\.workspaceClient)
    private var workspaceClient

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
            isEnabled: canGoBack,
            font: ToolbarButtonLabel.Metrics.iconFont,
            menuID: backHistory.count,
            primaryAction: { store.send(.goBack) },
            menuContent: {
                if backHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(backHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: { store.send(.goToHistoryIndex(index, isBackHistory: true)) },
                            label: { historyMenuLabel(for: entry) },
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
            font: ToolbarButtonLabel.Metrics.iconFont,
            menuID: forwardHistory.count,
            primaryAction: { store.send(.goForward) },
            menuContent: {
                if forwardHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(forwardHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: { store.send(.goToHistoryIndex(index, isBackHistory: false)) },
                            label: { historyMenuLabel(for: entry) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func enclosingDirectoryButton() -> some View {
        Button(
            action: { store.send(.goToEnclosingDirectory) },
            label: {
                ToolbarHoverButtonLabel(
                    systemName: "chevron.up",
                    isEnabled: canGoToEnclosingDirectory,
                    font: ToolbarButtonLabel.Metrics.iconFont,
                )
            },
        )
        .fixedSize()
        .disabled(!canGoToEnclosingDirectory)
        .buttonStyle(.borderless)
    }

    private func historyDisplayName(for entry: FileManagerFeature.HistoryEntry) -> String {
        switch entry.navigationState {
        case let .folder(path):
            entryClient.displayName(path)
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            navigationClient.computerName()
        case let .collection(navigation):
            switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
        }
    }

    private func historyMenuLabel(for entry: FileManagerFeature.HistoryEntry) -> some View {
        HStack(spacing: 6) {
            if let icon = historyIcon(for: entry) {
                Image(nsImage: resizedHistoryIcon(from: icon))
                    .frame(width: 10, height: 10)
            }
            Text(historyDisplayName(for: entry))
        }
    }

    private func historyIcon(for entry: FileManagerFeature.HistoryEntry) -> NSImage? {
        switch entry.navigationState {
        case let .folder(path):
            return workspaceClient.iconForFile(path)
        case let .collection(navigation):
            if case let .file(url, _) = navigation.kind {
                return workspaceClient.iconForFile(url.path)
            }
            return nil
        case .recents:
            return NSImage(
                systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil,
            )
        case .tags:
            return NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        case .computer:
            return NSImage(
                systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil,
            )
        }
    }

    private func resizedHistoryIcon(from icon: NSImage) -> NSImage {
        let size: CGFloat = 10
        let targetSize = NSSize(width: size, height: size)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: targetSize))
        resized.unlockFocus()
        resized.isTemplate = icon.isTemplate
        return resized
    }
}
