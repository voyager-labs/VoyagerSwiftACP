import ComposableArchitecture
import VoyagerFeaturesAiChat

@CasePathable
enum FileManagerInspectorAction: CasePathable, Sendable {
    case toggleInspector
    case setInspectorVisible(Bool)
    case setInspectorPaneExists(Bool)
    case closeChat
    case openChat(AiChatSetupState)
    case aiChat(AiChatFeature.Action)
}
