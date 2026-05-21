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
                    if !viewStore.scopeEditor.selection.isRootOnly {
                        includeSubfoldersRow(viewStore: viewStore)
                    }
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

    private func includeSubfoldersRow(
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) -> some View {
        IncludeSubfoldersRow(
            includeSubfolders: viewStore.scopeEditor.includeSubfolders,
            onTap: { store.send(.scopeEditorSetIncludeSubfolders(!$0)) },
        )
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

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                scopeSections(rows: rows, viewStore: viewStore)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func scopeSections(
        rows: [ComposerScopeTreeRow],
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) -> some View {
        let sections = makeScopeSections(rows: rows, listState: viewStore.scopeEditor.listState)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections.indices, id: \.self) { index in
                if index > 0 {
                    sectionDivider
                }

                scopeSectionView(section: sections[index], viewStore: viewStore)
                    .padding(.top, index == 0 ? 0 : 6)
            }
        }
        .accessibilityIdentifier(ScopePickerAccessibilityID.treeSection)
    }

    private var sectionDivider: some View {
        VoyagerDS.SystemColor.separator
            .frame(height: 1)
            .padding(.horizontal, 2)
            .opacity(0.8)
    }

    private func makeScopeSections(
        rows: [ComposerScopeTreeRow],
        listState: ComposerScopeEditorListState,
    ) -> [ScopePickerSection] {
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
            appendCandidateSection(to: &sections, candidateRows: candidateRows, listState: listState)
            appendCurrentScopeSection(to: &sections, currentScopeRows: currentScopeRows)
        } else {
            appendCurrentScopeSection(to: &sections, currentScopeRows: currentScopeRows)
            appendCandidateSection(to: &sections, candidateRows: candidateRows, listState: listState)
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
                    kind: .currentScope,
                    title: "Current scope",
                    rows: currentScopeRows,
                    showsNoResultsFooter: false,
                ),
            )
        }
    }

    private func appendCandidateSection(
        to sections: inout [ScopePickerSection],
        candidateRows: [ComposerScopeTreeRow],
        listState: ComposerScopeEditorListState,
    ) {
        if !candidateRows.isEmpty || listState.noResultsQuery != nil {
            sections.append(
                ScopePickerSection(
                    kind: .candidate,
                    title: treeSectionTitle(for: listState),
                    rows: candidateRows,
                    showsNoResultsFooter: listState.noResultsQuery != nil,
                ),
            )
        }
    }

    private func isCandidateSectionPrimary(_ listState: ComposerScopeEditorListState) -> Bool {
        switch listState {
        case .searchResults, .noResults:
            true
        case .defaultCandidates, .childFolders:
            false
        }
    }

    @ViewBuilder
    private func scopeSectionView(
        section: ScopePickerSection,
        viewStore: ViewStore<ViewState, ComposerFeature.Action>,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.85))
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.rows) { row in
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
                }

                if section.showsNoResultsFooter {
                    noResultsFooter(viewStore.scopeEditor.listState)
                }
            }
        }
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
        enum Kind: Hashable {
            case currentScope
            case candidate
        }

        let kind: Kind
        let title: String
        let rows: [ComposerScopeTreeRow]
        let showsNoResultsFooter: Bool

        var id: Kind { kind }
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
