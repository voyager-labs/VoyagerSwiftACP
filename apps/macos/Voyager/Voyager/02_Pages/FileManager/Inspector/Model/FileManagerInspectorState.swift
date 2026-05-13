import ComposableArchitecture
import VoyagerFeaturesAiChat

enum FileManagerInspectorMode: Equatable, Sendable {
    case chat
}

@ObservableState
struct FileManagerInspectorState: Equatable {
    var inspectorVisible: Bool = false
    var inspectorPaneExists: Bool = false
    var activeMode: FileManagerInspectorMode = .chat
    var aiChat: AiChatFeature.State = .init()
}
