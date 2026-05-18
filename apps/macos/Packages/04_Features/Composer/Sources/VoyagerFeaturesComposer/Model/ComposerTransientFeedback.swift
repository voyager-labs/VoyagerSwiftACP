import Foundation

public enum ComposerTransientFeedbackKind: Equatable, Sendable {
    case info
    case error
}

public struct ComposerTransientFeedback: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ComposerTransientFeedbackKind
    public let message: String

    public init(id: UUID, kind: ComposerTransientFeedbackKind, message: String) {
        self.id = id
        self.kind = kind
        self.message = message
    }
}
