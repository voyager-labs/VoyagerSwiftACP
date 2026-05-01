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
                        currentScopeRow(item: item, viewStore: viewStore)
                    }
                case .exceptionSlot:
                    ForEach(section.items, id: \.id) { item in
                        exceptionSlotRow(item: item)
                    }
                case .addableCandidates:
                    if section.items.isEmpty {
                        if case let .addableCandidates(listState) = section.kind,
                           let message = listState.emptyStateMessage
                        {
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
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
        case .exceptionSlot:
            "Exceptions"
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
            HStack(spacing: 8) {
                Button(action: {
                    handleCurrentScopeTap(currentItem, viewStore: viewStore)
                }, label: {
                    currentScopeLabel(currentItem)
                })
                .buttonStyle(.plain)

                Button {
                    store.send(.currentScope(.remove(path: currentItem.base.path)))
                } label: {
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
            ),
        )
    }

    private func exceptionSlotRow(item: ComposerScopeEditorSectionItem) -> some View {
        guard case let .exceptionSlot(slot) = item else {
            return AnyView(EmptyView())
        }

        let text = switch slot {
        case .empty:
            "No exceptions"
        case let .exceptionPresent(count):
            count == 1 ? "1 exception present" : "\(count) exceptions present"
        }

        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme).opacity(0.5)),
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
                addableCandidateLabel(candidate, isHovering: isHovering)
            })
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredPath = hovering ? candidate.path : nil
            },
        )
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

    private func currentScopeLabel(_ currentItem: ComposerScopeEditorCurrentItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(entryLoadingClient.displayName(currentItem.base.path))
                    .font(.system(size: 13, weight: currentItem.isEditingTarget ? .semibold : .regular))
                    .foregroundColor(.primary)
                if currentItem.isEditingTarget {
                    Text("Editing")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
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

    private func handleAddableCandidateTap(
        _ candidate: ComposerScopeEditorCandidateItem,
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
    ) {
        switch viewStore.scopeEditor.entryMode {
        case .edit:
            if let oldPath = viewStore.scopeEditor.editingPath {
                store.send(.currentScope(.replace(oldPath: oldPath, newPath: candidate.path)))
            } else {
                store.send(.candidateScope(.add(path: candidate.path)))
            }
        case .add:
            store.send(.candidateScope(.add(path: candidate.path)))
        }
    }

    private func addableCandidateLabel(
        _ candidate: ComposerScopeEditorCandidateItem,
        isHovering: Bool,
    ) -> some View {
        HStack(spacing: 8) {
            if candidate.path == "/Applications", let appIcon = applicationsIcon() {
                Image(nsImage: appIcon)
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
                Text(candidate.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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

    private func applicationsIcon() -> NSImage? {
        let appIcon = NSImage(
            contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns",
        )
        appIcon?.isTemplate = true
        return appIcon
    }
}
