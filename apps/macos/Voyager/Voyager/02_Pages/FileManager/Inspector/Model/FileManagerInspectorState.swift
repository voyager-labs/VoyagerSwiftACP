import ComposableArchitecture
import CoreGraphics
import VoyagerFeaturesAiChat

enum FileManagerInspectorMode: Equatable, Sendable {
    case chat
}

enum FileManagerInspectorLayoutMetrics {
    static let defaultWidth: CGFloat = 300
    static let minWidth: CGFloat = 230
}

@ObservableState
struct FileManagerInspectorState: Equatable {
    var inspectorVisible: Bool = false
    var inspectorPaneExists: Bool = false
    var inspectorWidth: CGFloat = FileManagerInspectorLayoutMetrics.defaultWidth
    var activeMode: FileManagerInspectorMode = .chat
    var aiChat: AiChatFeature.State = .init()
}
