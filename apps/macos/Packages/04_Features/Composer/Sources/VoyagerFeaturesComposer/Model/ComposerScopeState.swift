import Foundation

public struct ComposerScopeBase: Equatable, Sendable, Identifiable {
    public let path: String

    public var id: String { path }
}

public struct ComposerScopeException: Equatable, Sendable, Identifiable {
    public let path: String

    public var id: String { path }
}

public enum ComposerScopeSelection: Equatable, Sendable {
    case rootOnly
    case explicit(bases: [ComposerScopeBase], exceptions: [ComposerScopeException])

    public var explicitBases: [ComposerScopeBase] {
        switch self {
        case .rootOnly:
            []
        case let .explicit(bases, _):
            bases
        }
    }

    public var exceptions: [ComposerScopeException] {
        switch self {
        case .rootOnly:
            []
        case let .explicit(_, exceptions):
            exceptions
        }
    }

    public var hasExplicitBases: Bool {
        !explicitBases.isEmpty
    }

    public var hasExceptions: Bool {
        !exceptions.isEmpty
    }

    public var isRootOnly: Bool {
        explicitBases.isEmpty
    }

    public var legacyScopePaths: [String] {
        switch self {
        case .rootOnly:
            return [ComposerScopeUtils.rootScopePath]
        case let .explicit(bases, _):
            let paths = bases.map(\.path)
            return paths.isEmpty ? [ComposerScopeUtils.rootScopePath] : paths
        }
    }

    public static func fromLegacyScopes(_ scopes: [String]) -> Self {
        fromCanonicalScopes(bases: scopes, exceptions: [], includeSubfolders: true)
    }

