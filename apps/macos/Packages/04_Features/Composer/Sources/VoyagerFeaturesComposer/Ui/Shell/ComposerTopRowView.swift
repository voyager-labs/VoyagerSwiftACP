import ComposableArchitecture
import HotSwiftUI
import SwiftUI
import VoyagerShared

struct ComposerTopRowView: View {
    @ObserveInjection private var injection

    let store: StoreOf<ComposerFeature>
    let colorScheme: ColorScheme
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
    let isOptionKeyPressed: Bool
    let onDiscardCollectionChanges: () -> Void

    @State var isComposeFieldFirstResponder: Bool = true
    @State var isStopHovering: Bool = false

    var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        WithViewStore(
            store,
            observe: { $0 },
            content: { viewStore in
                firstRow(viewStore: viewStore)
            },
        )
    }
}

private extension ComposerTopRowView {
    @ViewBuilder
    func firstRow(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let isLocked = viewStore.isLoadingSearch || viewStore.isFilteringInFlight
        HStack(spacing: 8) {
            ComposerChromeButton(
                isEnabled: viewStore.canUndo && !isLocked,
                colorScheme: colorScheme,
                action: { store.send(.undo) },
                label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(VoyagerDS.Typography.body)
                },
            )

            ComposerChromeButton(
                isEnabled: viewStore.canRedo && !isLocked,
                colorScheme: colorScheme,
                action: { store.send(.redo) },
                label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(VoyagerDS.Typography.body)
                },
            )

            textField(viewStore: viewStore, isLocked: isLocked)
                .frame(maxWidth: .infinity, alignment: .leading)

            ComposerChromeButton(
                isEnabled: canSaveCollection && !isLocked,
                colorScheme: colorScheme,
                action: { viewStore.send(.saveCollection) },
                label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(VoyagerDS.Typography.body)
                },
            )

            overflowMenu(viewStore: viewStore, isLocked: isLocked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 40)
        .accessibilityIdentifier("composer.inputRow")
    }

    func textField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        ZStack(alignment: .trailing) {
            queryInputField(viewStore: viewStore, isLocked: isLocked)

            if viewStore.isLoadingSearch || viewStore.isFilteringInFlight {
                stopButton(viewStore: viewStore)
            }
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder
    func stopButton(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let buttonBackground = Circle().fill(VoyagerDS.BrandSecondaryColor.c500)
        Button {
            if viewStore.isLoadingSearch {
                viewStore.send(.cancelSearch)
            } else {
                viewStore.send(.cancelFilters)
            }
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(.black)
                .frame(width: 16, height: 16)
                .background(buttonBackground)
        }
        .buttonStyle(.borderless)
        .background(
            Circle()
                .fill(isStopHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
                .frame(width: 20, height: 20),
        )
        .padding(.trailing, 8)
        .onHover { hovering in
            isStopHovering = hovering
        }
    }

    func queryInputField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        let placeholderText = "Describe the collection you want..."

        return ZStack(alignment: .leading) {
            if viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholderText)
                    .foregroundColor(.secondary)
                    .font(VoyagerDS.Typography.body)
                    .padding(.leading, 12)
            }

            FocusedTextField(
                text: viewStore.binding(get: \.text, send: ComposerFeature.Action.setText),
                isFirstResponder: Binding(
                    get: { isComposeFieldFirstResponder },
                    set: { isComposeFieldFirstResponder = $0 },
                ),
                onCommit: {
                    let trimmed = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { viewStore.send(.submit) }
                },
            )
            .font(VoyagerDS.Typography.body)
            .accessibilityIdentifier("composer.query.input")
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .padding(.trailing, 28)
            .disabled(isLocked)
        }
        .onSubmit {
            let trimmed = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { viewStore.send(.submit) }
        }
        .onChange(of: viewStore.isPresented) { presented in
            if presented {
                isComposeFieldFirstResponder = true
            }
        }
        .onChange(of: viewStore.focusRequestID) { _ in
            isComposeFieldFirstResponder = true
        }
    }

    @ViewBuilder
    func overflowMenu(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        let trimmedText = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRootScopeOnly = viewStore.isSemanticallyRootOnly
        let isAllEmpty = trimmedText.isEmpty && viewStore.conditions.isEmpty
            && (viewStore.scopeEditor.selection.legacyScopePaths.isEmpty || isRootScopeOnly)
        let isClearEnabled = !isLocked && !isAllEmpty
        let isDiscardActionEnabled = isDiscardEnabled && !isLocked
        let isSaveAsEnabled = canSaveCollection && !isLocked

        Menu {
            Button("Clear") {
                viewStore.send(.clearAll)
            }
            .disabled(!isClearEnabled)

            Button("Discard") {
                onDiscardCollectionChanges()
            }
            .disabled(!isDiscardActionEnabled)

            Divider()

            Button("Save As…") {
                viewStore.send(.saveCollectionAs)
            }
            .disabled(!isSaveAsEnabled)
        } label: {
            Image(systemName: "ellipsis")
                .font(VoyagerDS.Typography.body)
                .foregroundColor(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("More actions")
        .accessibilityIdentifier("composer.overflow.menu")
    }
}
