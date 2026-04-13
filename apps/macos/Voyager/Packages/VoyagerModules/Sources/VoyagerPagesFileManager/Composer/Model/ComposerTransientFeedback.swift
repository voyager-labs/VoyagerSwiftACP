import Foundation

public enum ComposerTransientFeedbackKind: Equatable, Sendable {
    case info
    case error
}

public struct ComposerTransientFeedback: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ComposerTransientFeedbackKind
    public let message: String
}
