import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection

struct AiSettingsView: View {
    enum ModelSettingsEditor: Hashable {
        case defaultChat
        case collectionSearch
    }

    static let aiModelSettingsSectionTitle = "AI Model Settings"
    static let defaultChatSummaryAccessibilityLabel = "Default Chat Settings"
    static let collectionSummaryAccessibilityLabel = "Collection Search Settings"
    static let defaultChatProviderAccessibilityLabel = "Default Chat Provider"
    static let defaultChatModelAccessibilityLabel = "Default Chat Model"
    static let defaultChatThinkingAccessibilityLabel = "Default Chat Thinking"
    static let resetChatDefaultsAccessibilityLabel = "Reset Chat Defaults"
    static let notConfiguredSummaryText = "Not configured"
    static let connectionGuidanceText = "Connect an AI provider to configure AI model settings."
    static let collectionSearchAutomaticSummary =
        "Automatic · Last-used provider first · First compatible model"
    static let collectionSearchAutoProviderSummary = "Auto provider (last-used available first at runtime)"
    static let collectionSearchAutoModelSummary = "Auto model (first compatible at runtime)"
    static let defaultChatFooterText =
        "Applies only to new conversations. " +
        "Existing conversations and Collection Search are not affected."
    static let collectionSearchFooterText =
        "These preferences are stored locally and used by collection search only."
    static let collectionSearchAutoExplanationText =
        "Auto uses the last-used available provider first and the first compatible model at runtime."

    @State private var expandedEditors: Set<ModelSettingsEditor> = []

    let store: StoreOf<AiSettingsFeature>

    private var thinkingOptions: [CollectionSearchAIThinkingOption] {
        let options = store.collectionSearchThinkingOptions
        if !options.isEmpty { return options }

        var fallback = [CollectionSearchAIThinkingOption(selection: nil, title: "Provider default")]
        if let current = store.collectionSearchThinkingSelection {
            fallback.append(CollectionSearchAIThinkingOption(
                selection: current,
                title: Self.thinkingTitle(for: current),
            ))
        }
        return fallback
    }

    var body: some View {
        Form {
            Section {
                // bootstrap 단계와 무관하게 rows는 항상 렌더링.
                // `.idle` / `.loading` 에서도 catalogRows가 즉시 표시되어
                // first paint가 spinner-only로 대체되지 않는다.
                // `.failed`인 경우 retry 안내를 rows 위에 supplemental로 표시.
                if store.bootstrapPhase == .failed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Failed to load AI connections.")
                        Button("Retry") {
                            store.send(.retryBootstrapTapped)
                        }
                    }
                }

                ForEach(store.scope(state: \.rows, action: \.row)) { rowStore in
                    AiConnectionRowView(store: rowStore)
                }
            } header: {
                Text("AI Connections")
            } footer: {
                Text("Connect AI providers to enable intelligent features in Voyager.")
                    .font(.footnote)
            }

