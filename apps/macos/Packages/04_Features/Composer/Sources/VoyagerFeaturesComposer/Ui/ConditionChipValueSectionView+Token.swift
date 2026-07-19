import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerEntitiesTag
import VoyagerShared

extension ConditionChipValueSectionView {
    func tokenValueButton(
        contract _: Condition.ValueContract,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let popoverBinding = Binding<Bool>(
            get: {
                valueViewStore.isPresented &&
                    valueViewStore.editingIndex == nil
            },
            set: { show in
                guard !show else { return }
                valuePickerStore.send(.setPresented(false))
            },
        )

        return Group {
            if ComposerPickerHostPolicy.host(for: .token) == .anchoredDropdown {
                ComposerAnchoredDropdown(
                    isPresented: popoverBinding,
                    dropdownAccessibilityIdentifier: "composer.token.dropdown",
                ) {
                    Button {
                        prepare(editingIndex: nil, includeDisplayState: false)
                    } label: {
                        tokenButtonLabel()
                    }
                    .contentShape(Rectangle())
                    .frame(minWidth: 32, minHeight: 22, alignment: .center)
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isValueHovering = hovering
                    }
                } content: {
                    tokenPopoverContent(valueViewStore: valueViewStore)
                }
            }
        }
    }

    private func tokenButtonLabel() -> some View {
        Text(ConditionTokenPresentation.buttonText(values: condition.values ?? []))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor((condition.values?.isEmpty ?? true) ? .secondary.opacity(0.7) : .primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isValueHovering
                            ?
                            (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black.opacity(hoverFillOpacity))
                            : Color.white.opacity(0.0001),
                    ),
            )
    }

    func tokenPopoverContent(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let tokens = ConditionValueNormalizer.deduplicatedTokenValues(valueViewStore.values)
        let finderTagOptions = valueViewStore.finderTagListState?.options ?? []
        let filteredFinderTags = ConditionTagSuggestions.filteredFinderTags(
            selectedTokens: tokens,
            finderTagOptions: finderTagOptions,
            query: valueViewStore.tokenInput,
        )
        let hasError = valueViewStore.errorMessage != nil

        return VStack(alignment: .leading, spacing: 8) {
            tokenInputRow(tokens: tokens, valueViewStore: valueViewStore)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            hasError
                                ? Color.red.opacity(0.85)
                                : (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.18)),
                            lineWidth: 1,
                        ),
                )

            if valueViewStore.finderTagListState != nil {
                finderTagListSection(tags: filteredFinderTags, query: valueViewStore.tokenInput)
            }

            if let error = valueViewStore.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(VoyagerDS.Surface.popoverBackground(for: isDark ? .dark : .light)),
        )
    }

    func tokenInputRow(
        tokens: [String],
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tokens, id: \.self) { token in
                    tokenChip(token)
                }

                TextField(
                    "Value",
                    text: valueViewStore.binding(
                        get: \.tokenInput,
                        send: ValuePickerFeature.Action.setTokenInput,
                    ),
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .accessibilityIdentifier("composer.token.input")
                .frame(minWidth: 70, alignment: .leading)
                .onSubmit {
                    handleTokenSubmit(valueViewStore)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    func tokenChip(_ token: String) -> some View {
        HStack(spacing: 4) {
            Text(token)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)

            Button {
                valuePickerStore.send(.removeToken(token))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)),
        )
    }

    func handleTokenSubmit(
        _ valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) {
        let token = valueViewStore.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            valuePickerStore.send(.commit)
            return
        }
        valuePickerStore.send(.appendToken(token))
    }

    func finderTagListSection(tags: [Tag], query: String) -> some View {
        ScrollView {
            if tags.isEmpty {
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No tags" : "No matching tags")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tags, id: \.name) { tag in
                        Button {
                            valuePickerStore.send(.appendToken(tag.name))
                        } label: {
                            HStack(spacing: 8) {
                                ColorDotView(nsColor: tag.tagColor.nsColor, size: 10)
                                Text(tag.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 164)
        .padding(.vertical, 2)
    }
}
