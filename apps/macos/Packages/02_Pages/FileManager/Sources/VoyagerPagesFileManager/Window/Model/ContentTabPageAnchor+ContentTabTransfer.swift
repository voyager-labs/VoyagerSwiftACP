import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

extension ContentTabPageAnchor {
    var aiChatSessionKey: String? {
        guard case let .aiChat(sessionID) = self else { return nil }
        return sessionID
    }

    var aiChatSessionID: AiChatSessionID? {
        guard let aiChatSessionKey, let uuid = UUID(uuidString: aiChatSessionKey) else { return nil }
        return AiChatSessionID(rawValue: uuid)
    }
}
