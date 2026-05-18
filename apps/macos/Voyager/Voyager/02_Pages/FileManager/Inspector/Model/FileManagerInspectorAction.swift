import ComposableArchitecture
import CoreGraphics
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

@CasePathable
enum FileManagerInspectorAction: CasePathable, Sendable {
    case delegate(Delegate)

    case toggleInspector
    case setInspectorVisible(Bool)
    case setInspectorPaneExists(Bool)
    case setInspectorWidth(CGFloat)
    case closeChat
    case openChat(AiChatSetupState, AIConnectionsFile)
    case aiChat(AiChatFeature.Action)

    @CasePathable
    enum Delegate: Sendable {
        case openAISettings
        case requestAttachmentPicker
    }
}
