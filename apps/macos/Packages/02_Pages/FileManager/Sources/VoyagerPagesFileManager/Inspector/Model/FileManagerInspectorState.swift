import ComposableArchitecture
import CoreGraphics
import VoyagerFeaturesAiChat

enum FileManagerInspectorMode: Equatable {
    case chat
}

public enum FileManagerInspectorLayoutMetrics {
    public static let defaultWidth: CGFloat = 300
    public static let minWidth: CGFloat = 230
}

@ObservableState
public struct FileManagerInspectorState: Equatable {
    var inspectorVisible: Bool = false
    var inspectorPaneExists: Bool = false
    var inspectorWidth: CGFloat = FileManagerInspectorLayoutMetrics.defaultWidth
    var activeMode: FileManagerInspectorMode = .chat
    var aiChat: AiChatFeature.State = .init()
}
