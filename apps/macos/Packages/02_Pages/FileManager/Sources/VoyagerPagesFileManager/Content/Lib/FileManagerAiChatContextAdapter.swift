import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

enum FileManagerAiChatContextAdapter {
    static func makeAiChatSetupState(
        content state: FileManagerContentState,
        sessionID: AiChatSessionID? = nil,
    ) -> AiChatSetupState {
        AiChatSetupState(
            sessionID: sessionID,
            currentContext: makeCurrentContextSnapshot(content: state),
        )
    }

    static func makeCurrentContextSnapshot(content state: FileManagerContentState) -> AiChatCurrentContextSnapshot {
        let currentViewReference = makeCurrentViewReference(navigation: state.navigation)
        let selectedEntries = state.entryViewLayout.displayOrderItems
            .filter { state.entryViewLayout.selectedIds.contains($0.id) }

        return AiChatCurrentContextSnapshot(
            summary: makeSummary(
                currentViewTitle: currentViewReference.title ?? currentViewReference.identifier,
                selectedCount: selectedEntries.count,
            ),
            references: [currentViewReference],
            items: selectedEntries.map { makeContextItem(for: $0, currentViewReference: currentViewReference) },
            attachments: [],
        )
    }

    private static func makeCurrentViewReference(
        navigation: ContentPageNavigationState,
    ) -> AiChatContextReference {
        let title = currentViewTitle(for: navigation.navigationState)
        let identifier = currentViewIdentifier(for: navigation.navigationState)
        let subtitle = navigation.currentPath.isEmpty || navigation.currentPath == title ? nil : navigation.currentPath

        return AiChatContextReference(
            kind: .reference,
            identifier: identifier,
            title: title,
            subtitle: subtitle,
            metadata: currentViewMetadata(for: navigation.navigationState),
        )
    }

    private static func makeContextItem(
        for entry: EntryModel,
        currentViewReference: AiChatContextReference,
    ) -> AiChatContextItem {
        AiChatContextItem(
            kind: entry.isFolder ? .folder : .file,
            identifier: entry.fullPath,
            title: entry.name,
            subtitle: entry.fullPath,
            metadata: [
                "path": entry.fullPath,
                "kind": entry.isFolder ? "folder" : "file",
                "selected": "true",
            ],
            references: [currentViewReference],
        )
    }

    private static func makeSummary(currentViewTitle: String, selectedCount: Int) -> String {
        guard selectedCount > 0 else { return currentViewTitle }
        return "\(currentViewTitle) · \(selectedCount) selected"
    }

    private static func currentViewTitle(for navigationState: ContentPageNavigationRoute) -> String {
        switch navigationState {
        case .home:
            return "Home"

        case let .folder(path):
            if path == "/" {
                return "Computer"
            }
            let fallback = URL(fileURLWithPath: path).lastPathComponent
            return fallback.isEmpty ? path : fallback

        case .recents:
            return "Recents"

        case let .tags(tagName):
            return tagName

        case .computer:
            return "Computer"

        case let .collection(collectionNavigation):
            switch collectionNavigation.kind {
            case .temporary:
                return "New Collection"
            case let .file(_, name):
                return name
            }
        }
    }

    private static func currentViewIdentifier(for navigationState: ContentPageNavigationRoute) -> String {
        switch navigationState {
        case .home:
            "Home"
        case let .folder(path):
            path
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            "Computer"
        case let .collection(collectionNavigation):
            switch collectionNavigation.kind {
            case .temporary:
                "New Collection"
            case let .file(url, _):
                url.path
            }
        }
    }

    private static func currentViewMetadata(for navigationState: ContentPageNavigationRoute) -> [String: String] {
        switch navigationState {
        case .home:
            ["route": "home"]
        case let .folder(path):
            ["route": "folder", "path": path]
        case .recents:
            ["route": "recents"]
        case let .tags(tagName):
            ["route": "tags", "path": tagName]
        case .computer:
            ["route": "computer"]
        case let .collection(collectionNavigation):
            switch collectionNavigation.kind {
            case .temporary:
                ["route": "collection", "kind": "temporary"]
            case let .file(url, name):
                ["route": "collection", "kind": "file", "path": url.path, "name": name]
            }
        }
    }
}
