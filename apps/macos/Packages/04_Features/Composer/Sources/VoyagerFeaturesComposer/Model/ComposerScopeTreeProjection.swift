import Foundation

enum ComposerScopeTreeProjection {
    nonisolated static func closestAncestorPath(for path: String, candidates: [String]) -> String? {
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
        let matchingAncestors = candidates
            .map(ComposerScopeUtils.normalizeScopePath)
            .filter { ComposerScopeUtils.isStrictDescendant(normalizedPath, of: $0) }
        return selectMostSpecificPath(matchingAncestors)
    }

    nonisolated static func selectMostSpecificPath(_ normalizedPaths: [String]) -> String? {
        normalizedPaths.min { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count > rhs.count
        }
    }
}

struct TreeBaseInfo: Equatable {
    let path: String
    let normalizedPath: String

    init(base: ComposerScopeBase) {
        path = base.path
        normalizedPath = ComposerScopeUtils.normalizeScopePath(base.path)
    }
}

struct TreeExceptionInfo: Equatable {
    let path: String
    let normalizedPath: String
    let owningBasePath: String

    init(exception: ComposerScopeException, owningBasePath: String) {
        path = exception.path
        normalizedPath = ComposerScopeUtils.normalizeScopePath(exception.path)
        self.owningBasePath = owningBasePath
    }
}

struct CandidateRowMetadata: Equatable {
    let path: String
    let displayName: String
    let iconName: String
    let locationIdentifier: String?
    let secondaryText: String?
    let depth: Int
}

extension ComposerScopeTreeRowRuleSource {
    var isInherited: Bool {
        if case .inherited = self { true } else { false }
    }
}

struct ResolvedCandidateState: Equatable {
    let visualState: ComposerScopeTreeRowVisualState
    let ruleSource: ComposerScopeTreeRowRuleSource
    let availableActions: [ComposerScopeTreeRowAvailableAction]
    let owningBasePath: String?
}
