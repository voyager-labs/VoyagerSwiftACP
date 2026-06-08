import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection

struct AiSettingsView: View {
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
                if store.bootstrapPhase == .failed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Failed to load AI connections.")
                        Button("Retry") {
                            store.send(.retryBootstrapTapped)
                        }
                    }
                } else {
                    ForEach(store.scope(state: \.rows, action: \.row)) { rowStore in
                        AiConnectionRowView(store: rowStore)
                    }
                }
            } header: {
                Text("AI Connections")
            } footer: {
                Text("Connect AI providers to enable intelligent features in Voyager.")
                    .font(.footnote)
            }

            Section {
                if store.hasConnectedProviders {
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
                } else {
                    Text("Connect an AI provider to enable collection search AI settings.")
                        .foregroundStyle(.secondary)
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
            } header: {
                Text("Collection Search AI")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These preferences are stored locally and used by collection search only.")
                    if let error = store.collectionSearchLoadError {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private static func thinkingTitle(for selection: AiThinkingSelection) -> String {
        CollectionSearchAISelectionPolicy.thinkingLabel(for: selection)
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
