import Foundation

enum ComposerTransientFeedbackKind: Equatable, Sendable {
    case info
    case error
}

struct ComposerTransientFeedback: Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: ComposerTransientFeedbackKind
    let message: String
}
