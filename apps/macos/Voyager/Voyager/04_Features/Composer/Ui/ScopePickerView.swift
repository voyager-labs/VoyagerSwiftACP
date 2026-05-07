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
                if !viewStore.scopeEditor.selection.isRootOnly {
                    includeSubfoldersRow(viewStore: viewStore)
                }
                if let display = viewStore.lastScopeChangeFeedbackDisplay {
                    scopeChangeFeedbackBanner(display)
                }
                listContent(viewStore: viewStore)
            }
            .frame(width: 260)
            .frame(maxHeight: 420)
            .background(VoyagerDS.Surface.popoverBackground(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
            )
            .shadow(
                color: VoyagerDS.Shadow.popoverColor(for: colorScheme),
                radius: VoyagerDS.Shadow.popoverRadius,
                y: VoyagerDS.Shadow.popoverYOffset,
            )
            .onAppear {
                isSearchFocused = true
            }
        })
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
                case .addableCandidates:
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
    }

    private func sectionTitle(for kind: ComposerScopeEditorSection.Kind) -> String {
        switch kind {
        case .currentScopes:
            "Current Scopes"
        case let .addableCandidates(listState):
            listState.candidateSectionTitle
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
        return AnyView(
            Button(action: {
                handleAddableCandidateTap(candidate, viewStore: viewStore)
            }, label: {
                AddableCandidateRow(
                    candidate: candidate,
                    isHovering: isHovering,
                    colorScheme: colorScheme,
                    applicationsIcon: applicationsIcon(),
                )
            })
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredPath = hovering ? candidate.path : nil
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
}

private struct IncludeSubfoldersRow: View {
    let includeSubfolders: Bool
    let onTap: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onTap(includeSubfolders)
            } label: {
                HStack(spacing: 10) {
                    Text("Include subfolders")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: includeSubfolders ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(includeSubfolders ? .accentColor : .secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            VoyagerDS.SystemColor.separator
                .frame(height: 1)
        }
    }
}

private struct CurrentScopeRow: View {
    let currentItem: ComposerScopeEditorCurrentItem
    let colorScheme: ColorScheme
    let displayName: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 13, weight: currentItem.isEditingTarget ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let exceptionSummary = currentItem.exceptionSummaryText {
                            statusBadge(text: exceptionSummary)
                        }

                        if currentItem.isEditingTarget {
                            statusBadge(text: "Editing", subtle: true)
                        }
                    }

                    Text(currentItem.base.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(VoyagerDS.Surface.chipItemBorder(for: colorScheme), lineWidth: 0.5),
        )
    }

    private func statusBadge(text: String, subtle: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        subtle
                            ? VoyagerDS.Surface.chipItemBackground(for: colorScheme)
                            : VoyagerDS.Interaction.hoverFill(for: colorScheme),
                    ),
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ExceptionRow: View {
    let exception: ComposerScopeEditorExceptionItem
    let colorScheme: ColorScheme
    let displayName: String
    let onRestore: () -> Void

    private var text: String {
        displayName
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Text("Excluded")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text(exception.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button(action: onRestore) {
                Text("Restore")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme).opacity(0.5)),
        )
    }
}

private struct AddableCandidateRow: View {
    let candidate: ComposerScopeEditorCandidateItem
    let isHovering: Bool
    let colorScheme: ColorScheme
    let applicationsIcon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            if candidate.path == "/Applications", let applicationsIcon {
                Image(nsImage: applicationsIcon)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: candidate.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let secondary = candidate.secondaryText {
                    Text(secondary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
        )
    }
}
