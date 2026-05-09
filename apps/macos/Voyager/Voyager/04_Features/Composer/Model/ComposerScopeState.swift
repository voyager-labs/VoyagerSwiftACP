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
        explicitBases.isEmpty
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

    static func fromLegacyScopes(_ scopes: [String]) -> Self {
        fromCanonicalScopes(bases: scopes, exceptions: [], includeSubfolders: true)
    }

    static func fromCanonicalScopes(
        bases: [String],
        exceptions: [String],
        includeSubfolders: Bool,
    ) -> Self {
        let canonical = ComposerScopeUtils.canonicalizeScopeRule(
            bases: bases,
            exceptions: exceptions,
            includeSubfolders: includeSubfolders,
        )

        guard !canonical.bases.isEmpty else { return .rootOnly }

        return .explicit(
            bases: canonical.bases.map(ComposerScopeBase.init(path:)),
            exceptions: canonical.exceptions.map(ComposerScopeException.init(path:)),
        )
    }

    func summary(includeSubfolders: Bool) -> ComposerScopeSummary {
        guard !isRootOnly else {
            return ComposerScopeSummary(primary: .rootOnly, secondaryItems: [], badges: [])
        }

        let secondaryItems: [ComposerScopeSummarySecondary] = switch explicitBases.count {
        case 1:
            includeSubfolders ? [.includeSubfolders] : [.onlySelectedFolder]
        default:
            includeSubfolders ? [.includeSubfolders] : [.onlySelectedFolders]
        }

        let badges: [ComposerScopeSummaryBadge] = hasExceptions
            ? [.exceptionCount(exceptions.count)]
            : []

        switch self {
        case .rootOnly:
            return ComposerScopeSummary(primary: .rootOnly, secondaryItems: [], badges: [])

        case let .explicit(bases, _):
            switch bases.count {
            case 1:
                return ComposerScopeSummary(
                    primary: .singleExplicit(path: bases[0].path),
                    secondaryItems: secondaryItems,
                    badges: badges,
                )
            default:
                return ComposerScopeSummary(
                    primary: .multiExplicit(count: bases.count),
                    secondaryItems: secondaryItems,
                    badges: badges,
                )
            }
        }
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

enum ScopeCandidateIntent: Equatable, Sendable {
    case add(path: String)
    case replace(oldPath: String, newPath: String)
    case exclude(path: String)
}

enum ComposerScopeEditorListState: Equatable, Sendable {
    case defaultCandidates
    case childFolders(parentPath: String)
    case searchResults(query: String)
    case noResults(query: String)

    var candidateSectionTitle: String {
        switch self {
        case .defaultCandidates:
            "Suggestions"
        case .childFolders:
            "Subfolders"
        case let .searchResults(query):
            "Search Results for \"\(query)\""
        case let .noResults(query):
            "No Results for \"\(query)\""
        }
    }

    var emptyStateMessage: String? {
        switch self {
        case .defaultCandidates, .searchResults:
            nil
        case .childFolders:
            "No subfolders found."
        case let .noResults(query):
            "No directories found for \"\(query)\"."
        }
    }

    var emptyStateRecoveryMessage: String? {
        switch self {
        case .defaultCandidates, .childFolders, .searchResults:
            nil
        case .noResults:
            "Try another search or clear the search to return to the previous list."
        }
    }
}

struct ComposerScopeEditorCurrentItem: Equatable, Sendable, Identifiable {
    let base: ComposerScopeBase
    let isEditingTarget: Bool
    let exceptionCount: Int

    var id: String { base.id }

    var exceptionSummaryText: String? {
        guard exceptionCount > 0 else { return nil }
        return exceptionCount == 1 ? "1 exception" : "\(exceptionCount) exceptions"
    }
}

struct ComposerScopeEditorCandidateItem: Equatable, Sendable, Identifiable {
    let path: String
    let name: String
    let iconName: String
    let locationIdentifier: String?
    let secondaryText: String?

    init(
        path: String,
        name: String,
        iconName: String,
        locationIdentifier: String? = nil,
        secondaryText: String? = nil,
    ) {
        self.path = path
        self.name = name
        self.iconName = iconName
        self.locationIdentifier = locationIdentifier
        self.secondaryText = secondaryText
    }

    var id: String { path }
}

struct ComposerScopeEditorExceptionItem: Equatable, Sendable, Identifiable {
    let path: String
    let owningBasePath: String

    var id: String { "exception-\(owningBasePath)-\(path)" }
}

enum ComposerScopeEditorSectionItem: Equatable, Sendable, Identifiable {
    case currentScope(ComposerScopeEditorCurrentItem)
    case exceptionScope(ComposerScopeEditorExceptionItem)
    case addableCandidate(ComposerScopeEditorCandidateItem)

    var id: String {
        switch self {
        case let .currentScope(item):
            "current-\(item.id)"
        case let .exceptionScope(item):
            item.id
        case let .addableCandidate(item):
            "candidate-\(item.id)"
        }
    }
}

struct ComposerScopeEditorSection: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case currentScopes
        case addableCandidates(ComposerScopeEditorListState)

        var id: String {
            switch self {
            case .currentScopes:
                "current-scopes"
            case let .addableCandidates(listState):
                switch listState {
                case .defaultCandidates:
                    "addable-default"
                case let .childFolders(parentPath):
                    "addable-children-\(parentPath)"
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

    var summary: ComposerScopeSummary {
        selection.summary(includeSubfolders: effectiveIncludeSubfolders)
    }

    func sections() -> [ComposerScopeEditorSection] {
        var sections: [ComposerScopeEditorSection] = []

        let currentItems = currentScopeSectionItems()
        if !currentItems.isEmpty {
            sections.append(
                ComposerScopeEditorSection(
                    kind: .currentScopes,
                    items: currentItems,
                ),
            )
        }

        let candidateSectionItems = visibleProjectionCandidates()
            .map { ComposerScopeEditorSectionItem.addableCandidate($0) }

        sections.append(
            ComposerScopeEditorSection(
                kind: .addableCandidates(listState),
                items: candidateSectionItems,
            ),
        )

        return sections
    }

    private func currentScopeSectionItems() -> [ComposerScopeEditorSectionItem] {
        let exceptionsByOwningBasePath = projectionExceptionsByOwningBasePath()
        var currentItems: [ComposerScopeEditorSectionItem] = []

        for base in selection.explicitBases {
            let owningExceptions = exceptionsByOwningBasePath[base.path, default: []]
            currentItems.append(
                .currentScope(
                    ComposerScopeEditorCurrentItem(
                        base: base,
                        isEditingTarget: base.path == editingPath,
                        exceptionCount: owningExceptions.count,
                    ),
                ),
            )
            currentItems.append(contentsOf: exceptionSectionItems(owningExceptions, owningBasePath: base.path))
        }

        return currentItems
    }

    private func exceptionSectionItems(
        _ exceptions: [ComposerScopeException],
        owningBasePath: String,
    ) -> [ComposerScopeEditorSectionItem] {
        exceptions.map {
            .exceptionScope(
                ComposerScopeEditorExceptionItem(
                    path: $0.path,
                    owningBasePath: owningBasePath,
                ),
            )
        }
    }

    func candidateSelectionIntent(for path: String) -> ScopeCandidateIntent {
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)

        guard entryMode == .edit,
              let editingPath
        else {
            return .add(path: normalizedPath)
        }

        let normalizedEditingPath = ComposerScopeUtils.normalizeScopePath(editingPath)
        if effectiveIncludeSubfolders,
           ComposerScopeUtils.isStrictDescendant(normalizedPath, of: normalizedEditingPath)
        {
            return .exclude(path: normalizedPath)
        }

        return .replace(oldPath: normalizedEditingPath, newPath: normalizedPath)
    }

    var trimmedQueryText: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasPendingScopeRuleChanges: Bool {
        committedSelection != selection || committedIncludeSubfolders != includeSubfolders
    }
}
