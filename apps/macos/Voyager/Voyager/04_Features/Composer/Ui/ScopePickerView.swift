import ComposableArchitecture
import SwiftUI

struct ScopePickerView: View {
    let store: StoreOf<ComposerFeature>

    private struct ViewState: Equatable {
        let scopeEditor: ComposerScopeEditorState
        let lastScopeChangeFeedbackDisplay: ComposerScopeChangeFeedbackDisplay?
    }

    private static let cachedApplicationsIcon: NSImage? = {
        let appIcon = NSImage(
            contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns",
        )
        appIcon?.isTemplate = true
        return appIcon
    }()

    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        WithViewStore(
            store,
            observe: { state in
                ViewState(
                    scopeEditor: state.scopeEditor,
                    lastScopeChangeFeedbackDisplay: state.lastScopeChangeFeedbackDisplay,
                )
            },
            content: { viewStore in
                let queryTextBinding = Binding(
                    get: { viewStore.scopeEditor.queryText },
                    set: { store.send(.scopeEditorSetQueryText($0)) },
                )

                VStack(spacing: 0) {
                    searchField(queryText: queryTextBinding)
                    currentSummaryRow(viewStore: viewStore)
                    if let display = viewStore.lastScopeChangeFeedbackDisplay {
                        scopeChangeFeedbackBanner(display)
                    }
                    listContent(viewStore: viewStore)
                }
                .frame(width: ScopePickerPresentationMetrics.width)
                .frame(maxHeight: ScopePickerPresentationMetrics.maxHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
                )
                .accessibilityIdentifier(ScopePickerAccessibilityID.surface)
                .onAppear {
                    isSearchFocused = true
                }
            },
        )
    }
}

private extension ScopePickerView {
    private func currentSummaryRow(
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) -> some View {
        ScopeEditorSummaryRow(
            summary: viewStore.scopeEditor.summary,
            ruleDescription: viewStore.scopeEditor.scopeRuleDescription,
            includeSubfolders: viewStore.scopeEditor.selection.isRootOnly ? nil : viewStore.scopeEditor
                .includeSubfolders,
            onToggleIncludeSubfolders: { store.send(.scopeEditorSetIncludeSubfolders(!$0)) },
        )
        .accessibilityIdentifier(ScopePickerAccessibilityID.currentSummary)
    }

