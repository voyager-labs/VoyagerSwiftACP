import Foundation

public enum ComposerTransientFeedbackKind: Equatable, Sendable {
    case info
    case error
}

public enum ComposerTransientFeedbackStage: Equatable, Sendable {
    case valueInput
    case queryConversion
    case queryExecution
    case save
}

public enum ComposerTransientFeedbackCategory: Equatable, Sendable {
    case invalidValue
    case incompleteValue
    case conversionFailure
    case executionFailure
    case saveBlocked
    case saveFailed
}

public struct ComposerTransientFeedback: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ComposerTransientFeedbackKind
    public let stage: ComposerTransientFeedbackStage?
    public let category: ComposerTransientFeedbackCategory?
    public let message: String
    public let recoveryHint: String?

    public init(
        id: UUID,
        kind: ComposerTransientFeedbackKind,
        message: String,
        stage: ComposerTransientFeedbackStage? = nil,
        category: ComposerTransientFeedbackCategory? = nil,
        recoveryHint: String? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.stage = stage
        self.category = category
        self.message = message
        self.recoveryHint = recoveryHint
    }
}
