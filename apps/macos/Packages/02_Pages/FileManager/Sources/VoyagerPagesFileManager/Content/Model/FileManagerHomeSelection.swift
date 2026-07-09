import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesContentPageNavigation

public enum FileManagerHomeSelection: Equatable, Sendable {
    case fixedDirectory(FileManagerHomeDirectory)
    case pageAnchor(ContentTabPageAnchor)
    case openDirectory
    case openCollection
    case startAiChat
    case chatHistory(AiChatSessionID)
}

public enum FileManagerHomeDirectory: Equatable, Hashable, Sendable, CaseIterable {
    case desktop
    case documents
    case downloads
    case applications
}
