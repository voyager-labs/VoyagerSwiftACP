import Foundation

enum ComposerScopeChangeFeedbackPhase: Equatable, Sendable {
    case visible
    case delayed
    case failed
}

enum ComposerScopeChangeFeedbackOrigin: Equatable, Sendable {
    case addBase
    case removeBase
    case replaceBase
    case exclude
    case restore
    case includeSubfolders
}

enum ScopeFeedbackPendingRequest: Equatable, Sendable {
    case search(UUID)
    case filters(UUID)
}

struct ComposerScopeSnapshot: Equatable, Sendable {
    let scopeSelection: ComposerScopeSelection
    let includeSubfolders: Bool
}

struct ComposerScopeChangeFeedback: Equatable, Sendable {
    let id: UUID
    let beforeScope: ComposerScopeSnapshot
    let afterScope: ComposerScopeSnapshot
    let origin: ComposerScopeChangeFeedbackOrigin
    let phase: ComposerScopeChangeFeedbackPhase
    let pendingResultRequest: ScopeFeedbackPendingRequest?
    let historyDepthAfterCommit: Int
    let redoDepthAfterCommit: Int
}

extension ComposerScopeChangeFeedback {
    func updating(
        pendingResultRequest: ScopeFeedbackPendingRequest,
        phase: ComposerScopeChangeFeedbackPhase? = nil,
    ) -> ComposerScopeChangeFeedback {
        ComposerScopeChangeFeedback(
            id: id,
            beforeScope: beforeScope,
            afterScope: afterScope,
            origin: origin,
            phase: phase ?? self.phase,
            pendingResultRequest: pendingResultRequest,
            historyDepthAfterCommit: historyDepthAfterCommit,
            redoDepthAfterCommit: redoDepthAfterCommit,
        )
    }

    func matchesCurrentScope(
        selection: ComposerScopeSelection,
        includeSubfolders: Bool,
    ) -> Bool {
        afterScope.scopeSelection == selection && afterScope.includeSubfolders == includeSubfolders
    }
}
