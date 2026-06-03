import Foundation

enum ComposerScopeTreeRowVisualState: Equatable {
    case included
    case excluded
    case none
}

enum ComposerScopeTreeRowRuleSource: Equatable {
    case direct
    case inherited(sourcePath: String)
    case none
}

enum ComposerScopeTreeRowAvailableAction: Equatable {
    case include
    case exclude
    case clearDirectRule
}

enum ComposerScopeTreeRowKind: String, Equatable {
    case root
    case base
    case exception
    case candidate
}

enum ComposerScopeTreeRowActionIntent: Equatable {
    case addBase(path: String)
    case exclude(path: String)
    case removeBase(path: String)
    case restoreException(path: String)
    case none
}

struct ComposerScopeTreeRow: Equatable, Identifiable {
    let path: String
    let depth: Int
    let displayName: String
    let iconName: String
    let locationIdentifier: String?
    let secondaryText: String?
    let kind: ComposerScopeTreeRowKind
    let visualState: ComposerScopeTreeRowVisualState
    let ruleSource: ComposerScopeTreeRowRuleSource
    let availableActions: [ComposerScopeTreeRowAvailableAction]
    let owningBasePath: String?

    var id: String {
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
        return "\(kind.rawValue)-\(normalizedPath)"
    }
}

struct ComposerScopeTreeSeedItem: Equatable, Identifiable {
    let path: String
    let name: String
    let iconName: String
    let locationIdentifier: String?
    let secondaryText: String?
    let depth: Int?

    init(
        path: String,
        name: String,
        iconName: String,
        locationIdentifier: String? = nil,
        secondaryText: String? = nil,
        depth: Int? = nil,
    ) {
        self.path = path
        self.name = name
        self.iconName = iconName
        self.locationIdentifier = locationIdentifier
        self.secondaryText = secondaryText
        self.depth = depth
    }

    var id: String {
        ComposerScopeUtils.normalizeScopePath(path)
    }
}

extension ComposerScopeEditorState {
    func treeActionIntent(
        rowPath: String,
        action: ComposerScopeTreeRowAvailableAction,
    ) -> ComposerScopeTreeRowActionIntent {
        let normalizedRowPath = ComposerScopeUtils.normalizeScopePath(rowPath)
        let row = resolvedTreeRow(for: normalizedRowPath)
        guard row.availableActions.contains(action) else { return .none }
        switch action {
        case .include:
            return .addBase(path: row.path)
        case .exclude:
            return .exclude(path: row.path)
        case .clearDirectRule:
            switch (row.ruleSource, row.visualState) {
            case (.direct, .included):
                return .removeBase(path: row.path)
            case (.direct, .excluded):
                return .restoreException(path: row.path)
            default:
                return .none
            }
        }
    }

    func treeRows(neighborhoodSeedItems: [ComposerScopeTreeSeedItem] = []) -> [ComposerScopeTreeRow] {
        let baseInfos = selection.explicitBases.map(TreeBaseInfo.init)
        let exceptionInfos = makeExceptionInfos(baseInfos: baseInfos)
        let orderedRows = rootRows()
            + directScopeRows(exceptionInfos: exceptionInfos)
            + canonicalCandidateRows(baseInfos: baseInfos, exceptionInfos: exceptionInfos)
            + neighborhoodRows(
                neighborhoodSeedItems,
                baseInfos: baseInfos,
                exceptionInfos: exceptionInfos,
            )
        return dedupedRows(orderedRows)
    }

    private func rootRows() -> [ComposerScopeTreeRow] {
        selection.isRootOnly ? [makeRootRow()] : []
    }

    private func resolvedTreeRow(for normalizedPath: String) -> ComposerScopeTreeRow {
        if let directBase = selection.explicitBases.first(where: {
            ComposerScopeUtils.normalizeScopePath($0.path) == normalizedPath
        }) {
            return makeDirectBaseRow(directBase)
        }
        let baseInfos = selection.explicitBases.map(TreeBaseInfo.init)
        let exceptionInfos = makeExceptionInfos(baseInfos: baseInfos)
        if let directException = exceptionInfos.first(where: { $0.normalizedPath == normalizedPath }) {
            return makeDirectExceptionRow(directException)
        }
        return makeCandidateRow(
            CandidateRowMetadata(
                path: normalizedPath,
                displayName: displayName(for: normalizedPath),
                iconName: "folder",
                locationIdentifier: nil,
                secondaryText: nil,
                depth: 0,
            ),
            baseInfos: baseInfos,
            exceptionInfos: exceptionInfos,
        )
    }

    private func directScopeRows(exceptionInfos: [TreeExceptionInfo]) -> [ComposerScopeTreeRow] {
        let exceptionInfosByOwningBasePath = Dictionary(grouping: exceptionInfos, by: \.owningBasePath)
        return selection.explicitBases.flatMap { base -> [ComposerScopeTreeRow] in
            let baseRow = makeDirectBaseRow(base)
            let exceptionRows = exceptionInfosByOwningBasePath[base.path, default: []].map(makeDirectExceptionRow)
            return [baseRow] + exceptionRows
        }
    }

