import Foundation

struct ComposerScopeBase: Equatable, Sendable, Identifiable {
    let path: String

    var id: String { path }
}

struct ComposerScopeException: Equatable, Sendable, Identifiable {
    let path: String

    var id: String { path }
}

enum ComposerScopeSelection: Equatable, Sendable {
    case rootOnly
    case explicit(bases: [ComposerScopeBase], exceptions: [ComposerScopeException])

    var explicitBases: [ComposerScopeBase] {
        switch self {
        case .rootOnly:
            []
        case let .explicit(bases, _):
            bases
        }
    }

    var exceptions: [ComposerScopeException] {
        switch self {
        case .rootOnly:
            []
        case let .explicit(_, exceptions):
            exceptions
        }
    }

    var hasExplicitBases: Bool {
        !explicitBases.isEmpty
    }

    var hasExceptions: Bool {
        !exceptions.isEmpty
    }

    var isRootOnly: Bool {
        switch self {
        case .rootOnly:
            true
        case .explicit:
            false
        }
    }

    var legacyScopePaths: [String] {
        switch self {
        case .rootOnly:
            return [ComposerScopeUtils.rootScopePath]
        case let .explicit(bases, _):
            let paths = bases.map(\.path)
            return paths.isEmpty ? [ComposerScopeUtils.rootScopePath] : paths
        }
    }

    var summary: ComposerScopeSummary {
        let secondary: [ComposerScopeSummarySecondary] = hasExceptions
            ? [.exceptionCount(exceptions.count)]
            : []

        switch self {
        case .rootOnly:
            return ComposerScopeSummary(primary: .rootOnly, secondary: secondary)

        case let .explicit(bases, _):
            switch bases.count {
            case 0:
                return ComposerScopeSummary(primary: .rootOnly, secondary: secondary)
            case 1:
                return ComposerScopeSummary(primary: .singleExplicit(path: bases[0].path), secondary: secondary)
            default:
                return ComposerScopeSummary(primary: .multiExplicit(count: bases.count), secondary: secondary)
            }
        }
    }

    static func fromLegacyScopes(_ scopes: [String]) -> Self {
        let normalized = scopes
            .map(ComposerScopeUtils.normalizeScopePath)
            .reduce(into: [String]()) { partialResult, path in
                guard !partialResult.contains(path) else { return }
                partialResult.append(path)
            }

        guard !normalized.isEmpty else { return .rootOnly }
        guard !normalized.contains(ComposerScopeUtils.rootScopePath) else { return .rootOnly }

        let explicitPaths = normalized.filter { $0 != ComposerScopeUtils.rootScopePath }
        guard !explicitPaths.isEmpty else { return .rootOnly }

        return .explicit(
            bases: explicitPaths.map(ComposerScopeBase.init(path:)),
            exceptions: [],
        )
    }
}

enum ComposerScopeCompositionState: Equatable, Sendable {
    case rootOnly
    case singleExplicit
    case multiExplicit
}

enum ComposerScopeEditorEntryMode: Equatable, Sendable {
    case add
    case edit
}

enum ComposerScopeEditorListState: Equatable, Sendable {
    case defaultCandidates
    case searchResults(query: String)
    case noResults(query: String)

    var candidateSectionTitle: String {
        switch self {
        case .defaultCandidates:
            "Suggestions"
        case .searchResults:
            "Search Results"
        case .noResults:
            "No Results"
        }
    }

    var emptyStateMessage: String? {
        switch self {
        case .defaultCandidates, .searchResults:
            nil
        case let .noResults(query):
            "No directories found for \"\(query)\""
        }
    }
}

struct ComposerScopeEditorCurrentItem: Equatable, Sendable, Identifiable {
    let base: ComposerScopeBase
    let isEditingTarget: Bool

    var id: String { base.id }
}

enum ComposerScopeEditorExceptionSlotState: Equatable, Sendable {
    case empty
    case exceptionPresent(count: Int)
}

struct ComposerScopeEditorCandidateItem: Equatable, Sendable, Identifiable {
    let path: String
    let name: String
    let iconName: String

    var id: String { path }
}

