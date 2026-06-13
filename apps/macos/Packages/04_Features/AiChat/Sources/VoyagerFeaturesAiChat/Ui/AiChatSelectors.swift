import ComposableArchitecture
import SwiftUI

struct AiChatModelSelectorButton: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState

    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
            if isPresented {
                store.send(.modelSelectorTapped)
            } else {
                store.send(.modelSelectorDismissed)
            }
        } label: {
            AiChatHoverTextAffordance(
                title: AiChatSelectorLabels.modelSelectorLabel(for: state),
                systemName: "chevron.down",
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AiChatModelSelectorDropdown(
                store: store,
                state: state,
                isPresented: $isPresented,
            )
            .onDisappear {
                store.send(.modelSelectorDismissed)
            }
        }
        .onChange(of: state.modelSelectorIsDisabled) { isDisabled in
            guard isDisabled, isPresented else { return }
            isPresented = false
            store.send(.modelSelectorDismissed)
        }
        .disabled(state.modelSelectorIsDisabled)
        .accessibilityLabel("Model")
        .accessibilityValue(AiChatSelectorLabels.modelSelectorAccessibilityValue(for: state))
    }
}

private struct AiChatModelSelectorDropdown: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState

    @Binding var isPresented: Bool

    var body: some View {
        AiChatSelectorPopoverContainer {
            switch state.modelSelectorContentState {
            case let .loaded(sections):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            modelSection(section, index: index)
                        }
                    }
                }
                .frame(maxHeight: AiChatModelSelectorLayout.contentMaxHeight)

            case let .loading(status),
                 let .empty(status),
                 let .failed(status),
                 let .unsupported(status):
                AiChatModelSelectorStatusRow(store: store, status: status)
            }
        }
    }

    private func modelSection(
        _ section: AiChatModelCatalogSectionDisplayModel,
        index: Int,
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if index > 0 {
                Divider()
                    .padding(.vertical, 4)
            }

            Text(section.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, index == 0 ? 0 : 2)

            ForEach(section.rows) { row in
                AiChatModelSelectorRow(
                    store: store,
                    row: row,
                    isPresented: $isPresented,
                )
            }
        }
    }
}

struct AiChatSelectorPopoverContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(8)
            .frame(width: Self.width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1),
            )
            .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    private static var width: CGFloat {
        260
    }
}

private struct AiChatModelSelectorStatusRow: View {
    let store: StoreOf<AiChatFeature>
    let status: AiChatModelSelectorStatusDisplayModel

    var body: some View {
        Button {
            store.send(.modelSelectorTapped)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(status.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel(status.title)
        .accessibilityValue(status.detail)
    }
}

private struct AiChatModelSelectorRow: View {
    let store: StoreOf<AiChatFeature>
    let row: AiChatModelCatalogRowDisplayModel

    @Binding var isPresented: Bool

    var body: some View {
        Button {
            store.send(.selectedModelChanged(row.handle))
            store.send(.modelSelectorDismissed)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(row.title)
                    .font(.system(size: 13, weight: row.isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if row.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(row.isSelected ? Color.primary.opacity(0.08) : Color.clear),
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.title)
        .accessibilityHint(row.providerBadge ?? "")
    }
}

enum AiChatModelSelectorLayout {
    static let contentMaxHeight: CGFloat = 280

    static func usesScrollableContent(for contentState: AiChatModelSelectorContentState) -> Bool {
        if case .loaded = contentState {
            return true
        }

        return false
    }
}

enum AiChatSelectorLabels {
    static func modelSelectorLabel(for state: AiChatState) -> String {
        if let selectedModel = state.selectedModelDisplayModel {
            return selectedModel.title
        }

        return switch state.modelListState {
        case .loading, .idle:
            "Loading"
        case .failed:
            "Unavailable"
        case .empty:
            "No models"
        case .loaded:
            "Model"
        }
    }

    static func modelSelectorAccessibilityValue(for state: AiChatState) -> String {
        switch state.modelSelectorContentState {
        case .loading:
            "Loading"
        case .empty:
            "No models"
        case .failed:
            "Unavailable"
        case .unsupported:
            "Unsupported"
        case .loaded:
            state.selectedModelDisplayModel?.title ?? "No selection"
        }
    }

    static func thinkingSelectorLabel(for state: AiChatState, input: AiChatInputDisplayModel) -> String {
        guard let model = state.resolvedSelectedModel else {
            return "Thinking"
        }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return "Unavailable"
        case .effort, .adaptive, .tokenBudget:
            return state.selectedThinking.map(AiChatState.thinkingLabel(for:)) ?? input.effortLabel
        }
    }

    static func thinkingSelectorAccessibilityValue(for state: AiChatState) -> String {
        guard let model = state.resolvedSelectedModel else { return "No selection" }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return "Unavailable"
        case .effort, .adaptive, .tokenBudget:
            return state.selectedThinking.map(AiChatState.thinkingLabel(for:))
                ?? AiChatState.defaultThinkingLabel(for: model.thinkingCapability)
        }
    }

    static func thinkingSelectorIsDisabled(for state: AiChatState) -> Bool {
        guard let model = state.resolvedSelectedModel else { return true }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return true
        case let .effort(values, _):
            return values.isEmpty
        case let .adaptive(effortValues, _):
            return effortValues.isEmpty
        case let .tokenBudget(min, max, _):
            return min > max
        }
    }
}
