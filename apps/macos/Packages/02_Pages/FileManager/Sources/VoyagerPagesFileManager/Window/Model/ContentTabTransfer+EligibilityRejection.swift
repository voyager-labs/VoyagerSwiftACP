import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

extension ContentTabTransfer.EligibilityRejection {
    init(_ rejection: ContentTabTransferEligibilityRejection) {
        self = switch rejection {
        case .pendingContentTabClose:
            .pendingContentTabClose
        case .pendingPinnedRecordPersistence:
            .pendingPinnedRecordPersistence
        case .pendingCollectionOperation:
            .pendingCollectionOperation
        case .pendingAiChatOperation:
            .pendingAiChatOperation
        case .malformedOwnership:
            .malformedOwnership
        }
    }
}
