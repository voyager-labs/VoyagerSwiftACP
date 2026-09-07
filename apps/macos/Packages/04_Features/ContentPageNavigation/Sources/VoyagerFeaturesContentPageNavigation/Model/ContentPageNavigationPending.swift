import Foundation

public enum ContentPageNavigationPending: Equatable, Sendable {
    case back
    case forward
    case history(index: Int, isBackHistory: Bool)
    case enclosingDirectory
    case navigateToPath(String)
    case showRecents
    case showComputer
    case showTag(String)
    case showAiChat(String)
    case showAiChatSessions(String)
    case openCollectionFile(URL)
}

public extension ContentPageNavigationPending {
    /// 현재 route에서 이 direct pending의 수행이 no-op인지 판별한다.
    /// computerName 특례 no-op은 요청 출발점인 FileManager window reducer가 소유한다.
    func isSameDirectRoute(as navigationState: ContentPageNavigationRoute) -> Bool {
        switch (self, navigationState) {
        case (.showRecents, .recents):
            true
        case (.showComputer, .computer):
            true
        case let (.showTag(tagName), .tags(currentTagName)):
            tagName == currentTagName
        case let (.showAiChat(sessionID), .aiChat(currentSessionID)):
            sessionID == currentSessionID
        case let (.showAiChatSessions(sessionID), .aiChatSessions(currentSessionID)):
            sessionID == currentSessionID
        default:
            false
        }
    }
}
