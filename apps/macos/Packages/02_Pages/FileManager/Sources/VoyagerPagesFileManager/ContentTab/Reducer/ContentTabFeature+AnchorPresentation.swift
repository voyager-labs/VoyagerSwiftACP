import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

extension ContentTabFeature {
    func title(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "Home"
        case let .directory(path):
            entryLoadingClient.displayName(path).nonEmpty ?? URL(fileURLWithPath: path).lastPathComponent
                .nonEmpty ?? path
        case let .collectionFile(url):
            CollectionFileUtils.displayName(url, fallback: url.lastPathComponent)
        case let .virtualCollection(id):
            id
        case .aiChat:
            "AI Chat"
        }
    }

    func iconName(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "house"
        case let .directory(path):
            fileManagerIconClient.iconNameForURL(URL(fileURLWithPath: path), true, entryLoadingClient)
        case .collectionFile:
            "rectangle.stack"
        case let .virtualCollection(id):
            id == "Recents" ? "clock" : "folder"
        case .aiChat:
            "bubble.right"
        }
    }

    func page(for anchor: ContentTabPageAnchor) -> ContentTabPage {
        switch anchor {
        case .homeDefault:
            .home
        case .directory:
            .directory
        case .collectionFile, .virtualCollection:
            .collection
        case .aiChat:
            .aiChat
        }
    }
}
