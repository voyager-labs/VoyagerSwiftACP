import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

@CasePathable
enum FileManagerInspectorAction: CasePathable, Sendable {
    case delegate(Delegate)

    case toggleInspector
    case setInspectorVisible(Bool)
    case setInspectorPaneExists(Bool)
    case closeChat
    case openChat(AiChatSetupState, AIConnectionsFile)
    case aiChat(AiChatFeature.Action)

    @CasePathable
    enum Delegate: Sendable {
        case openAISettings
    }
}