    func visibleProjectionCandidates() -> [ComposerScopeEditorCandidateItem] {
        visibleCandidateItems()
    }

    func projectionExceptionsByOwningBasePath() -> [String: [ComposerScopeException]] {
        let baseInfos = selection.explicitBases.map(TreeBaseInfo.init)
        let exceptionInfos = makeExceptionInfos(baseInfos: baseInfos)
        return Dictionary(grouping: exceptionInfos, by: \.owningBasePath)
            .mapValues { $0.map { ComposerScopeException(path: $0.path) } }
    }

    private func canonicalCandidateRows(
        baseInfos: [TreeBaseInfo],
        exceptionInfos: [TreeExceptionInfo],
    ) -> [ComposerScopeTreeRow] {
        visibleCandidateItems().map { candidate in
            makeCandidateRow(
                candidate,
                depth: 0,
                baseInfos: baseInfos,
                exceptionInfos: exceptionInfos,
            )
        }
    }

    private func neighborhoodRows(
        _ seedItems: [ComposerScopeTreeSeedItem],
        baseInfos: [TreeBaseInfo],
        exceptionInfos: [TreeExceptionInfo],
    ) -> [ComposerScopeTreeRow] {
        seedItems.map { seed in
            makeCandidateRow(
                seed,
                depth: seed.depth ?? 0,
                baseInfos: baseInfos,
                exceptionInfos: exceptionInfos,
            )
        }
    }

    private func dedupedRows(_ rows: [ComposerScopeTreeRow]) -> [ComposerScopeTreeRow] {
        var deduped: [ComposerScopeTreeRow] = []
        var seenNormalizedPaths: Set<String> = []

        for row in rows {
            let normalizedPath = ComposerScopeUtils.normalizeScopePath(row.path)
            guard seenNormalizedPaths.insert(normalizedPath).inserted else { continue }
            deduped.append(row)
        }
        return deduped
    }

    private func makeExceptionInfos(baseInfos: [TreeBaseInfo]) -> [TreeExceptionInfo] {
        selection.exceptions.compactMap { exception -> TreeExceptionInfo? in
            guard let owningBase = closestOwningBase(for: exception.path, bases: baseInfos) else {
                return nil
            }
            return TreeExceptionInfo(exception: exception, owningBasePath: owningBase.path)
        }
    }

    private func makeRootRow() -> ComposerScopeTreeRow {
        ComposerScopeTreeRow(
            path: ComposerScopeUtils.rootScopePath,
            depth: 0,
            displayName: "This Mac",
            iconName: "folder",
            locationIdentifier: nil,
            secondaryText: nil,
            kind: .root,
            visualState: .included,
            ruleSource: .none,
            availableActions: [],
            owningBasePath: nil,
        )
    }

    private func makeDirectBaseRow(_ base: ComposerScopeBase) -> ComposerScopeTreeRow {
        ComposerScopeTreeRow(
            path: base.path,
            depth: 0,
            displayName: displayName(for: base.path),
            iconName: "folder",
            locationIdentifier: nil,
            secondaryText: nil,
            kind: .base,
            visualState: .included,
            ruleSource: .direct,
            availableActions: [.clearDirectRule],
            owningBasePath: nil,
        )
    }

    private func makeDirectExceptionRow(_ exceptionInfo: TreeExceptionInfo) -> ComposerScopeTreeRow {
        ComposerScopeTreeRow(
            path: exceptionInfo.path,
            depth: 1,
            displayName: displayName(for: exceptionInfo.path),
            iconName: "folder",
            locationIdentifier: nil,
            secondaryText: nil,
            kind: .exception,
            visualState: .excluded,
            ruleSource: .direct,
            availableActions: [.clearDirectRule],
            owningBasePath: exceptionInfo.owningBasePath,
        )
    }

    private func makeCandidateRow(
        _ candidate: ComposerScopeEditorCandidateItem,
        depth: Int,
        baseInfos: [TreeBaseInfo],
        exceptionInfos: [TreeExceptionInfo],
    ) -> ComposerScopeTreeRow {
        makeCandidateRow(
            CandidateRowMetadata(
                path: candidate.path,
                displayName: candidate.name,
                iconName: candidate.iconName,
                locationIdentifier: candidate.locationIdentifier,
                secondaryText: candidate.secondaryText,
                depth: depth,
            ),
            baseInfos: baseInfos,
            exceptionInfos: exceptionInfos,
        )
    }

