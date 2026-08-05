import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

enum FileManagerAiChatNewChatTarget: Equatable {
    case inspector(
        snapshot: AiChatCurrentContextSnapshot,
        provenance: AiChatNewChatPreparationProvenance,
    )
    case content(
        expectedAnchor: ContentTabPageAnchor,
        provenance: AiChatNewChatPreparationProvenance,
    )
    case homeContent(
        expectedSessionID: AiChatSessionID,
        expectedAnchor: ContentTabPageAnchor,
        provenance: AiChatNewChatPreparationProvenance,
    )
}

enum FileManagerAiChatNewChatTargetKind: Equatable {
    case inspector
    case content
}
