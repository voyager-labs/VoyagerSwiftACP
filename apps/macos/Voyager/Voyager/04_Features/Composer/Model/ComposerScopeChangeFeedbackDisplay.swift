import Foundation

struct ComposerScopeChangeFeedbackDisplay: Equatable, Sendable {
    let title: String
    let message: String
    let phaseLabel: String
    let showsUndo: Bool
    let showsRedo: Bool
    let isFailure: Bool
    let isDelayed: Bool
    let accessibilityLabel: String?

    init(state: ComposerState, feedback: ComposerScopeChangeFeedback) {
        let afterSummary = feedback.afterScope.scopeSelection
            .summary(includeSubfolders: feedback.afterScope.includeSubfolders)
        let beforeSummary = feedback.beforeScope.scopeSelection
            .summary(includeSubfolders: feedback.beforeScope.includeSubfolders)
        let title = Self.title(for: feedback, afterSummary: afterSummary, beforeSummary: beforeSummary)
        let message = Self.message(for: feedback, afterSummary: afterSummary)
        let phaseLabel = Self.phaseLabel(for: feedback.phase)
        let matchesAfterScope = state.scopeEditor.selection == feedback.afterScope.scopeSelection
            && state.scopeEditor.includeSubfolders == feedback.afterScope.includeSubfolders
        let matchesBeforeScope = state.scopeEditor.selection == feedback.beforeScope.scopeSelection
            && state.scopeEditor.includeSubfolders == feedback.beforeScope.includeSubfolders

        self.title = title
        self.message = message
        self.phaseLabel = phaseLabel
        showsUndo = state.canUndo
            && matchesAfterScope
            && state.history.count == feedback.historyDepthAfterCommit
        showsRedo = state.canRedo
            && matchesBeforeScope
            && state.redoHistory.count > feedback.redoDepthAfterCommit
        isFailure = feedback.phase == .failed
        isDelayed = feedback.phase == .delayed
        accessibilityLabel = [title, message, phaseLabel]
            .compactMap { $0.isEmpty ? nil : $0 }
            .joined(separator: ", ")
    }

    private static func title(
        for feedback: ComposerScopeChangeFeedback,
        afterSummary: ComposerScopeSummary,
        beforeSummary: ComposerScopeSummary,
    ) -> String {
        switch feedback.origin {
        case .addBase, .replaceBase:
            return "Scope updated to \(afterSummary.primaryText)"
        case .removeBase:
            return "Removed \(changedBaseName(before: feedback.beforeScope, after: feedback.afterScope, fallback: beforeSummary.primaryText)) from scope"
        case .exclude:
            let baseName = changedBaseName(
                before: feedback.beforeScope,
                after: feedback.afterScope,
                fallback: beforeSummary.primaryText,
            )
            return "Excluded \(changedExceptionName(before: feedback.beforeScope, after: feedback.afterScope, fallback: afterSummary.primaryText)) from \(baseName)"
        case .restore:
            return "Restored \(changedExceptionName(before: feedback.beforeScope, after: feedback.afterScope, fallback: beforeSummary.primaryText))"
        case .includeSubfolders:
            return feedback.afterScope.includeSubfolders ? "Included subfolders" : "Limited to this folder"
        }
    }

    private static func message(
        for feedback: ComposerScopeChangeFeedback,
        afterSummary: ComposerScopeSummary,
    ) -> String {
        switch feedback.phase {
        case .visible:
            afterSummary.secondaryText ?? afterSummary.badgeText ?? afterSummary.primaryText
        case .delayed:
            "Scope change is still applying"
        case .failed:
            "Scope change could not be fully applied. Current selection was kept."
        }
    }

    private static func phaseLabel(for phase: ComposerScopeChangeFeedbackPhase) -> String {
        switch phase {
        case .visible:
            "Applied"
        case .delayed:
            "Applying"
        case .failed:
            "Failed"
        }
    }

    private static func changedBaseName(
        before: ComposerScopeSnapshot,
        after: ComposerScopeSnapshot,
        fallback: String,
    ) -> String {
        let beforeBases = Set(before.scopeSelection.explicitBases.map(\.path))
        let afterBases = Set(after.scopeSelection.explicitBases.map(\.path))
        let changedPath = beforeBases.symmetricDifference(afterBases).first ?? before.scopeSelection.explicitBases
            .first?.path
        return displayName(for: changedPath ?? fallback)
    }

    private static func changedExceptionName(
        before: ComposerScopeSnapshot,
        after: ComposerScopeSnapshot,
        fallback: String,
    ) -> String {
        let beforeExceptions = Set(before.scopeSelection.exceptions.map(\.path))
        let afterExceptions = Set(after.scopeSelection.exceptions.map(\.path))
        let changedPath = beforeExceptions.symmetricDifference(afterExceptions).first ?? after.scopeSelection.exceptions
            .first?.path
        return displayName(for: changedPath ?? fallback)
    }

    private static func displayName(for path: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let displayName = URL(fileURLWithPath: normalizedPath).lastPathComponent
        return displayName.isEmpty ? normalizedPath : displayName
    }
}

extension ComposerState {
    var lastScopeChangeFeedbackDisplay: ComposerScopeChangeFeedbackDisplay? {
        guard let lastScopeChangeFeedback, hasMatchingScopeChangeFeedback else { return nil }
        return ComposerScopeChangeFeedbackDisplay(state: self, feedback: lastScopeChangeFeedback)
    }
}