    private func searchField(queryText: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search directories...", text: queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .accessibilityIdentifier(ScopePickerAccessibilityID.searchField)

                if !queryText.wrappedValue.isEmpty {
                    Button {
                        queryText.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(VoyagerDS.Surface.popoverSearchFieldBackground(for: colorScheme))

            VoyagerDS.SystemColor.separator
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func scopeChangeFeedbackBanner(_ display: ComposerScopeChangeFeedbackDisplay) -> some View {
        ScopeChangeFeedbackBannerView(
            display: display,
            colorScheme: colorScheme,
            onUndo: { store.send(.scopeFeedbackUndoTapped) },
            onRedo: { store.send(.scopeFeedbackRedoTapped) },
        )
        .accessibilityIdentifier(ScopePickerAccessibilityID.feedbackBanner)
    }

    @ViewBuilder
    private func listContent(viewStore: ViewStore<ViewState, ComposerFeature.Action>) -> some View {
        let rows = viewStore.scopeEditor.treeRows(
            neighborhoodSeedItems: viewStore.scopeEditor.treeNeighborhoodSeedItems,
        )
        let sections = makeScopeSections(rows: rows, viewStore: viewStore)
        let listItems = makeScopeListItems(sections: sections)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(listItems) { item in
                    scopeListItemView(item, viewStore: viewStore)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityIdentifier(ScopePickerAccessibilityID.treeSection)
        }
    }

    private var sectionDivider: some View {
        VoyagerDS.SystemColor.separator
            .frame(height: 1)
            .padding(.horizontal, 2)
            .opacity(0.8)
    }

    private func makeScopeSections(
        rows: [ComposerScopeTreeRow],
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) -> [ScopePickerSection] {
        let listState = viewStore.scopeEditor.listState
        let currentScopeRows = rows.filter { row in
            switch row.kind {
            case .root, .base, .exception:
                true
            case .candidate:
                false
            }
        }
        let candidateRows = rows.filter { $0.kind == .candidate }
        let candidateFirst = isCandidateSectionPrimary(listState)

        var sections: [ScopePickerSection] = []

        if candidateFirst {
            appendCandidateSections(
                to: &sections,
                candidateRows: candidateRows,
                listState: listState,
                viewStore: viewStore,
            )
            appendCurrentScopeSection(to: &sections, currentScopeRows: currentScopeRows)
        } else {
            appendCurrentScopeSection(to: &sections, currentScopeRows: currentScopeRows)
            appendCandidateSections(
                to: &sections,
                candidateRows: candidateRows,
                listState: listState,
                viewStore: viewStore,
            )
        }

        return sections
    }

    private func appendCurrentScopeSection(
        to sections: inout [ScopePickerSection],
        currentScopeRows: [ComposerScopeTreeRow],
    ) {
        if !currentScopeRows.isEmpty {
            sections.append(
                ScopePickerSection(
                    id: "current-scope",
                    title: "Current scope",
                    rows: currentScopeRows,
                    showsNoResultsFooter: false,
                ),
            )
        }
    }

    private func appendCandidateSections(
        to sections: inout [ScopePickerSection],
        candidateRows: [ComposerScopeTreeRow],
        listState: ComposerScopeEditorListState,
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) {
        if case .childFolders = listState,
           let editingPath = viewStore.scopeEditor.editingPath
        {
            appendChildFolderCandidateSections(
                to: &sections,
                candidateRows: candidateRows,
                editingPath: editingPath,
            )
            return
        }

        if !candidateRows.isEmpty || listState.noResultsQuery != nil {
            sections.append(
                ScopePickerSection(
                    id: "candidate",
                    title: treeSectionTitle(for: listState),
                    rows: candidateRows,
                    showsNoResultsFooter: listState.noResultsQuery != nil,
                ),
            )
        }
    }

    private func appendChildFolderCandidateSections(
        to sections: inout [ScopePickerSection],
        candidateRows: [ComposerScopeTreeRow],
        editingPath: String,
    ) {
        let groupedRows = childFolderCandidateGroups(candidateRows: candidateRows, editingPath: editingPath)

        appendScopeSection(
            to: &sections,
            id: "child-folders",
            title: "Child folders",
            rows: groupedRows.childRows,
        )
        appendScopeSection(
            to: &sections,
            id: "parent-folder",
            title: "Parent folder",
            rows: groupedRows.parentRows,
        )
        appendScopeSection(
            to: &sections,
            id: "current-folder",
            title: "Current folder",
            rows: groupedRows.currentRows,
        )
        appendScopeSection(
            to: &sections,
            id: "sibling-folders",
            title: "Sibling folders",
            rows: groupedRows.siblingRows,
        )
        appendScopeSection(
            to: &sections,
            id: "related-folders",
            title: "Related folders",
            rows: groupedRows.relatedRows,
        )
    }

    private func appendScopeSection(
        to sections: inout [ScopePickerSection],
        id: String,
        title: String,
        rows: [ComposerScopeTreeRow],
    ) {
        guard !rows.isEmpty else { return }
        sections.append(
            ScopePickerSection(
                id: id,
                title: title,
                rows: rows,
                showsNoResultsFooter: false,
            ),
        )
    }

    private func childFolderCandidateGroups(
        candidateRows: [ComposerScopeTreeRow],
        editingPath: String,
    ) -> ChildFolderCandidateGroups {
        let normalizedEditingPath = ComposerScopeUtils.normalizeScopePath(editingPath)
        let normalizedParentPath = ComposerScopeUtils.normalizeScopePath(
            (normalizedEditingPath as NSString).deletingLastPathComponent,
        )

        var childRows: [ComposerScopeTreeRow] = []
        var parentRows: [ComposerScopeTreeRow] = []
        var currentRows: [ComposerScopeTreeRow] = []
        var siblingRows: [ComposerScopeTreeRow] = []
        var relatedRows: [ComposerScopeTreeRow] = []

        for row in candidateRows {
            let normalizedRowPath = ComposerScopeUtils.normalizeScopePath(row.path)
            let rowParentPath = ComposerScopeUtils.normalizeScopePath(
                (normalizedRowPath as NSString).deletingLastPathComponent,
            )

            if normalizedRowPath == normalizedEditingPath {
                currentRows.append(row)
            } else if normalizedRowPath == normalizedParentPath {
                parentRows.append(row)
            } else if rowParentPath == normalizedEditingPath {
                childRows.append(row)
            } else if rowParentPath == normalizedParentPath {
                siblingRows.append(row)
            } else {
                relatedRows.append(row)
            }
        }

        return ChildFolderCandidateGroups(
            childRows: childRows,
            parentRows: parentRows,
            currentRows: currentRows,
            siblingRows: siblingRows,
            relatedRows: relatedRows,
        )
    }

    private func isCandidateSectionPrimary(_ listState: ComposerScopeEditorListState) -> Bool {
        switch listState {
        case .searchResults, .noResults:
            true
        case .defaultCandidates, .childFolders:
            false
        }
    }

    private func makeScopeListItems(sections: [ScopePickerSection]) -> [ScopePickerListItem] {
        sections.enumerated().flatMap { index, section -> [ScopePickerListItem] in
            var items: [ScopePickerListItem] = []
            if index > 0 {
                items.append(.divider(id: "divider-\(section.id)"))
            }
            items.append(.header(id: "header-\(section.id)", title: section.title))
            items.append(
                contentsOf: section.rows.map { row in
                    .row(id: "row-\(section.id)-\(row.id)", row: row)
                },
            )
            if section.showsNoResultsFooter {
                items.append(.noResultsFooter(id: "footer-\(section.id)"))
            }
            return items
        }
    }

    @ViewBuilder
    private func scopeListItemView(
        _ item: ScopePickerListItem,
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) -> some View {
        switch item {
        case .divider:
            sectionDivider
                .padding(.vertical, 6)
        case let .header(_, title):
            scopeSectionHeader(title)
        case let .row(_, row):
            ScopeTreeRowView(
                row: row,
                colorScheme: colorScheme,
                applicationsIcon: Self.cachedApplicationsIcon,
                onBodyTap: { handleTreeRowBodyTap(row, viewStore: viewStore) },
                onAction: { action in
                    handleTreeRowAction(row, action: action, viewStore: viewStore)
                },
                actionAccessibilityIdentifier: { action in
                    ScopePickerAccessibilityID.treeAction(action, path: row.path)
                },
            )
            .accessibilityIdentifier(ScopePickerAccessibilityID.treeRow(path: row.path))
        case .noResultsFooter:
            noResultsFooter(viewStore.scopeEditor.listState)
        }
    }

    private func scopeSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary.opacity(0.85))
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func noResultsFooter(_ listState: ComposerScopeEditorListState) -> some View {
        if let message = listState.emptyStateMessage {
            VStack(alignment: .leading, spacing: 2) {
                Text("No Results")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if let recoveryMessage = listState.emptyStateRecoveryMessage {
                    Text(recoveryMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier(ScopePickerAccessibilityID.noResults)
        } else {
            EmptyView()
        }
    }

    private func treeSectionTitle(for listState: ComposerScopeEditorListState) -> String {
        switch listState {
        case .defaultCandidates:
            "Suggested locations"
        case .childFolders:
            "Nearby folders"
        case let .searchResults(query):
            "Search Results for \"\(query)\""
        case let .noResults(query):
            "No Results for \"\(query)\""
        }
    }

    private struct ScopePickerSection: Identifiable {
        let id: String
        let title: String
        let rows: [ComposerScopeTreeRow]
        let showsNoResultsFooter: Bool
    }

    private enum ScopePickerListItem: Identifiable {
        case divider(id: String)
        case header(id: String, title: String)
        case row(id: String, row: ComposerScopeTreeRow)
        case noResultsFooter(id: String)

        var id: String {
            switch self {
            case let .divider(id), let .header(id, _), let .row(id, _), let .noResultsFooter(id):
                id
            }
        }
    }

    private struct ChildFolderCandidateGroups {
        let childRows: [ComposerScopeTreeRow]
        let parentRows: [ComposerScopeTreeRow]
        let currentRows: [ComposerScopeTreeRow]
        let siblingRows: [ComposerScopeTreeRow]
        let relatedRows: [ComposerScopeTreeRow]
    }

    private func handleTreeRowBodyTap(
        _ row: ComposerScopeTreeRow,
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) {
        switch row.kind {
        case .base:
            store.send(.scopeEditorOpen(
                editingPath: row.path,
                favorites: viewStore.scopeEditor.favorites,
                backHistory: viewStore.scopeEditor.backHistory,
            ))
        case .candidate:
            if row.availableActions.count == 1,
               let primaryAction = row.availableActions.first,
               viewStore.scopeEditor.treeActionIntent(rowPath: row.path, action: primaryAction) != .none
            {
                handleTreeRowAction(row, action: primaryAction, viewStore: viewStore)
            }
        case .exception, .root:
            break
        }
    }

    private func handleTreeRowAction(
        _ row: ComposerScopeTreeRow,
        action: ComposerScopeTreeRowAvailableAction,
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) {
        switch viewStore.scopeEditor.treeActionIntent(rowPath: row.path, action: action) {
        case let .addBase(path):
            store.send(.candidateScope(.add(path: path)))
        case let .exclude(path):
            store.send(.exceptionScope(.exclude(path: path)))
        case let .removeBase(path):
            store.send(.currentScope(.remove(path: path)))
        case let .restoreException(path):
            store.send(.exceptionScope(.restore(path: path)))
        case .none:
            break
        }
    }
}