    private func makeCandidateRow(
        _ seed: ComposerScopeTreeSeedItem,
        depth: Int,
        baseInfos: [TreeBaseInfo],
        exceptionInfos: [TreeExceptionInfo],
    ) -> ComposerScopeTreeRow {
        makeCandidateRow(
            CandidateRowMetadata(
                path: seed.path,
                displayName: seed.name,
                iconName: seed.iconName,
                locationIdentifier: seed.locationIdentifier,
                secondaryText: seed.secondaryText,
                depth: depth,
            ),
            baseInfos: baseInfos,
            exceptionInfos: exceptionInfos,
        )
    }

    private func makeCandidateRow(
        _ metadata: CandidateRowMetadata,
        baseInfos: [TreeBaseInfo],
        exceptionInfos: [TreeExceptionInfo],
    ) -> ComposerScopeTreeRow {
        let resolvedState = resolvedCandidateState(
            path: metadata.path,
            baseInfos: baseInfos,
            exceptionInfos: exceptionInfos,
        )
        return ComposerScopeTreeRow(
            path: metadata.path,
            depth: metadata.depth,
            displayName: metadata.displayName,
            iconName: metadata.iconName,
            locationIdentifier: metadata.locationIdentifier,
            secondaryText: metadata.secondaryText,
            kind: .candidate,
            visualState: resolvedState.visualState,
            ruleSource: resolvedState.ruleSource,
            availableActions: resolvedState.availableActions,
            owningBasePath: resolvedState.owningBasePath,
        )
    }

    private func resolvedCandidateState(
        path: String,
        baseInfos: [TreeBaseInfo],
        exceptionInfos: [TreeExceptionInfo],
    ) -> ResolvedCandidateState {
        if selection.isRootOnly {
            return ResolvedCandidateState(
                visualState: .none,
                ruleSource: .none,
                availableActions: [.include],
                owningBasePath: nil,
            )
        }
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
        if let directException = exceptionInfos.first(where: { $0.normalizedPath == normalizedPath }) {
            return ResolvedCandidateState(
                visualState: .excluded,
                ruleSource: .direct,
                availableActions: [.clearDirectRule],
                owningBasePath: directException.owningBasePath,
            )
        }
        if baseInfos.contains(where: { $0.normalizedPath == normalizedPath }) {
            return ResolvedCandidateState(
                visualState: .included,
                ruleSource: .direct,
                availableActions: [.clearDirectRule],
                owningBasePath: nil,
            )
        }
        if let closestException = closestExceptionInfo(for: path, exceptions: exceptionInfos) {
            return ResolvedCandidateState(
                visualState: .excluded,
                ruleSource: .inherited(sourcePath: closestException.path),
                availableActions: [],
                owningBasePath: closestOwningBase(for: path, bases: baseInfos)?.path,
            )
        }
        if effectiveIncludeSubfolders,
           let closestBase = closestOwningBase(for: path, bases: baseInfos)
        {
            return ResolvedCandidateState(
                visualState: .included,
                ruleSource: .inherited(sourcePath: closestBase.path),
                availableActions: [.exclude],
                owningBasePath: closestBase.path,
            )
        }
        return ResolvedCandidateState(
            visualState: .none,
            ruleSource: .none,
            availableActions: [.include],
            owningBasePath: nil,
        )
    }

    private func visibleCandidateItems() -> [ComposerScopeEditorCandidateItem] {
        let normalizedCurrentPaths = Set(selection.explicitBases.map { ComposerScopeUtils.normalizeScopePath($0.path) })
        let visibleCandidates = candidateItems
            .filter { !normalizedCurrentPaths.contains(ComposerScopeUtils.normalizeScopePath($0.path)) }
        return ComposerScopeUtils.applyCandidateDisambiguationPolicy(
            visibleCandidates.map { candidate in
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

    private func closestOwningBase(for path: String, bases: [TreeBaseInfo]) -> TreeBaseInfo? {
        let candidatePath = ComposerScopeUtils.normalizeScopePath(path)
        let rankedPaths = bases.map(\.normalizedPath)
        guard let selectedPath = ComposerScopeTreeProjection.closestAncestorPath(
            for: candidatePath,
            candidates: rankedPaths,
        ) else {
            return nil
        }
        return bases.first(where: { $0.normalizedPath == selectedPath })
    }

    private func closestExceptionInfo(for path: String, exceptions: [TreeExceptionInfo]) -> TreeExceptionInfo? {
        let candidatePath = ComposerScopeUtils.normalizeScopePath(path)
        let rankedPaths = exceptions.map(\.normalizedPath)
        guard let selectedPath = ComposerScopeTreeProjection.closestAncestorPath(
            for: candidatePath,
            candidates: rankedPaths,
        ) else {
            return nil
        }
        return exceptions.first(where: { $0.normalizedPath == selectedPath })
    }

    private func displayName(for path: String) -> String {
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
        if normalizedPath == ComposerScopeUtils.rootScopePath {
            return "This Mac"
        }

        let pathName = (normalizedPath as NSString).lastPathComponent
        return pathName.isEmpty ? normalizedPath : pathName
    }
}