enum ComposerScopeEditorSectionItem: Equatable, Sendable, Identifiable {
    case currentScope(ComposerScopeEditorCurrentItem)
    case exceptionSlot(ComposerScopeEditorExceptionSlotState)
    case addableCandidate(ComposerScopeEditorCandidateItem)

    var id: String {
        switch self {
        case let .currentScope(item):
            "current-\(item.id)"
        case let .exceptionSlot(state):
            switch state {
            case .empty:
                "exception-empty"
            case let .exceptionPresent(count):
                "exception-present-\(count)"
            }
        case let .addableCandidate(item):
            "candidate-\(item.id)"
        }
    }
}

struct ComposerScopeEditorSection: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case currentScopes
        case exceptionSlot
        case addableCandidates(ComposerScopeEditorListState)

        var id: String {
            switch self {
            case .currentScopes:
                "current-scopes"
            case .exceptionSlot:
                "exception-slot"
            case let .addableCandidates(listState):
                switch listState {
                case .defaultCandidates:
                    "addable-default"
                case let .searchResults(query):
                    "addable-search-\(query)"
                case let .noResults(query):
                    "addable-empty-\(query)"
                }
            }
        }
    }

    let kind: Kind
    let items: [ComposerScopeEditorSectionItem]

    var id: String { kind.id }
}

struct ComposerScopeEditorState: Equatable, Sendable {
    var selection: ComposerScopeSelection = .rootOnly
    var includeSubfolders: Bool = true
    var committedSelection: ComposerScopeSelection = .rootOnly
    var committedIncludeSubfolders: Bool = true
    var listState: ComposerScopeEditorListState = .defaultCandidates
    var isPresented: Bool = false
    var queryText: String = ""
    var editingPath: String?
    var entryMode: ComposerScopeEditorEntryMode = .add
    var candidateItems: [ComposerScopeEditorCandidateItem] = []
    var favorites: [ScopeFavoriteItem] = []
    var backHistory: [String] = []

    var compositionState: ComposerScopeCompositionState {
        switch selection.explicitBases.count {
        case 0:
            .rootOnly
        case 1:
            .singleExplicit
        default:
            .multiExplicit
        }
    }

    var hasExceptions: Bool {
        selection.hasExceptions
    }

    var effectiveIncludeSubfolders: Bool {
        selection.isRootOnly || includeSubfolders
    }

    var isExactFolderOnlyMode: Bool {
        !selection.isRootOnly && !effectiveIncludeSubfolders
    }

    var scopeRuleDescription: String {
        if selection.isRootOnly {
            "This Mac"
        } else if effectiveIncludeSubfolders {
            "Include subfolders"
        } else {
            "Only selected folder"
        }
    }

    func sections(
        editingPath: String? = nil,
    ) -> [ComposerScopeEditorSection] {
        var sections: [ComposerScopeEditorSection] = []

        let currentItems = selection.explicitBases.map {
            ComposerScopeEditorSectionItem.currentScope(
                ComposerScopeEditorCurrentItem(
                    base: $0,
                    isEditingTarget: $0.path == editingPath,
                ),
            )
        }

        if !currentItems.isEmpty {
            sections.append(
                ComposerScopeEditorSection(
                    kind: .currentScopes,
                    items: currentItems,
                ),
            )
        }

        let exceptionSlotState: ComposerScopeEditorExceptionSlotState = selection.exceptions.isEmpty
            ? .empty
            : .exceptionPresent(count: selection.exceptions.count)

        sections.append(
            ComposerScopeEditorSection(
                kind: .exceptionSlot,
                items: [.exceptionSlot(exceptionSlotState)],
            ),
        )

        let normalizedCurrentPaths = Set(
            selection.explicitBases.map { ComposerScopeUtils.normalizeScopePath($0.path) },
        )
        let candidateSectionItems = candidateItems
            .filter { !normalizedCurrentPaths.contains(ComposerScopeUtils.normalizeScopePath($0.path)) }
            .map { ComposerScopeEditorSectionItem.addableCandidate($0) }

        sections.append(
            ComposerScopeEditorSection(
                kind: .addableCandidates(listState),
                items: candidateSectionItems,
            ),
        )

        return sections
    }

    var trimmedQueryText: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasPendingScopeRuleChanges: Bool {
        committedSelection != selection || committedIncludeSubfolders != includeSubfolders
    }
}