    public static func fromCanonicalScopes(
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

public enum ComposerScopeCompositionState: Equatable, Sendable {
    case rootOnly
    case singleExplicit
    case multiExplicit
}

public enum ComposerScopeEditorEntryMode: Equatable, Sendable {
    case add
    case edit
}

public enum ScopeCandidateIntent: Equatable, Sendable {
    case add(path: String)
    case replace(oldPath: String, newPath: String)
    case exclude(path: String)
}

public enum ComposerScopeEditorListState: Equatable, Sendable {
    case defaultCandidates
    case childFolders(parentPath: String)
    case searchResults(query: String)
    case noResults(query: String)

    public var candidateSectionTitle: String {
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

    public var emptyStateMessage: String? {
        switch self {
        case .defaultCandidates, .searchResults:
            nil
        case .childFolders:
            "No subfolders found."
        case let .noResults(query):
            "No directories found for \"\(query)\"."
        }
    }

    public var emptyStateRecoveryMessage: String? {
        switch self {
        case .defaultCandidates, .childFolders, .searchResults:
            nil
        case .noResults:
            "Try another search or clear the search to return to the previous list."
        }
    }
}

public struct ComposerScopeEditorCurrentItem: Equatable, Sendable, Identifiable {
    let base: ComposerScopeBase
    let isEditingTarget: Bool
    let exceptionCount: Int

    public var id: String { base.id }

    var exceptionSummaryText: String? {
        guard exceptionCount > 0 else { return nil }
        return exceptionCount == 1 ? "1 exception" : "\(exceptionCount) exceptions"
    }
}

public struct ComposerScopeEditorCandidateItem: Equatable, Sendable, Identifiable {
    public let path: String
    let name: String
    let iconName: String
    let locationIdentifier: String?
    let secondaryText: String?

    public init(
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

    public var id: String { path }
}

public struct ComposerScopeEditorExceptionItem: Equatable, Sendable, Identifiable {
    public let path: String
    let owningBasePath: String

    public var id: String { "exception-\(owningBasePath)-\(path)" }
}

public enum ComposerScopeEditorSectionItem: Equatable, Sendable, Identifiable {
    case currentScope(ComposerScopeEditorCurrentItem)
    case exceptionScope(ComposerScopeEditorExceptionItem)
    case addableCandidate(ComposerScopeEditorCandidateItem)

    public var id: String {
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

public struct ComposerScopeEditorSection: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case currentScopes
        case addableCandidates(ComposerScopeEditorListState)

        public var id: String {
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

    public let kind: Kind
    public let items: [ComposerScopeEditorSectionItem]

    public var id: String { kind.id }
}

public struct ComposerScopeEditorState: Equatable, Sendable {
    public var selection: ComposerScopeSelection = .rootOnly
    public var includeSubfolders: Bool = true
    public var committedSelection: ComposerScopeSelection = .rootOnly
    public var committedIncludeSubfolders: Bool = true
    public var listState: ComposerScopeEditorListState = .defaultCandidates
    public var isPresented: Bool = false
    public var queryText: String = ""
    public var editingPath: String?
    public var entryMode: ComposerScopeEditorEntryMode = .add
    public var candidateItems: [ComposerScopeEditorCandidateItem] = []
    public var favorites: [ScopeFavoriteItem] = []
    public var backHistory: [String] = []

    public var compositionState: ComposerScopeCompositionState {
        switch selection.explicitBases.count {
        case 0:
            .rootOnly
        case 1:
            .singleExplicit
        default:
            .multiExplicit
        }
    }

    public var hasExceptions: Bool {
        selection.hasExceptions
    }

    public var effectiveIncludeSubfolders: Bool {
        selection.isRootOnly || includeSubfolders
    }

    public var isExactFolderOnlyMode: Bool {
        !selection.isRootOnly && !effectiveIncludeSubfolders
    }

    public var scopeRuleDescription: String {
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

    public func sections() -> [ComposerScopeEditorSection] {
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

        let normalizedCurrentPaths = Set(
            selection.explicitBases.map { ComposerScopeUtils.normalizeScopePath($0.path) },
        )
        let visibleCandidates = candidateItems
            .filter { !normalizedCurrentPaths.contains(ComposerScopeUtils.normalizeScopePath($0.path)) }
        let candidateSectionItems = disambiguatedVisibleCandidates(visibleCandidates)
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
        let exceptionsByOwningBasePath = exceptionItemsByOwningBasePath()
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

    private func exceptionItemsByOwningBasePath() -> [String: [ComposerScopeException]] {
        let normalizedBases = selection.explicitBases.map { base in
            (
                base: base,
                normalizedPath: ComposerScopeUtils.normalizeScopePath(base.path),
            )
        }
        var exceptionsByOwningBasePath: [String: [ComposerScopeException]] = [:]

        for exception in selection.exceptions {
            let normalizedExceptionPath = ComposerScopeUtils.normalizeScopePath(exception.path)
            let owningBase = normalizedBases
                .filter { ComposerScopeUtils.isStrictDescendant(normalizedExceptionPath, of: $0.normalizedPath) }
                .max { lhs, rhs in lhs.normalizedPath.count < rhs.normalizedPath.count }

            guard let owningBase else { continue }
            exceptionsByOwningBasePath[owningBase.base.path, default: []].append(exception)
        }

        return exceptionsByOwningBasePath
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

    private func disambiguatedVisibleCandidates(
        _ candidates: [ComposerScopeEditorCandidateItem],
    ) -> [ComposerScopeEditorCandidateItem] {
        ComposerScopeUtils.applyCandidateDisambiguationPolicy(
            candidates.map { candidate in
                ComposerScopeUtils.DirectoryItem(
                    id: candidate.id,
                    path: candidate.path,
                    name: candidate.name,
                    iconName: candidate.iconName,
                    locationIdentifier: candidate.locationIdentifier,
                    secondaryText: candidate.secondaryText,
                )
            },
        )
        .map { item in
            ComposerScopeEditorCandidateItem(
                path: item.path,
                name: item.name,
                iconName: item.iconName,
                locationIdentifier: item.locationIdentifier,
                secondaryText: item.secondaryText,
            )
        }
    }

    public func candidateSelectionIntent(for path: String) -> ScopeCandidateIntent {
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

    public var trimmedQueryText: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasPendingScopeRuleChanges: Bool {
        committedSelection != selection || committedIncludeSubfolders != includeSubfolders
    }
}