            Section {
                DisclosureGroup(
                    isExpanded: disclosureBinding(for: .defaultChat),
                    content: { defaultChatEditor },
                    label: {
                        settingsSummaryLabel(
                            title: "Default Chat",
                            summary: defaultChatSummaryText,
                        )
                    },
                )
                .accessibilityLabel(Self.defaultChatSummaryAccessibilityLabel)
                .accessibilityValue(defaultChatSummaryText)

                DisclosureGroup(
                    isExpanded: disclosureBinding(for: .collectionSearch),
                    content: { collectionSearchEditor },
                    label: {
                        settingsSummaryLabel(
                            title: "Collection Search",
                            summary: collectionSearchSummaryText,
                        )
                    },
                )
                .accessibilityLabel(Self.collectionSummaryAccessibilityLabel)
                .accessibilityValue(collectionSearchSummaryText)
            } header: {
                Text(Self.aiModelSettingsSectionTitle)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            store.send(.onAppear)
        }
    }

    @ViewBuilder private var defaultChatEditor: some View {
        if !store.hasConnectedProviders {
            connectionGuidance
        }

        Picker("Provider", selection: Binding(
            get: { store.chatDefaultSettings.provider },
            set: { selection in
                if let selection {
                    store.send(.chatProviderChanged(selection))
                }
            },
        )) {
            Text("Select a provider").tag(PersistedAIProviderSelection?.none)
            ForEach(store.connectedProviderDescriptors, id: \.provider) { descriptor in
                Text(descriptor.displayName).tag(Optional(PersistedAIProviderSelection(
                    rawValue: descriptor.provider.rawValue,
                )))
            }
            if let selection = store.chatDefaultSettings.provider,
               store.chatSelectedProviderIsUnavailable
            {
                Text(Self.unavailableLabel(selection.rawValue))
                    .tag(Optional(selection))
                    .disabled(true)
            }
        }
        .accessibilityLabel(Self.defaultChatProviderAccessibilityLabel)

        Picker("Model", selection: Binding(
            get: { store.chatDefaultSettings.model },
            set: { selection in
                if let selection {
                    store.send(.chatModelChanged(selection))
                }
            },
        )) {
            Text(chatModelPlaceholder).tag(PersistedAIModelSelection?.none)
            ForEach(store.chatAvailableModels, id: \.id) { model in
                Text(model.displayName).tag(Optional(PersistedAIModelSelection(
                    providerRawValue: model.provider.rawValue,
                    modelRawValue: model.rawModelID,
                )))
            }
            if let selection = store.chatDefaultSettings.model,
               store.chatSelectedModelIsUnavailable
            {
                Text(Self.unavailableLabel(selection.modelRawValue))
                    .tag(Optional(selection))
                    .disabled(true)
            }
        }
        .disabled(!chatCanSelectModel)
        .accessibilityLabel(Self.defaultChatModelAccessibilityLabel)

        Picker("Thinking", selection: Binding(
            get: { store.chatDefaultSettings.thinking },
            set: { selection in
                store.send(.chatThinkingChanged(Self.thinkingSelection(from: selection)))
            },
        )) {
            ForEach(store.chatThinkingOptions) { option in
                Text(option.title).tag(Self.persistedThinking(from: option.selection))
            }
            if store.chatThinkingIsUnavailable {
                Text(Self.unavailableLabel(Self.thinkingTitle(for: store.chatDefaultSettings.thinking)))
                    .tag(store.chatDefaultSettings.thinking)
                    .disabled(true)
            }
        }
        .disabled(store.chatSelectedModel == nil || store.chatThinkingOptions.count <= 1)
        .accessibilityLabel(Self.defaultChatThinkingAccessibilityLabel)

        HStack {
            Button("Reset to Defaults") {
                store.send(.chatResetTapped)
            }
            .accessibilityLabel(Self.resetChatDefaultsAccessibilityLabel)
            Spacer()
        }

        VStack(alignment: .leading) {
            Text(Self.defaultChatFooterText)
            if store.chatDefaultSettings.provider != nil,
               let error = store.chatModelLoadError
            {
                Text(error)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var collectionSearchEditor: some View {
        if !store.hasConnectedProviders {
            connectionGuidance
        }

        Picker("Provider", selection: Binding(
            get: { store.collectionSearchSettings.provider },
            set: { store.send(.collectionSearchProviderChanged($0)) },
        )) {
            Text("Auto").tag(CollectionSearchAIProviderPreference.auto)
            ForEach(store.connectedProviderDescriptors, id: \.provider) { descriptor in
                Text(descriptor.displayName).tag(
                    CollectionSearchAIProviderPreference.specific(descriptor.provider.rawValue),
                )
            }
        }

        Picker("Model", selection: Binding(
            get: { store.collectionSearchSettings.model },
            set: { store.send(.collectionSearchModelChanged($0)) },
        )) {
            Text("Auto").tag(CollectionSearchAIModelPreference.auto)
            if let provider = store.collectionSearchSelectedProvider,
               let models = store.collectionSearchModelsByProvider[provider]
            {
                ForEach(models, id: \.id) { model in
                    Text(model.displayName).tag(
                        CollectionSearchAIModelPreference.specific(
                            provider: provider.rawValue,
                            model: model.rawModelID,
                        ),
                    )
                }
            } else if case let .specific(providerRaw, modelRaw) = store.collectionSearchSettings.model {
                Text(modelRaw).tag(
                    CollectionSearchAIModelPreference.specific(
                        provider: providerRaw,
                        model: modelRaw,
                    ),
                )
            }
        }
        .disabled(store.collectionSearchSelectedProvider == nil)

        Picker("Thinking", selection: Binding(
            get: { store.collectionSearchSettings.thinking },
            set: { store.send(.collectionSearchThinkingChanged($0)) },
        )) {
            ForEach(thinkingOptions, id: \.selection) { option in
                if let selection = option.selection {
                    Text(option.title).tag(Self.preference(from: selection))
                } else {
                    Text(option.title).tag(CollectionSearchAIThinkingPreference.providerDefault)
                }
            }
        }
        .disabled(store.collectionSearchSelectedModel == nil && store.collectionSearchSelectedProvider == nil)

        HStack {
            Button("Reset to Defaults") {
                store.send(.collectionSearchResetTapped)
            }
            Spacer()
        }

        VStack(alignment: .leading) {
            Text(Self.collectionSearchFooterText)
            Text(Self.collectionSearchAutoExplanationText)
            if let error = store.collectionSearchLoadError {
                Text(error)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private extension AiSettingsView {
    var connectionGuidance: some View {
        Text(Self.connectionGuidanceText)
            .foregroundStyle(.secondary)
    }

    private var defaultChatSummaryText: String {
        Self.defaultChatSummary(
            settings: store.chatDefaultSettings,
            providerDisplayName: defaultChatProviderDisplayName,
            modelDisplayName: store.chatSelectedModel?.displayName,
            providerUnavailable: store.chatSelectedProviderIsUnavailable,
            modelUnavailable: store.chatSelectedModelIsUnavailable,
            thinkingUnavailable: store.chatThinkingIsUnavailable,
        )
    }

    private var collectionSearchSummaryText: String {
        Self.collectionSearchSummary(
            settings: store.collectionSearchSettings,
            providerDisplayName: collectionSearchProviderDisplayName,
            modelDisplayName: store.collectionSearchSelectedModel?.displayName,
            providerUnavailable: collectionSearchProviderIsUnavailable,
            modelUnavailable: collectionSearchModelIsUnavailable,
        )
    }

    private var defaultChatProviderDisplayName: String? {
        guard let selection = store.chatDefaultSettings.provider else { return nil }
        return store.connectedProviderDescriptors.first {
            $0.provider.rawValue == selection.rawValue
        }?.displayName
    }

    private var collectionSearchProviderDisplayName: String? {
        guard case let .specific(rawValue) = store.collectionSearchSettings.provider else { return nil }
        return store.connectedProviderDescriptors.first {
            $0.provider.rawValue == rawValue
        }?.displayName
    }

    private var collectionSearchProviderIsUnavailable: Bool {
        guard case .specific = store.collectionSearchSettings.provider else { return false }
        return collectionSearchProviderDisplayName == nil
    }

    private var collectionSearchModelIsUnavailable: Bool {
        guard case .specific = store.collectionSearchSettings.model else { return false }
        return store.collectionSearchSelectedModel == nil
    }

    private func disclosureBinding(for editor: ModelSettingsEditor) -> Binding<Bool> {
        Binding(
            get: { expandedEditors.contains(editor) },
            set: { isExpanded in
                expandedEditors = Self.nextEditors(expandedEditors, editor, isExpanded)
            },
        )
    }

    private func settingsSummaryLabel(title: String, summary: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

extension AiSettingsView {
    static func nextEditors(
        _ current: Set<ModelSettingsEditor>,
        _ editor: ModelSettingsEditor,
        _ expanded: Bool,
    ) -> Set<ModelSettingsEditor> {
        var next = current
        if expanded {
            next.insert(editor)
        } else {
            next.remove(editor)
        }
        return next
    }

    static func defaultChatSummary(
        settings: AiChatDefaultSettings,
        providerDisplayName: String? = nil,
        modelDisplayName: String? = nil,
        providerUnavailable: Bool = false,
        modelUnavailable: Bool = false,
        thinkingUnavailable: Bool = false,
    ) -> String {
        guard let provider = settings.provider else { return notConfiguredSummaryText }

        var providerTitle = providerDisplayName ?? provider.rawValue
        if providerUnavailable {
            providerTitle = unavailableLabel(providerTitle)
        }

        var modelTitle = settings.model.map { modelDisplayName ?? $0.modelRawValue } ?? "No model selected"
        if settings.model != nil, modelUnavailable {
            modelTitle = unavailableLabel(modelTitle)
        }

        var thinking = thinkingTitle(for: settings.thinking)
        if thinkingUnavailable {
            thinking = unavailableLabel(thinking)
        }

        return [providerTitle, modelTitle, thinking].joined(separator: " · ")
    }

    static func collectionSearchSummary(
        settings: CollectionSearchAISettings,
        providerDisplayName: String? = nil,
        modelDisplayName: String? = nil,
        providerUnavailable: Bool = false,
        modelUnavailable: Bool = false,
    ) -> String {
        if case .auto = settings.provider,
           case .auto = settings.model,
           case .providerDefault = settings.thinking
        {
            return collectionSearchAutomaticSummary
        }

        let providerTitle: String = switch settings.provider {
        case .auto:
            collectionSearchAutoProviderSummary
        case let .specific(rawValue):
            unavailableTitleIfNeeded(
                providerDisplayName ?? rawValue,
                isUnavailable: providerUnavailable,
            )
        }
        let modelTitle: String = switch settings.model {
        case .auto:
            collectionSearchAutoModelSummary
        case let .specific(_, rawValue):
            unavailableTitleIfNeeded(
                modelDisplayName ?? rawValue,
                isUnavailable: modelUnavailable,
            )
        }

        return [providerTitle, modelTitle, thinkingTitle(for: settings.thinking)]
            .joined(separator: " · ")
    }

    static func unavailableLabel(_ value: String) -> String {
        "\(value) (Unavailable)"
    }

    private static func unavailableTitleIfNeeded(_ title: String, isUnavailable: Bool) -> String {
        isUnavailable ? unavailableLabel(title) : title
    }
}

private extension AiSettingsView {
    var chatCanSelectModel: Bool {
        store.chatSelectedProviderIsAvailable
            && store.chatModelCatalogPhase == .loaded
            && !store.chatAvailableModels.isEmpty
    }

    private var chatModelPlaceholder: String {
        guard store.chatDefaultSettings.provider != nil else { return "Select a provider first" }
        guard store.chatSelectedProviderIsAvailable else { return "Provider unavailable" }

        switch store.chatModelCatalogPhase {
        case .idle:
            return "Select a model"
        case .loading:
            return "Loading models…"
        case .loaded:
            return store.chatAvailableModels.isEmpty ? "No models available" : "Select a model"
        case .failed:
            return "Models unavailable"
        }
    }

    private static func thinkingTitle(for selection: AiThinkingSelection) -> String {
        CollectionSearchAISelectionPolicy.thinkingLabel(for: selection)
    }

    private static func thinkingTitle(for selection: PersistedAIThinkingSelection) -> String {
        switch selection {
        case .providerDefault:
            "Provider default"
        case .none:
            "none"
        case let .effort(value):
            value
        case let .tokenBudget(value):
            "\(value) tokens"
        }
    }

    private static func thinkingTitle(for selection: CollectionSearchAIThinkingPreference) -> String {
        switch selection {
        case .providerDefault:
            "Provider default"
        case .none:
            "none"
        case let .effort(value):
            value
        case let .tokenBudget(value):
            "\(value) tokens"
        }
    }

    private static func thinkingSelection(from selection: PersistedAIThinkingSelection) -> AiThinkingSelection? {
        switch selection {
        case .providerDefault:
            nil
        case .none:
            .some(AiThinkingSelection.none)
        case let .effort(value):
            AiThinkingEffort(rawValue: value).map(AiThinkingSelection.effort)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }

    private static func persistedThinking(from selection: AiThinkingSelection?) -> PersistedAIThinkingSelection {
        guard let selection else { return .providerDefault }
        switch selection {
        case .none:
            return PersistedAIThinkingSelection.none
        case let .effort(effort):
            return .effort(effort.rawValue)
        case let .tokenBudget(value):
            return .tokenBudget(value)
        }
    }

    private static func preference(from selection: AiThinkingSelection) -> CollectionSearchAIThinkingPreference {
        switch selection {
        case .none:
            .none
        case let .effort(effort):
            .effort(effort.rawValue)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }
}
