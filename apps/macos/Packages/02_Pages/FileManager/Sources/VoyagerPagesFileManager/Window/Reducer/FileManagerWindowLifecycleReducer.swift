import ComposableArchitecture
import Foundation
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared

@Reducer
struct FileManagerWindowLifecycleReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.metricsClient)
    var metricsClient
    @Dependency(\.aiChatProductMetricsClient)
    var aiChatProductMetricsClient
    @Dependency(\.composerMetricClient)
    var composerMetricClient
    @Dependency(\.fileManagerProductMetricsClient)
    var productMetricsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                if shouldLogDailyFileManagerOpen(userDefaultsClient) {
                    metricsClient.logMetric(
                        "voyager_file_manager_first_open",
                        1,
                        ["date": currentDateKey()],
                    )
                }

                return .merge(
                    .send(.content(.entryViewLayout(.entryArrangements(.setSortKey(
                        state.content.entryViewLayout.entryArrangements.sortKey,
                    ))))),
                    .send(.content(.entryViewLayout(.entryArrangements(.setSortOrder(
                        state.content.entryViewLayout.entryArrangements.sortOrder,
                    ))))),
                    .send(.content(.entryViewLayout(.entryArrangements(.setGroupKey(
                        state.content.entryViewLayout.entryArrangements.groupKey,
                    ))))),
                    .send(.content(.internal(.applyNavigationState(state.content.navigation.navigationState)))),
                )

            case .onDisappear:
                return teardownWindowOwnedChildOperations(state: &state)

            default:
                return .none
            }
        }
    }

    private func teardownWindowOwnedChildOperations(state: inout State) -> Effect<Action> {
        recordPendingContentEntryMetrics(state: &state)
        recordPendingSidebarEntryMetrics(state: &state)
        recordBrowsingUnavailabilityDuringWindowTeardown(state: &state)
        let recordedMetricKeys = LockIsolated<Set<FileManagerWindowTeardownMetricKey>>([])
        let aiChatProductMetricsClient = aiChatProductMetricsClient
        let composerMetricClient = composerMetricClient
        var deduplicatingComposerMetricClient = composerMetricClient
        deduplicatingComposerMetricClient.recordProductMetric = { metric in
            guard recordedMetricKeys.withValue({ $0.insert(metric.teardownMetricKey).inserted }) else { return }
            composerMetricClient.record(metric)
        }

        var effects: [Effect<Action>] = []
        withDependencies {
            $0.aiChatProductMetricsClient = AiChatProductMetricsClient { metric in
                guard let key = metric.teardownMetricKey else {
                    aiChatProductMetricsClient.record(metric)
                    return
                }
                guard recordedMetricKeys.withValue({ $0.insert(key).inserted }) else { return }
                aiChatProductMetricsClient.record(metric)
            }
            $0.composerMetricClient = deduplicatingComposerMetricClient
        } operation: {
            effects.append(contentsOf: teardownContentState(&state.content) {
                .content($0)
            })
            effects.append(contentsOf: teardownTabContentStates(state: &state))

            effects.append(teardownAiChatState(&state.inspector.aiChat) {
                .inspector(.aiChat($0))
            })
            effects.append(contentsOf: teardownTabInspectorStates(state: &state))
            effects.append(contentsOf: teardownBackgroundAiChatStates(state: &state))
            effects.append(contentsOf: teardownBackgroundInspectorAiChatStates(state: &state))
        }
        return .merge(effects)
    }

    private func recordBrowsingUnavailabilityDuringWindowTeardown(state: inout State) {
        var consumedOperationIDs = Set<UUID>()
        if let metric = consumePendingBrowsingUnavailability(
            state: &state.content,
            consumedOperationIDs: &consumedOperationIDs,
        ) {
            productMetricsClient.record(metric)
        }
        for tabID in Array(state.tabContentStates.keys) {
            guard var content = state.tabContentStates[tabID] else { continue }
            if let metric = consumePendingBrowsingUnavailability(
                state: &content,
                consumedOperationIDs: &consumedOperationIDs,
            ) {
                productMetricsClient.record(metric)
            }
            state.tabContentStates[tabID] = content
        }
    }

    private func recordPendingContentEntryMetrics(state: inout State) {
        for (_, pending) in state.pendingContentEntryCommands {
            guard state.recordedContentEntryCommandIDs.insert(pending.metadata.id).inserted else { continue }
            productMetricsClient.record(FileManagerProductMetricsProducer.entryTerminal(
                operationID: pending.metadata.id,
                identity: pending.metadata.interaction,
                source: pending.metadata.source,
                result: .unavailable,
                aggregate: pending.aggregate,
            ))
        }
        state.pendingContentEntryCommands.removeAll()
    }

    private func recordPendingSidebarEntryMetrics(state: inout State) {
        for (_, pending) in state.pendingSidebarEntryCommands {
            guard state.recordedSidebarEntryCommandIDs.insert(pending.metadata.id).inserted else { continue }
            productMetricsClient.record(FileManagerProductMetricsProducer.entryTerminal(
                operationID: pending.metadata.id,
                identity: pending.metadata.interaction,
                source: pending.metadata.source,
                result: .unavailable,
                aggregate: pending.aggregate,
            ))
        }
        state.pendingSidebarEntryCommands.removeAll()
    }

    private func teardownTabContentStates(state: inout State) -> [Effect<Action>] {
        var effects: [Effect<Action>] = []
        for tabID in Array(state.tabContentStates.keys) {
            guard var content = state.tabContentStates[tabID] else { continue }
            effects.append(contentsOf: teardownContentState(&content) {
                .tabContent(tabID: tabID, action: $0)
            })
            state.tabContentStates[tabID] = content
        }
        return effects
    }

    private func teardownTabInspectorStates(state: inout State) -> [Effect<Action>] {
        var effects: [Effect<Action>] = []
        for tabID in Array(state.tabInspectorStates.keys) {
            guard var inspector = state.tabInspectorStates[tabID] else { continue }
            effects.append(teardownAiChatState(&inspector.aiChat) {
                .backgroundInspectorAiChat($0)
            })
            state.tabInspectorStates[tabID] = inspector
        }
        return effects
    }

    private func teardownBackgroundAiChatStates(state: inout State) -> [Effect<Action>] {
        var effects: [Effect<Action>] = []
        for sessionID in Array(state.backgroundAiChatStates.keys) {
            guard var content = state.backgroundAiChatStates[sessionID] else { continue }
            effects.append(teardownAiChatState(&content.aiChat) {
                .backgroundAiChat($0)
            })
            state.backgroundAiChatStates[sessionID] = content
        }
        return effects
    }

    private func teardownBackgroundInspectorAiChatStates(state: inout State) -> [Effect<Action>] {
        var effects: [Effect<Action>] = []
        for sessionID in Array(state.backgroundInspectorAiChatStates.keys) {
            guard var inspector = state.backgroundInspectorAiChatStates[sessionID] else { continue }
            effects.append(teardownAiChatState(&inspector.aiChat) {
                .backgroundInspectorAiChat($0)
            })
            state.backgroundInspectorAiChatStates[sessionID] = inspector
        }
        return effects
    }

    private func teardownContentState(
        _ state: inout FileManagerContentFeature.State,
        map: @escaping @Sendable (FileManagerContentFeature.Action) -> Action,
    ) -> [Effect<Action>] {
        [
            AiChatFeature()
                .reduce(into: &state.aiChat, action: .teardownRequested)
                .map { map(.aiChat($0)) },
            ComposerFeature()
                .reduce(into: &state.composer, action: .internal(.cleanupCollectionWork))
                .map { map(.composer($0)) },
        ]
    }

    private func teardownAiChatState(
        _ state: inout AiChatFeature.State,
        map: @escaping @Sendable (AiChatAction) -> Action,
    ) -> Effect<Action> {
        AiChatFeature()
            .reduce(into: &state, action: .teardownRequested)
            .map(map)
    }
}

private enum FileManagerWindowTeardownMetricKey: Hashable {
    case aiChat(UUID)
    case composerQuery(UUID)
    case composerApply(UUID)
}

private extension AiChatProductMetric {
    var teardownMetricKey: FileManagerWindowTeardownMetricKey? {
        switch self {
        case .turnSubmitted:
            nil
        case let .turnResult(operationID, _, _, _):
            .aiChat(operationID)
        }
    }
}

private extension ComposerProductMetric {
    var teardownMetricKey: FileManagerWindowTeardownMetricKey {
        switch self {
        case let .queryResult(operationID, _, _):
            .composerQuery(operationID)
        case let .applyResult(operationID, _, _):
            .composerApply(operationID)
        }
    }
}

private func shouldLogDailyFileManagerOpen(_ userDefaultsClient: UserDefaultsClient) -> Bool {
    let key = "voyager.file_manager.first_open_date"
    let today = currentDateKey()
    let lastValue = userDefaultsClient.string(key)
    if lastValue == today {
        return false
    }
    userDefaultsClient.setString(today, key)
    return true
}

private func currentDateKey() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}
