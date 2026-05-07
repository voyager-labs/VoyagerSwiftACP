import ComposableArchitecture
import VoyagerFeaturesAiChat

@CasePathable
enum FileManagerInspectorAction: CasePathable, Sendable {
    case toggleInspector
    case setInspectorVisible(Bool)
    case setInspectorPaneExists(Bool)
    case openChat(AiChatSetupState)
    case aiChat(AiChatFeature.Action)
}
