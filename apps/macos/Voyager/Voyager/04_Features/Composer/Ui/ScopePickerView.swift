import AppKit
import ComposableArchitecture
import SwiftUI

struct ScopePickerView: View {
    let store: StoreOf<ComposerFeature>

    @State private var hoveredPath: String?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme)
    private var colorScheme
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
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
        })
    }
}

private extension ScopePickerView {
    private func currentSummaryRow(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
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
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
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
    private func listContent(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let sections = viewStore.scopeEditor.sections()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    sectionView(section: section, viewStore: viewStore)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func sectionView(
        section: ComposerScopeEditorSection,
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sectionTitle(for: section.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                switch section.kind {
                case .currentScopes:
                    ForEach(section.items, id: \.id) { item in
                        switch item {
                        case .currentScope:
                            currentScopeRow(item: item, viewStore: viewStore)
                        case .exceptionScope:
                            exceptionRow(item: item, viewStore: viewStore)
                        case .addableCandidate:
                            EmptyView()
                        }
                    }
                case let .addableCandidates(listState):
                    parentContextRow(for: listState)
                    if section.items.isEmpty {
                        addableCandidatesEmptyState(for: section.kind)
                    } else {
                        ForEach(section.items, id: \.id) { item in
                            addableCandidateRow(item: item, viewStore: viewStore)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier(sectionAccessibilityIdentifier(for: section.kind))
    }

    private func sectionTitle(for kind: ComposerScopeEditorSection.Kind) -> String {
        switch kind {
        case .currentScopes:
            "Current Scopes"
        case let .addableCandidates(listState):
            listState.candidateSectionTitle
        }
    }

    @ViewBuilder
    private func parentContextRow(for listState: ComposerScopeEditorListState) -> some View {
        if case let .childFolders(parentPath) = listState {
            ScopeEditorParentContextRow(
                displayName: entryLoadingClient.displayName(parentPath),
                path: parentPath,
            )
        }
    }

    private func currentScopeRow(
        item: ComposerScopeEditorSectionItem,
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) -> some View {
        guard case let .currentScope(currentItem) = item else {
            return AnyView(EmptyView())
        }

        return AnyView(
            CurrentScopeRow(
                currentItem: currentItem,
                colorScheme: colorScheme,
                displayName: entryLoadingClient.displayName(currentItem.base.path),
                removeAccessibilityIdentifier: ScopePickerAccessibilityID.directRemove(path: currentItem.base.path),
                removeAccessibilityLabel: "Remove direct scope rule for \(entryLoadingClient.displayName(currentItem.base.path))",
                onTap: { handleCurrentScopeTap(currentItem, viewStore: viewStore) },
                onRemove: { store.send(.currentScope(.remove(path: currentItem.base.path))) },
            ),
        )
    }

    private func exceptionRow(
        item: ComposerScopeEditorSectionItem,
        viewStore _: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) -> some View {
        guard case let .exceptionScope(exception) = item else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ExceptionRow(
                exception: exception,
                colorScheme: colorScheme,
                displayName: entryLoadingClient.displayName(exception.path),
                restoreAccessibilityIdentifier: ScopePickerAccessibilityID.restore(path: exception.path),
                restoreAccessibilityLabel: "Restore excluded scope \(entryLoadingClient.displayName(exception.path))",
                onRestore: { store.send(.restoreScope(path: exception.path)) },
            ),
        )
    }

    private func addableCandidateRow(
        item: ComposerScopeEditorSectionItem,
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) -> some View {
        guard case let .addableCandidate(candidate) = item else {
            return AnyView(EmptyView())
        }

        let isHovering = hoveredPath == candidate.path
        let selectionIntent = viewStore.scopeEditor.candidateSelectionIntent(for: candidate.path)
        let identifier = candidateAccessibilityIdentifier(for: selectionIntent, candidate: candidate)
        let actionKind = candidateActionKind(for: selectionIntent)
        let button = Button(action: {
            handleAddableCandidateTap(candidate, viewStore: viewStore)
        }, label: {
            AddableCandidateRow(
                candidate: candidate,
                isHovering: isHovering,
                colorScheme: colorScheme,
                applicationsIcon: applicationsIcon(),
                actionKind: actionKind,
                accessibilityIdentifier: identifier,
            )
        })
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPath = hovering ? candidate.path : nil
        }

        return AnyView(
            Group {
                if let identifier {
                    button.accessibilityIdentifier(identifier)
                } else {
                    button
                }
            },
        )
    }

    @ViewBuilder
    private func addableCandidatesEmptyState(for kind: ComposerScopeEditorSection.Kind) -> some View {
        if case let .addableCandidates(listState) = kind,
           let message = listState.emptyStateMessage
        {
            VStack(alignment: .leading, spacing: 2) {
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

    private func handleCurrentScopeTap(
        _ currentItem: ComposerScopeEditorCurrentItem,
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) {
        let editingPath = currentItem.isEditingTarget ? nil : currentItem.base.path
        store.send(.scopeEditorOpen(
            editingPath: editingPath,
            favorites: viewStore.scopeEditor.favorites,
            backHistory: viewStore.scopeEditor.backHistory,
        ))
    }

    private func handleAddableCandidateTap(
        _ candidate: ComposerScopeEditorCandidateItem,
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) {
        switch viewStore.scopeEditor.candidateSelectionIntent(for: candidate.path) {
        case let .add(path):
            store.send(.candidateScope(.add(path: path)))
        case let .replace(oldPath, newPath):
            store.send(.currentScope(.replace(oldPath: oldPath, newPath: newPath)))
        case let .exclude(path):
            store.send(.exceptionScope(.exclude(path: path)))
        }
    }

    private func applicationsIcon() -> NSImage? {
        let appIcon = NSImage(
            contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns",
        )
        appIcon?.isTemplate = true
        return appIcon
    }

    private func sectionAccessibilityIdentifier(for kind: ComposerScopeEditorSection.Kind) -> String {
        switch kind {
        case .currentScopes:
            ScopePickerAccessibilityID.currentSection
        case .addableCandidates:
            ScopePickerAccessibilityID.candidatesSection
        }
    }

    private func candidateActionKind(for intent: ScopeCandidateIntent) -> ScopeEditorCandidateRowActionKind {
        switch intent {
        case .add:
            .include
        case .replace:
            .replace
        case .exclude:
            .exclude
        }
    }

    private func candidateAccessibilityIdentifier(
        for intent: ScopeCandidateIntent,
        candidate: ComposerScopeEditorCandidateItem,
    ) -> String? {
        switch intent {
        case .add, .replace:
            nil
        case .exclude:
            ScopePickerAccessibilityID.exclude(path: candidate.path)
        }
    }
}

private enum ScopePickerPresentationMetrics {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 520
}

private enum ScopePickerAccessibilityID {
    static let surface = "scopeEditor.surface"
    static let searchField = "scopeEditor.searchField"
    static let currentSummary = "scopeEditor.currentSummary"
    static let currentSection = "scopeEditor.currentSection"
    static let candidatesSection = "scopeEditor.candidatesSection"
    static let noResults = "scopeEditor.noResults"
    static let feedbackBanner = "scopeEditor.feedbackBanner"

    static func directRemove(path: String) -> String {
        "scopeEditor.row.directRemove.\(slug(for: path))"
    }

    static func exclude(path: String) -> String {
        "scopeEditor.row.exclude.\(slug(for: path))"
    }

    static func restore(path: String) -> String {
        "scopeEditor.row.restore.\(slug(for: path))"
    }

    private static func slug(for path: String) -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        let mapped = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(mapped).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
