import ComposableArchitecture
import SwiftUI
import VoyagerShared

struct ComposerTopRowView: View {
    let store: StoreOf<ComposerFeature>
    let colorScheme: ColorScheme
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
    let isOptionKeyPressed: Bool
    let onDiscardCollectionChanges: () -> Void

    @State var isComposeFieldFirstResponder: Bool = true
    @State var isUndoHovering: Bool = false
    @State var isRedoHovering: Bool = false
    @State var isStopHovering: Bool = false
    @State var isSubmitHovering: Bool = false
    @State var isClearHovering: Bool = false
    @State var isSaveHovering: Bool = false

    var isDark: Bool { colorScheme == .dark }

    var body: some View {
        WithViewStore(
            store,
            observe: { $0 },
            content: { viewStore in
                firstRow(viewStore: viewStore)
            }
        )
    }
}

private extension ComposerTopRowView {
    @ViewBuilder
    func firstRow(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let isLocked = viewStore.isLoadingSearch || viewStore.isFilteringInFlight
        HStack(spacing: 8) {
            undoButton(viewStore: viewStore, isLocked: isLocked)
            redoButton(viewStore: viewStore, isLocked: isLocked)
            textField(viewStore: viewStore, isLocked: isLocked)
                .frame(maxWidth: .infinity, alignment: .leading)
            clearButton(viewStore: viewStore, isLocked: isLocked)
            saveButton(viewStore: viewStore, isLocked: isLocked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 40)
    }

    @ViewBuilder
    func undoButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool
    ) -> some View {
        let isEnabled = viewStore.canUndo && !isLocked
        Button {
            store.send(.undo)
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEnabled && isUndoHovering ? VoyagerDS.Interaction
                            .controlHoverFill(for: colorScheme) : .clear)
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
        .onHover { hovering in
            isUndoHovering = hovering
        }
    }

    @ViewBuilder
    func redoButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool
    ) -> some View {
        let isEnabled = viewStore.canRedo && !isLocked
        Button {
            store.send(.redo)
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEnabled && isRedoHovering ? VoyagerDS.Interaction
                            .controlHoverFill(for: colorScheme) : .clear)
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
        .onHover { hovering in
            isRedoHovering = hovering
        }
    }

    func textField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool
    ) -> some View {
        ZStack(alignment: .trailing) {
            let isSubmitDisabled = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            queryInputField(viewStore: viewStore, isSubmitDisabled: isSubmitDisabled, isLocked: isLocked)

            if viewStore.isLoadingSearch || viewStore.isFilteringInFlight {
                stopButton(viewStore: viewStore)
            } else {
                submitButton(viewStore: viewStore, isLocked: isLocked, isSubmitDisabled: isSubmitDisabled)
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
                .frame(width: 20, height: 20)
        )
        .padding(.trailing, 8)
        .onHover { hovering in
            isStopHovering = hovering
        }
    }

    @ViewBuilder
    func submitButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
        isSubmitDisabled: Bool
    ) -> some View {
        let submitButtonBackground = Circle().fill(
            isSubmitDisabled
                ? VoyagerDS.BrandSecondaryColor.c500.opacity(0.5)
                : VoyagerDS.BrandSecondaryColor.c500
        )

        Button {
            viewStore.send(.submit)
        } label: {
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(isSubmitDisabled ? .secondary : .black)
                .frame(width: 16, height: 16)
                .background(submitButtonBackground)
        }
        .buttonStyle(.borderless)
        .disabled(isSubmitDisabled || isLocked)
        .background(
            Circle()
                .fill(!isSubmitDisabled && !isLocked && isSubmitHovering
                    ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme)
                    : .clear)
                .frame(width: 20, height: 20)
        )
        .background(
            Circle()
                .fill(
                    isSubmitDisabled
                        ? Color(red: 0.843, green: 0.714, blue: 0.322).opacity(0.5)
                        : Color(red: 0.843, green: 0.714, blue: 0.322)
                )
                .allowsHitTesting(false)
        )
        .padding(.trailing, 8)
        .onHover { hovering in
            isSubmitHovering = hovering
        }
    }

    func queryInputField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isSubmitDisabled _: Bool,
        isLocked: Bool
    ) -> some View {
        let placeholderText = "Describe the collection you want..."

        return ZStack(alignment: .leading) {
            if viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholderText)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .padding(.leading, 12)
            }

            FocusedTextField(
                text: viewStore.binding(get: \.text, send: ComposerFeature.Action.setText),
                isFirstResponder: Binding(
                    get: { isComposeFieldFirstResponder },
                    set: { isComposeFieldFirstResponder = $0 }
                ),
                onCommit: {
                    let trimmed = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { viewStore.send(.submit) }
                }
            )
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .padding(.trailing, 28)
            .disabled(isLocked)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(VoyagerDS.Surface.inputBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoyagerDS.Surface.inputBorder(for: colorScheme), lineWidth: 1)
        )
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
}

private extension ComposerTopRowView {
    func clearButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool
    ) -> some View {
        let trimmedText = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRootScopeOnly = viewStore.isSemanticallyRootOnly
        let isAllEmpty = trimmedText.isEmpty && viewStore.conditions.isEmpty
            && (viewStore.scopeEditor.selection.legacyScopePaths.isEmpty || isRootScopeOnly)
        let isDiscard = isDiscardEnabled
        let isEnabled = isDiscard ? !isLocked : (!isLocked && !isAllEmpty)

        return Button {
            if isDiscard {
                onDiscardCollectionChanges()
            } else {
                viewStore.send(.clearAll)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.square")
                Text(isDiscard ? "Discard" : "Clear")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isEnabled && isClearHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
                .allowsHitTesting(false)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            isClearHovering = hovering
        }
    }

    func saveButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool
    ) -> some View {
        let isEnabled = canSaveCollection && !isLocked
        let isSaveAs = !isTemporaryCollection && isOptionKeyPressed

        return Button {
            viewStore.send(isSaveAs ? .saveCollectionAs : .saveCollection)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSaveAs ? "square.and.arrow.down" : "tray.and.arrow.down")
                Text(isSaveAs ? "Save As" : "Save")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isEnabled && isSaveHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
                .allowsHitTesting(false)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            isSaveHovering = hovering
        }
    }
}
