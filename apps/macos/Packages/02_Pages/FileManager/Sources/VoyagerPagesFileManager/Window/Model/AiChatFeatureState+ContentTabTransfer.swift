import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

extension AiChatFeature.State {
    var contentTabTransferSessionIDs: Set<AiChatSessionID> {
        var sessionIDs = Set<AiChatSessionID>()
        if let sessionID { sessionIDs.insert(sessionID) }
        if let restoreSessionID { sessionIDs.insert(restoreSessionID) }
        if let pendingRequestStart { sessionIDs.insert(pendingRequestStart.sessionID) }
        sessionIDs.formUnion(backgroundPendingRequestStarts.values.map(\.sessionID))
        if let sessionID = executionPhase.lock?.context.sessionID { sessionIDs.insert(sessionID) }
        sessionIDs.formUnion(backgroundExecutionPhases.values.compactMap { $0.lock?.context.sessionID })
        return sessionIDs
    }
}
