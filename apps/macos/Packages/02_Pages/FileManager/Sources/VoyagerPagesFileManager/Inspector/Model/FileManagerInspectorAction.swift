import ComposableArchitecture
import CoreGraphics
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

@CasePathable
public enum FileManagerInspectorAction: CasePathable, Sendable {
    case delegate(Delegate)

    case toggleInspector
    case setInspectorVisible(Bool)
    case setInspectorPaneExists(Bool)
    case setInspectorWidth(CGFloat)
    case closeChat
    case sessionHeaderNewChatTapped
    case sessionHeaderBackTapped
    case newChatRequested
    case showChatHistoryRequested
    case openChat(AiChatSetupState, AIConnectionsFile)
    case openNewChat(AiChatSetupState, AIConnectionsFile)
    case openChatHistory(AiChatSetupState, AIConnectionsFile)
    case aiChat(AiChatFeature.Action)

    @CasePathable
    public enum Delegate: Sendable {
        case newChatRequested
        case openAISettings
        case requestAttachmentPicker(AiChatSessionID)
        case clearCurrentContextSelection
    }
}
