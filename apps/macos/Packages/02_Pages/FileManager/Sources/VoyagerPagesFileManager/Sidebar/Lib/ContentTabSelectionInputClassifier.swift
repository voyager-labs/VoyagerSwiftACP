import VoyagerShared

enum ContentTabRowPrimaryIntent: Equatable {
    case activate
    case toggleSelection
    case selectRange
}

enum ContentTabSelectionInputClassifier {
    static func classify(_ modifiers: KeyModifiers) -> ContentTabRowPrimaryIntent {
        if modifiers.contains(.shift) {
            return .selectRange
        }
        if modifiers.contains(.command) || modifiers.contains(.option) {
            return .toggleSelection
        }
        return .activate
    }
}
