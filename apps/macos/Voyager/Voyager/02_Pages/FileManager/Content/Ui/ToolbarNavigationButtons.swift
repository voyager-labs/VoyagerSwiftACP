import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

struct ToolbarNavigationButtons: View {
    let onNavigationAction: (ContentPageNavigationAction) -> Void
    let backHistory: [ContentPageNavigationHistorySnapshot]
    let forwardHistory: [ContentPageNavigationHistorySnapshot]
    let canGoBack: Bool
    let canGoForward: Bool
    let canGoToEnclosingDirectory: Bool

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
            font: IconButtonStyle.toolbar.font,
            menuID: backHistory.count,
            primaryAction: { onNavigationAction(.goBack) },
            menuContent: {
                if backHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(backHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: {
                                onNavigationAction(.goToHistoryIndex(index, isBackHistory: true))
                            },
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
            font: IconButtonStyle.toolbar.font,
            menuID: forwardHistory.count,
            primaryAction: { onNavigationAction(.goForward) },
            menuContent: {
                if forwardHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(forwardHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: {
                                onNavigationAction(.goToHistoryIndex(index, isBackHistory: false))
                            },
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
            action: { onNavigationAction(.goToEnclosingDirectory) },
            label: {
                ToolbarHoverButtonLabel(
                    systemName: "chevron.up",
                    isEnabled: canGoToEnclosingDirectory,
                    font: IconButtonStyle.toolbar.font,
                )
            },
        )
        .fixedSize()
        .disabled(!canGoToEnclosingDirectory)
        .buttonStyle(.borderless)
    }

    private func historyDisplayName(for entry: ContentPageNavigationHistorySnapshot) -> String {
        switch entry.navigationState {
        case let .folder(path):
            FileManager.default.displayName(atPath: path)
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            FileManager.default.displayName(atPath: "/")
        case let .collection(navigation):
            switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
        }
    }

    private func historyMenuLabel(for entry: ContentPageNavigationHistorySnapshot) -> some View {
        HStack(spacing: 6) {
            if let icon = historyIcon(for: entry) {
                Image(nsImage: resizedHistoryIcon(from: icon))
                    .frame(width: 10, height: 10)
            }
            Text(historyDisplayName(for: entry))
        }
    }

    private func historyIcon(for entry: ContentPageNavigationHistorySnapshot) -> NSImage? {
        switch entry.navigationState {
        case let .folder(path):
            return NSWorkspace.shared.icon(forFile: path)
        case let .collection(navigation):
            if case let .file(url, _) = navigation.kind {
                return NSWorkspace.shared.icon(forFile: url.path)
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
